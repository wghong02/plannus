import Foundation

/// The local performance metadata Metroneo attaches to a reminder (DESIGNV2 R3) —
/// the only thing that lives in Metroneo's own store; everything else is Apple's.
public struct PerformanceMetadata: Equatable, Sendable {
    public var rating: Int?
    public var performanceNotes: String?
    public var estimatedDuration: Int?
    public var actualDuration: Int?

    public init(rating: Int? = nil, performanceNotes: String? = nil,
                estimatedDuration: Int? = nil, actualDuration: Int? = nil) {
        self.rating = rating
        self.performanceNotes = performanceNotes
        self.estimatedDuration = estimatedDuration
        self.actualDuration = actualDuration
    }

    public static let empty = PerformanceMetadata()
    /// No performance data ⇒ the sidecar drops the row (R3.1).
    public var isEmpty: Bool {
        rating == nil && performanceNotes == nil && estimatedDuration == nil && actualDuration == nil
    }
}

/// The companion's read model (DESIGNV2 R2): a reminder (`ReminderData`, from
/// EventKit) joined with its local `PerformanceMetadata`. The UI and analytics
/// consume `TaskItem`s; the join is keyed by the reminder's external id.
public struct TaskItem: Identifiable, Equatable, Sendable {
    // From the reminder (Apple Reminders):
    public let id: String
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var isCompleted: Bool
    public var completionDate: Date?
    public var priority: ReminderPriority
    public var listId: String
    public var isRecurring: Bool
    /// Early-reminder alarms as minutes-before (R4.2) — carried so the editor can
    /// round-trip them; not used by analytics.
    public var alarmOffsetMinutes: [Int]
    // From the sidecar (Metroneo):
    public var rating: Int?
    public var performanceNotes: String?
    public var estimatedDuration: Int?
    public var actualDuration: Int?

    /// A recorded rating (R2.3) — the analytics population.
    public var isRated: Bool { rating != nil }
    /// Where the item sits on the analytics timeline: completion, else due (D6.7).
    public var placementDate: Date? { completionDate ?? dueDate }

    public init(reminder r: ReminderData, metadata m: PerformanceMetadata) {
        id = r.id
        title = r.title
        notes = r.notes
        dueDate = r.dueDate
        hasDueTime = r.hasDueTime
        isCompleted = r.isCompleted
        completionDate = r.completionDate
        priority = r.priority
        listId = r.listId
        isRecurring = r.isRecurring
        alarmOffsetMinutes = r.alarmOffsetMinutes
        rating = m.rating
        performanceNotes = m.performanceNotes
        estimatedDuration = m.estimatedDuration
        actualDuration = m.actualDuration
    }

    /// The reminder half of the join, for write-back through the store (R4).
    public var reminderData: ReminderData {
        ReminderData(
            id: id, title: title, notes: notes, dueDate: dueDate, hasDueTime: hasDueTime,
            isCompleted: isCompleted, completionDate: completionDate, priority: priority,
            listId: listId, isRecurring: isRecurring, alarmOffsetMinutes: alarmOffsetMinutes
        )
    }
}
