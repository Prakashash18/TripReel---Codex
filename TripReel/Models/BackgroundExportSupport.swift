import BackgroundTasks
import Foundation
import OSLog
import UIKit
import UserNotifications

/// One user-started render at a time. iOS 26 can keep the AVFoundation pipeline
/// running after the app is backgrounded; older releases get only UIKit's
/// expiring grace period and must never be presented as guaranteed background work.
@MainActor
final class BackgroundExportSupport {
    static let shared = BackgroundExportSupport()

    private static let taskPrefix = "com.prakashash18.tripreel.video-export"
    private static let diagnosticKey = "memories.background-export-diagnostic.v1"
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.prakashash18.tripreel",
        category: "BackgroundExport"
    )
    private var pendingLaunch: ((AnyObject) -> Void)?
    private var pendingContinuation: CheckedContinuation<Bool, Never>?
    private var activeTask: AnyObject?
    private var activeRequestID: String?
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private var expirationAction: (() -> Void)?
    private var lastReportedPercent = -1
    private(set) var interruptionMessage = "iOS stopped the background render. Open this story and try exporting again."

    private init() {}

    /// Call immediately after an explicit Export tap, before accessing media.
    /// Returns true only when the system accepted continuous processing.
    func begin(onExpiration: @escaping () -> Void) async -> Bool {
        UserDefaults.standard.removeObject(forKey: Self.diagnosticKey)
        record("begin ios=\(UIDevice.current.systemVersion)")
        expirationAction = onExpiration
        interruptionMessage = "iOS stopped the background render. Open this story and try exporting again."
        if #available(iOS 26.0, *) {
            let identifier = Self.taskPrefix + "." + UUID().uuidString
            activeRequestID = identifier
            let registered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier,
                using: nil
            ) { [weak self] launchedTask in
                Task { @MainActor in
                    guard let self else {
                        launchedTask.setTaskCompleted(success: false)
                        return
                    }
                    guard let task = launchedTask as? BGContinuedProcessingTask else {
                        self.record("launch-type-mismatch")
                        self.resumePendingLaunch(accepted: false)
                        launchedTask.setTaskCompleted(success: false)
                        return
                    }
                    guard let launch = self.pendingLaunch else {
                        self.record("launch-without-pending-export")
                        task.setTaskCompleted(success: false)
                        return
                    }
                    self.pendingLaunch = nil
                    self.activeTask = task
                    launch(task)
                }
            }

            if registered {
                record("registration-succeeded")
                let accepted = await withCheckedContinuation { continuation in
                    pendingContinuation = continuation
                    pendingLaunch = { [weak self] launchedTask in
                        guard let self,
                              let task = launchedTask as? BGContinuedProcessingTask else {
                            self?.resumePendingLaunch(accepted: false)
                            return
                        }
                        task.progress.totalUnitCount = 100
                        task.progress.completedUnitCount = 1
                        task.expirationHandler = { [weak self] in
                            Task { @MainActor in
                                guard let self else { return }
                                self.interruptionMessage = "iOS ended an active background export because the phone needed its resources. Open this story and try exporting again. Diagnostic: continued-task-expired."
                                self.record("continued-task-expired")
                                self.expirationAction?()
                            }
                        }
                        self.record("continued-task-started")
                        self.resumePendingLaunch(accepted: true)
                    }
                    let request = BGContinuedProcessingTaskRequest(
                        identifier: identifier,
                        title: "Rendering your memory",
                        subtitle: "Preparing your video"
                    )
                    request.strategy = .fail
                    // The renderer deliberately uses the default CPU/network resources here.
                    // Requesting `.gpu` requires a distribution entitlement that isn't
                    // available in the current App Store provisioning profile.
                    record("requesting-default-resources")
                    do {
                        try BGTaskScheduler.shared.submit(request)
                        record("continued-task-submitted")
                    } catch {
                        let nsError = error as NSError
                        record(
                            "submission-failed domain=\(nsError.domain) code=\(nsError.code) "
                                + nsError.localizedDescription
                        )
                        interruptionMessage = Self.submissionFailureMessage(for: nsError)
                        pendingLaunch = nil
                        activeRequestID = nil
                        resumePendingLaunch(accepted: false)
                    }
                }
                if accepted { return true }
            } else {
                record("registration-failed")
                interruptionMessage = "Background export could not start because iOS rejected its task registration. Keep Memories open while exporting. Diagnostic: registration-failed."
            }
        } else {
            record("continued-task-unavailable ios=\(UIDevice.current.systemVersion)")
            interruptionMessage = "This iOS version only gives the export a short background grace period. Keep Memories open while exporting. Diagnostic: continued-task-unavailable."
        }

        guard !Task.isCancelled else { return false }

        graceTask = UIApplication.shared.beginBackgroundTask(withName: "Finish memory export") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.record("grace-period-expired")
                self.expirationAction?()
                self.endGraceTask()
            }
        }
        record("using-grace-period reason=\(interruptionMessage)")
        return false
    }

    func updateProgress(_ fraction: Double) {
        guard #available(iOS 26.0, *),
              let activeTask = activeTask as? BGContinuedProcessingTask else { return }
        let percent = Int(max(0, min(1, fraction)) * 100)
        activeTask.progress.completedUnitCount = Int64(percent)
        activeTask.updateTitle("Rendering your memory", subtitle: "\(percent)% complete")
        if percent != lastReportedPercent, percent.isMultiple(of: 10) {
            lastReportedPercent = percent
            record("continued-task-progress \(percent)")
        }
    }

    func finish(success: Bool) {
        if #available(iOS 26.0, *), let activeTask = activeTask as? BGContinuedProcessingTask {
            activeTask.setTaskCompleted(success: success)
            self.activeTask = nil
        } else if let activeRequestID {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: activeRequestID)
        }
        pendingLaunch = nil
        pendingContinuation?.resume(returning: false)
        pendingContinuation = nil
        activeRequestID = nil
        expirationAction = nil
        lastReportedPercent = -1
        endGraceTask()
        record("finished success=\(success)")
    }

    private func resumePendingLaunch(accepted: Bool) {
        pendingContinuation?.resume(returning: accepted)
        pendingContinuation = nil
    }

    private static func submissionFailureMessage(for error: NSError) -> String {
        let diagnostic = "Diagnostic: submit-\(error.code)."
        switch BGTaskScheduler.Error.Code(rawValue: error.code) {
        case .notPermitted:
            return "Background export is disabled or not permitted on this phone. Keep Memories open while exporting. \(diagnostic)"
        case .immediateRunIneligible:
            return "The phone was too busy to start a long background export. Keep Memories open while exporting, then try again later. \(diagnostic)"
        case .tooManyPendingTaskRequests:
            return "Another background export was still pending. Keep Memories open while exporting and try again. \(diagnostic)"
        case .unavailable:
            return "Long background export is unavailable on this phone right now. Keep Memories open while exporting. \(diagnostic)"
        case .none:
            return "Long background export could not start. Keep Memories open while exporting. \(diagnostic)"
        @unknown default:
            return "Long background export could not start. Keep Memories open while exporting. \(diagnostic)"
        }
    }

    private func record(_ event: String) {
        logger.info("\(event, privacy: .public)")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) | \(event)"
        let defaults = UserDefaults.standard
        let prior = defaults.stringArray(forKey: Self.diagnosticKey) ?? []
        defaults.set(Array((prior + [entry]).suffix(20)), forKey: Self.diagnosticKey)
    }

    var latestDiagnosticSummary: String? {
        UserDefaults.standard.stringArray(forKey: Self.diagnosticKey)?.last
    }

    private func endGraceTask() {
        guard graceTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(graceTask)
        graceTask = .invalid
    }

    func requestReadyNotificationPermission() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func notifyIfBackgrounded() async {
        guard UIApplication.shared.applicationState != .active else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your memory is ready"
        content.body = "Open Memories to save the video or create a seven-day link. It isn't saved automatically."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "memory-ready-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }
}

