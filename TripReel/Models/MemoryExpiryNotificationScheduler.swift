import Foundation
import UserNotifications

struct MemoryExpiryReminder: Equatable, Sendable {
    let identifier: String
    let memoryID: UUID
    let title: String
    let fireDate: Date
}

struct MemoryExpiryNotificationScheduler {
    static let identifierPrefix = "memory-expiry."
    private static let reminderLeadTime: TimeInterval = 24 * 60 * 60

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    static func reminders(for memories: [SharedMemory], now: Date = Date()) -> [MemoryExpiryReminder] {
        memories.compactMap { memory in
            guard memory.savedToPhoneAt == nil, memory.expiresAt > now else { return nil }
            let fireDate = memory.expiresAt.addingTimeInterval(-reminderLeadTime)
            // Do not repeatedly deliver a late reminder whenever the app opens.
            // New links are scheduled six days ahead, so their one-day warning
            // is already registered well before this point.
            guard fireDate > now else { return nil }
            return MemoryExpiryReminder(
                identifier: identifier(for: memory.id),
                memoryID: memory.id,
                title: memory.title,
                fireDate: fireDate
            )
        }
    }

    func synchronize(
        memories: [SharedMemory],
        requestAuthorizationIfNeeded: Bool = false
    ) async {
        let reminders = Self.reminders(for: memories)
        let desiredIdentifiers = Set(reminders.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let stalePendingIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !desiredIdentifiers.contains($0) }
        let staleDeliveredIdentifiers = delivered
            .map(\.request.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !desiredIdentifiers.contains($0) }
        if !stalePendingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stalePendingIdentifiers)
        }
        if !staleDeliveredIdentifiers.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIdentifiers)
        }

        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, requestAuthorizationIfNeeded {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else { return }

        let pendingIdentifiers = Set(pending.map(\.identifier))
        for reminder in reminders where !pendingIdentifiers.contains(reminder.identifier) {
            let content = UNMutableNotificationContent()
            content.title = "Your memory expires tomorrow"
            content.body = "“\(reminder.title)” has one day left. Download it to Photos if you want to keep it."
            content.sound = .default
            content.userInfo = ["memory_id": reminder.memoryID.uuidString.lowercased()]

            let components = Calendar.current.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: reminder.fireDate
            )
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancel(memoryID: UUID) {
        let identifier = Self.identifier(for: memoryID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let identifiers = Set(pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) } + delivered
            .map(\.request.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) })
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(identifiers))
        center.removeDeliveredNotifications(withIdentifiers: Array(identifiers))
    }

    private static func identifier(for memoryID: UUID) -> String {
        identifierPrefix + memoryID.uuidString.lowercased()
    }
}

struct MonthlyExportResetNotificationScheduler {
    static let identifier = "monthly-export-reset"

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.center = center
        self.calendar = calendar
    }

    static func nextResetDate(
        after date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return nil
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextMonth)
    }

    func isScheduled() async -> Bool {
        await center.pendingNotificationRequests().contains { $0.identifier == Self.identifier }
    }

    func schedule(for resetDate: Date) async -> Bool {
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else { return false }

        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])

        let content = UNMutableNotificationContent()
        content.title = "Your free exports are back"
        content.body = "You have 3 free full-story exports ready in Memories."
        content.sound = .default

        let components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: resetDate
        )
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
