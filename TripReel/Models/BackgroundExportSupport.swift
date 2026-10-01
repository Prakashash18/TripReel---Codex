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
    private var lastTitlePercent = -1
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
                        launchedTask.setTaskCompleted(success: true)
                        return
                    }
                    guard let task = launchedTask as? BGContinuedProcessingTask else {
                        self.record("launch-type-mismatch")
                        self.resumePendingLaunch(accepted: false)
                        launchedTask.setTaskCompleted(success: true)
                        return
                    }
                    guard let launch = self.pendingLaunch else {
                        self.record("launch-without-pending-export")
                        task.setTaskCompleted(success: true)
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
                        task.progress.totalUnitCount = 1000
                        task.progress.completedUnitCount = 1
                        task.expirationHandler = { [weak self] in
                            Task { @MainActor in
                                guard let self else { return }
                                self.interruptionMessage = "iOS ended an active background export because the phone needed its resources. Open this story and try exporting again. Diagnostic: continued-task-expired."
                                self.record("continued-task-expired " + Self.deviceConditions())
                                self.expirationAction?()
                                // Progress is checkpointed, so this is a pause, not a failure.
                                self.finish(success: true)
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
        // Tenths of a percent: iOS judges a continued task by how steadily its progress moves,
        // so report every small step, not only whole percents.
        activeTask.progress.completedUnitCount = max(activeTask.progress.completedUnitCount, Int64(max(0, min(1, fraction)) * 1000))
        guard percent != lastTitlePercent else { return }
        lastTitlePercent = percent
        activeTask.updateTitle("Rendering your memory", subtitle: "\(percent)% complete")
        if percent != lastReportedPercent, percent.isMultiple(of: 10) {
            lastReportedPercent = percent
            record("continued-task-progress \(percent)")
        }
    }

    func finish(success: Bool) {
        if #available(iOS 26.0, *), let activeTask = activeTask as? BGContinuedProcessingTask {
            // Always report success to iOS. A `false` leaves a "Task failed" row in
            // the Dynamic Island / Live Activity area that lingers; failures and
            // pauses are already explained inside the app, and finished pieces
            // are checkpointed.
            activeTask.setTaskCompleted(success: true)
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
        lastTitlePercent = -1
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

    /// What the phone was doing when iOS ended the task. Kept in the diagnostic log so a
    /// pattern (heat, Low Power Mode, little memory) can be spotted across attempts.
    private static func deviceConditions() -> String {
        let thermal = ProcessInfo.processInfo.thermalState
        let thermalName = ["nominal", "fair", "serious", "critical"][min(max(thermal.rawValue, 0), 3)]
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = Int(UIDevice.current.batteryLevel * 100)
        let free = Int(os_proc_available_memory() / 1_048_576)
        return "thermal=\(thermalName) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled) battery=\(battery)% freeMemoryMB=\(free)"
    }

    /// Sent when iOS pauses a render in the background, so the person knows to come back.
    func notifyPaused(percent: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your film is \(percent)% done"
        content.body = "iOS paused it in the background. Open Memories and it carries on from here."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "memory-paused",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }

    func notifyIfBackgrounded() async {
        guard UIApplication.shared.applicationState != .active else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your memory is ready"
        content.body = "Open Memories to save the video or share it. It stays in My exports for a while, but saving to Photos keeps it for good."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "memory-ready-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }
}

/// A finished film kept on this iPhone ("My exports"). Nothing is uploaded: the file stays in
/// the app's private storage until it expires or the person deletes it. A full 1080p film is kept
/// for seven days so it can be saved or shared again; the free preview is kept for a day.
struct LocalCompletedExport: Codable, Identifiable, Equatable {
    let id: String
    let fileName: String
    var title: String
    let durationSeconds: Double
    let isHD: Bool
    let completedAt: Date
    /// False until the film has been shown once, so a render that finished while the app was
    /// closed opens on the ready screen next launch, and only once.
    var seen: Bool

    static let interruptedKey = "memories.export-in-progress.v1"
    static let fullFilmLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let previewLifetime: TimeInterval = 24 * 60 * 60
    static let maximumKept = 5
    private static let indexName = "shelf.json"
    private static let legacyReceiptName = "completed-export.json"

    /// Tests point this at a temporary folder so they never touch the real shelf.
    nonisolated(unsafe) static var directoryOverride: URL?

    static var directory: URL {
        directoryOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CompletedExport", isDirectory: true)
    }

    var fileURL: URL { Self.directory.appendingPathComponent(fileName) }
    var lifetime: TimeInterval { isHD ? Self.fullFilmLifetime : Self.previewLifetime }
    var expiresAt: Date { completedAt.addingTimeInterval(lifetime) }

    func remaining(now: Date = Date()) -> TimeInterval { expiresAt.timeIntervalSince(now) }

    /// "6 days left", "5 hours left".
    func remainingDescription(now: Date = Date()) -> String {
        let seconds = max(0, remaining(now: now))
        let days = Int((seconds / 86_400).rounded(.up))
        if seconds >= 86_400 { return days == 1 ? "1 day left" : "\(days) days left" }
        let hours = max(1, Int((seconds / 3_600).rounded(.up)))
        return hours == 1 ? "1 hour left" : "\(hours) hours left"
    }

    // MARK: Shelf

    /// Newest first. Expired and missing films are removed as a side effect.
    static func all(now: Date = Date()) -> [Self] {
        migrateLegacyReceipt()
        let stored = readIndex()
        var kept: [Self] = []
        for item in stored {
            if now < item.expiresAt, FileManager.default.fileExists(atPath: item.fileURL.path) {
                kept.append(item)
            } else {
                try? FileManager.default.removeItem(at: item.fileURL)
            }
        }
        if kept.count != stored.count { writeIndex(kept) }
        return kept.sorted { $0.completedAt > $1.completedAt }
    }

    /// A finished film that has not been shown yet.
    static func latestUnseen(now: Date = Date()) -> Self? {
        all(now: now).first { !$0.seen }
    }

    @discardableResult
    static func keep(
        _ renderedURL: URL,
        title: String,
        durationSeconds: Double,
        isHD: Bool,
        now: Date = Date()
    ) throws -> Self {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)

        let identifier = UUID().uuidString
        let receipt = Self(
            id: identifier,
            fileName: "memory-\(identifier).mp4",
            title: title,
            durationSeconds: durationSeconds,
            isHD: isHD,
            completedAt: now,
            seen: false
        )
        try FileManager.default.moveItem(at: renderedURL, to: receipt.fileURL)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: receipt.fileURL.path
        )
        var shelf = all(now: now) + [receipt]
        shelf.sort { $0.completedAt > $1.completedAt }
        // Only the newest few stay, so films cannot quietly fill the phone.
        for extra in shelf.dropFirst(maximumKept) { try? FileManager.default.removeItem(at: extra.fileURL) }
        shelf = Array(shelf.prefix(maximumKept))
        writeIndex(shelf)
        guard shelf.contains(receipt) else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        return receipt
    }

    static func markSeen(_ id: String) {
        var shelf = all()
        guard let index = shelf.firstIndex(where: { $0.id == id }), !shelf[index].seen else { return }
        shelf[index].seen = true
        writeIndex(shelf)
    }

    static func remove(_ id: String) {
        let shelf = all()
        if let item = shelf.first(where: { $0.id == id }) { try? FileManager.default.removeItem(at: item.fileURL) }
        writeIndex(shelf.filter { $0.id != id })
    }

    static func discardAll() {
        for item in readIndex() { try? FileManager.default.removeItem(at: item.fileURL) }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(indexName))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(legacyReceiptName))
    }

    // MARK: Storage

    private static func readIndex() -> [Self] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(indexName)),
              let items = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return items
    }

    private static func writeIndex(_ items: [Self]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: directory.appendingPathComponent(indexName), options: .atomic)
    }

    /// Versions before the shelf kept one film and a single receipt. Move it across once.
    private struct LegacyReceipt: Codable {
        let fileName: String
        let title: String
        let durationSeconds: Double
        let isHD: Bool
        let completedAt: Date
    }

    private static func migrateLegacyReceipt() {
        let legacyURL = directory.appendingPathComponent(legacyReceiptName)
        guard let data = try? Data(contentsOf: legacyURL) else { return }
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        guard let legacy = try? JSONDecoder().decode(LegacyReceipt.self, from: data),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(legacy.fileName).path) else { return }
        var shelf = readIndex()
        shelf.append(Self(
            id: UUID().uuidString, fileName: legacy.fileName, title: legacy.title,
            durationSeconds: legacy.durationSeconds, isHD: legacy.isHD,
            completedAt: legacy.completedAt, seen: false
        ))
        writeIndex(shelf)
    }
}
