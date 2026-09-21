import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// One user-started render at a time. iOS 26 can keep the AVFoundation pipeline
/// running after the app is backgrounded; older releases get only UIKit's
/// expiring grace period and must never be presented as guaranteed background work.
@MainActor
final class BackgroundExportSupport {
    static let shared = BackgroundExportSupport()

    private static let taskPrefix = "com.prakashash18.tripreel.video-export"
    private var isRegistered = false
    private var pendingLaunch: ((AnyObject) -> Void)?
    private var pendingContinuation: CheckedContinuation<Bool, Never>?
    private var activeTask: AnyObject?
    private var activeRequestID: String?
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private var expirationAction: (() -> Void)?

    private init() {}

    func register() {
        guard #available(iOS 26.0, *), !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskPrefix + ".*",
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else { return }
            Task { @MainActor in
                guard let self, let launch = self.pendingLaunch else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.pendingLaunch = nil
                self.activeTask = task
                launch(task)
            }
        }
    }

    /// Call immediately after an explicit Export tap, before accessing media.
    /// Returns true only when the system accepted continuous processing.
    func begin(onExpiration: @escaping () -> Void) async -> Bool {
        expirationAction = onExpiration
        if #available(iOS 26.0, *), isRegistered {
            let identifier = Self.taskPrefix + "." + UUID().uuidString
            activeRequestID = identifier
            let accepted = await withCheckedContinuation { continuation in
                pendingContinuation = continuation
                pendingLaunch = { [weak self] launchedTask in
                    guard let task = launchedTask as? BGContinuedProcessingTask else {
                        self?.pendingContinuation?.resume(returning: false)
                        self?.pendingContinuation = nil
                        return
                    }
                    task.progress.totalUnitCount = 100
                    task.expirationHandler = { [weak self] in
                        Task { @MainActor in self?.expirationAction?() }
                    }
                    self?.pendingContinuation?.resume(returning: true)
                    self?.pendingContinuation = nil
                }
                let request = BGContinuedProcessingTaskRequest(
                    identifier: identifier,
                    title: "Rendering your memory",
                    subtitle: "Preparing your video"
                )
                request.strategy = .fail
                do {
                    try BGTaskScheduler.shared.submit(request)
                } catch {
                    pendingLaunch = nil
                    activeRequestID = nil
                    pendingContinuation?.resume(returning: false)
                    pendingContinuation = nil
                }
            }
            if accepted { return true }
        }

        guard !Task.isCancelled else { return false }

        graceTask = UIApplication.shared.beginBackgroundTask(withName: "Finish memory export") { [weak self] in
            Task { @MainActor in
                self?.expirationAction?()
                self?.endGraceTask()
            }
        }
        return false
    }

    func updateProgress(_ fraction: Double) {
        guard #available(iOS 26.0, *),
              let activeTask = activeTask as? BGContinuedProcessingTask else { return }
        let percent = Int(max(0, min(1, fraction)) * 100)
        activeTask.progress.completedUnitCount = Int64(percent)
        activeTask.updateTitle("Rendering your memory", subtitle: "\(percent)% complete")
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
        endGraceTask()
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
