import Foundation
import UserNotifications

/// The reminder side-effect hook called by ``EntryService`` (D9). Kept a protocol
/// so the service stays testable without the notification system.
public protocol ReminderScheduling: AnyObject {
    /// (Re)schedules or cancels an entry's local notification to match its current
    /// state — cancels when completed / no reminder / fire time past (D9.5).
    func reschedule(for entry: Entry)
    /// Cancels any pending notification for the entry (on delete).
    func cancel(entryId: String)
}

/// Routes a tapped reminder to the Calendar tab at the entry's day (D9.4), and
/// keeps notifications visible while the app is foregrounded.
public final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    /// Set when a reminder is tapped; the Calendar view consumes and clears it.
    @Published public var pendingCalendarDate: Date?
    /// Tab index to select (0 = Calendar).
    @Published public var selectedTab: Int = 0

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let interval = response.notification.request.content.userInfo["calendarDate"] as? TimeInterval {
            DispatchQueue.main.async {
                self.selectedTab = 0
                self.pendingCalendarDate = Date(timeIntervalSince1970: interval)
            }
        }
        completionHandler()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Schedules local notifications for entry reminders (D9). Authorization is
/// requested on first use and the reminder control is gated on it (D9.3/D9.3a).
public final class ReminderScheduler: NSObject, ObservableObject, ReminderScheduling {
    @Published public private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    public let router: NotificationRouter

    public init(router: NotificationRouter) {
        self.router = router
        super.init()
        center.delegate = router
        refreshStatus()
    }

    public func refreshStatus() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { self.authorization = settings.authorizationStatus }
        }
    }

    /// Requests authorization (D9.3). Safe to call repeatedly.
    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            self.refreshStatus()
        }
    }

    public func reschedule(for entry: Entry) {
        center.removePendingNotificationRequests(withIdentifiers: [entry.id])
        guard
            !entry.isCompleted,
            let fire = ReminderTiming.fireDate(for: entry),
            ReminderTiming.shouldSchedule(fireDate: fire)
        else { return }

        let content = UNMutableNotificationContent()
        content.title = entry.title
        content.body = Self.bodyText(entry)
        if let day = entry.timeKey {
            content.userInfo = ["calendarDate": day.timeIntervalSince1970]
        }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: entry.id, content: content, trigger: trigger))
    }

    public func cancel(entryId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [entryId])
    }

    /// Notification body: the entry's time (D9.3).
    private static func bodyText(_ entry: Entry) -> String {
        if let s = entry.scheduled {
            return s.allDay ? "All day" : s.start.formatted(date: .abbreviated, time: .shortened)
        }
        if let d = entry.deadline {
            return "Due " + DateTimeUtilities.formatDeadline(d.date, hasTime: d.hasTime)
        }
        return ""
    }
}