/// A finished render stays only on this device until the person saves it or
/// explicitly creates a share link. The small receipt restores the ready screen
/// after process termination; it does not upload or auto-save the MP4.
struct LocalCompletedExport: Codable {
    let fileName: String
    let title: String
    let durationSeconds: Double
    let isHD: Bool
    let completedAt: Date

    static let receiptName = "completed-export.json"
    static let interruptedKey = "memories.export-in-progress.v1"
    static let lifetime: TimeInterval = 24 * 60 * 60

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CompletedExport", isDirectory: true)
    }

    var fileURL: URL { Self.directory.appendingPathComponent(fileName) }

    static func load() -> Self? {
        let receiptURL = directory.appendingPathComponent(receiptName)
        guard let data = try? Data(contentsOf: receiptURL),
              let receipt = try? JSONDecoder().decode(Self.self, from: data),
              FileManager.default.fileExists(atPath: receipt.fileURL.path) else { return nil }
        guard Date().timeIntervalSince(receipt.completedAt) < lifetime else {
            try? FileManager.default.removeItem(at: receipt.fileURL)
            try? FileManager.default.removeItem(at: receiptURL)
            return nil
        }
        return receipt
    }

    static func keep(_ renderedURL: URL, title: String, durationSeconds: Double, isHD: Bool) throws -> Self {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let prior = load()
        let receipt = Self(
            fileName: "memory-\(UUID().uuidString).mp4",
            title: title,
            durationSeconds: durationSeconds,
            isHD: isHD,
            completedAt: Date()
        )
        try FileManager.default.moveItem(at: renderedURL, to: receipt.fileURL)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: receipt.fileURL.path
        )
        do {
            let data = try JSONEncoder().encode(receipt)
            try data.write(to: directory.appendingPathComponent(receiptName), options: .atomic)
            if let prior { try? FileManager.default.removeItem(at: prior.fileURL) }
            return receipt
        } catch {
            try? FileManager.default.removeItem(at: receipt.fileURL)
            throw error
        }
    }

    static func discard() {
        if let prior = load() { try? FileManager.default.removeItem(at: prior.fileURL) }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(receiptName))
    }
}
