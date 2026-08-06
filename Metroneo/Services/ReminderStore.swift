import Foundation
import Combine

/// The companion's abstraction over the user's Apple Reminders (DESIGN R1). The
/// real store is ``EventKitReminderStore``; tests inject an in-memory fake, so the
/// join / sidecar / analytics logic above this never touches EventKit or its
/// permission prompt (R1.2). Nothing above the store sees an `EKReminder` — the
/// store's currency is the value types below.

/// Performance-bucket priority (R7). Maps to `EKReminder.priority`: none 0,
/// high 1, medium 5, low 9.
public enum ReminderPriority: Int, CaseIterable, Sendable, Equatable {
    case none, low, medium, high

    /// The label shown in the editor's 4-way picker.
    public var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// A Reminders list (an `EKCalendar` of type reminder) — the companion's grouping
/// unit (R5).
public struct ReminderList: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var isDefault: Bool
    public init(id: String, title: String, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}

/// A value snapshot of an `EKReminder` — the read/write currency of ``ReminderStore``.
/// The performance fields (rating, durations) are **not** here: they live in the
/// local sidecar, joined into a `TaskItem` a layer up (R2/R3).
public struct ReminderData: Identifiable, Equatable, Sendable {
    /// The reminder's stable external id (`calendarItemExternalIdentifier`); empty
    /// for a not-yet-saved reminder, filled in by ``ReminderStore/save(_:)``.
    public var id: String
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var isCompleted: Bool
    public var completionDate: Date?
    public var priority: ReminderPriority
    /// The list this reminder belongs to (empty ⇒ the default list on save).
    public var listId: String
    public var isRecurring: Bool
    /// Early-reminder alarms as **minutes before** the due date (R4.2).
    public var alarmOffsetMinutes: [Int]

    public init(
        id: String = "",
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        priority: ReminderPriority = .none,
        listId: String = "",
        isRecurring: Bool = false,
        alarmOffsetMinutes: [Int] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.priority = priority
        self.listId = listId
        self.isRecurring = isRecurring
        self.alarmOffsetMinutes = alarmOffsetMinutes
    }
}

/// Read/write access to Apple Reminders (DESIGN R1/R4/R5). All reads are async
/// (EventKit fetches on a background queue); writes are fire-and-forget and commit
/// immediately so changes sync out.
public protocol ReminderStore: AnyObject {
    /// Whether full access to Reminders has been granted (R1.1).
    var isAuthorized: Bool { get }
    /// Requests full access to Reminders; returns whether it was granted.
    func requestAccess() async -> Bool

    /// The user's reminder lists.
    func lists() -> [ReminderList]
    /// The list new reminders default to (`defaultCalendarForNewReminders`, R5.3).
    func defaultListId() -> String?

    /// Incomplete reminders in the given lists (`nil` ⇒ all authorized lists).
    func incompleteReminders(inLists ids: [String]?) async -> [ReminderData]
    /// Reminders completed on/after `since` — the Needs-rating source (R6.1).
    func completedReminders(since: Date, inLists ids: [String]?) async -> [ReminderData]

    /// Creates or updates a reminder (R4). A blank `id` creates one (in `listId`,
    /// else the default list); returns the saved snapshot with its assigned id.
    @discardableResult func save(_ reminder: ReminderData) -> ReminderData?
    /// Marks a reminder complete/incomplete (R4.3).
    func setCompleted(id: String, _ completed: Bool)
    /// Deletes a reminder (R4.1).
    func delete(id: String)
    /// Creates a new reminder list (R5.2); returns it, or `nil` on failure.
    @discardableResult func createList(named name: String) -> ReminderList?

    /// Emits when reminders change externally (`EKEventStoreChanged`, R1.3).
    var changes: AnyPublisher<Void, Never> { get }
}
