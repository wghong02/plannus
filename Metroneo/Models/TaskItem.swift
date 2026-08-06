import Foundation

/// The local performance metadata Metroneo attaches to a reminder (DESIGN R3) —
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

/// The companion's read model (DESIGN R2): a reminder (`ReminderData`, from
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
    /// True for a recurring **occurrence snapshot** (R3.3): a historical, sidecar-only
    /// record with no live reminder behind it, so its reminder fields can't be edited.
    public var isOccurrence: Bool
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
    /// Where the item sits on the analytics timeline: completion, else due (R2.3).
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
        isOccurrence = false
        alarmOffsetMinutes = r.alarmOffsetMinutes
        rating = m.rating
        performanceNotes = m.performanceNotes
        estimatedDuration = m.estimatedDuration
        actualDuration = m.actualDuration
    }

    /// Projects a recurring **occurrence snapshot** (DESIGN R3.3) as a `TaskItem`:
    /// its composite id, the series' snapshotted title/list/priority, the
    /// occurrence's due + completion dates, and the joined performance fields. It's
    /// always a completed, recurring item placed on the timeline by its completion.
    public init(occurrence o: OccurrenceRecord) {
        id = o.id
        title = o.title
        notes = nil
        dueDate = o.occurrenceDate
        hasDueTime = false
        isCompleted = true
        completionDate = o.completionDate
        priority = o.priority
        listId = o.listId
        isRecurring = true
        isOccurrence = true
        alarmOffsetMinutes = []
        rating = o.metadata.rating
        performanceNotes = o.metadata.performanceNotes
        estimatedDuration = o.metadata.estimatedDuration
        actualDuration = o.metadata.actualDuration
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
