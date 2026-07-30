import Foundation

/// A scheduled time block (D6.5 · DESIGN.md). Present ⇒ the entry renders as an
/// **event** and occupies its day(s) on the calendar. `allDay` drops the times.
public struct Schedule: Codable, Equatable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var allDay: Bool

    public init(start: Date, end: Date, allDay: Bool = false) {
        self.start = start
        self.end = end
        self.allDay = allDay
    }
}

/// A due-by deadline (D6.5). `hasTime` distinguishes a timed deadline from a
/// date-only "due by end of day" one (mirrors today's `hasDeadlineTime`).
public struct Deadline: Codable, Equatable, Hashable, Sendable {
    public var date: Date
    public var hasTime: Bool

    public init(date: Date, hasTime: Bool = false) {
        self.date = date
        self.hasTime = hasTime
    }
}

/// Completion aspect (D6.2). *Present* ⇒ the entry is **checkable**;
/// `completedAt != nil` ⇒ **completed**. Both states are distinct on purpose.
public struct Completion: Codable, Equatable, Hashable, Sendable {
    public var completedAt: Date?

    public init(completedAt: Date? = nil) {
        self.completedAt = completedAt
    }
}

/// Rating aspect (D6.2). *Present* ⇒ **ratable**; `performanceRating != nil` ⇒
/// **rated** (only rated entries feed analytics — D6.7).
public struct Rating: Codable, Equatable, Hashable, Sendable {
    /// 0–100 once recorded; `nil` while ratable-but-unrated.
    public var performanceRating: Int?
    public var performanceNotes: String?

    public init(performanceRating: Int? = nil, performanceNotes: String? = nil) {
        self.performanceRating = performanceRating
        self.performanceNotes = performanceNotes
    }
}

/// The v2 core unit (D6). A single `Entry` replaces `Task`, `SubTask`, and
/// `Event`: it takes on only the aspects it needs — a time block (`scheduled`),
/// a due date (`deadline`), completion, and/or rating — so one type can be a
/// calendar event, a due-dated task, a checklist step, or a loose reminder.
///
/// Field defaults follow **D6.9** (the `Entry` analog of the old `[DM-03]`):
/// tracking is on by default (both aspects present, inner values nil), so a
/// fresh entry is `isCompletable && isRatable` but neither completed nor rated.
public struct Entry: Codable, Identifiable, Equatable, Hashable, Sendable {
    /// Non-optional UUID, assigned at construction (D2) — no transient-nil window.
    public var id: String
    public var title: String
    public var notes: String?
    /// Required list; **empty means "no tags"** (D4) — never nil.
    public var types: [String]
    /// Plain planning attribute, 0–100 (D6.2).
    public var priorityRating: Int
    public var createDate: Date
    /// Optional planning/display durations in minutes (D14).
    public var estimatedDuration: Int?
    public var actualDuration: Int?

    // Time model — Option A (D6.5): either, both, or neither.
    public var scheduled: Schedule?
    public var deadline: Deadline?

    /// Reminder lead time in **minutes before the time key** (D9). `0` = "at time",
    /// `nil` = no reminder. Only meaningful on a dated entry (D9.1).
    public var reminderLeadMinutes: Int?

    // Tracking aspects (D6.2) — present by default (D6.4), opt out per entry.
    public var completion: Completion?
    public var rating: Rating?

    // Recurrence provenance (D15). `seriesId == nil` ⇒ a one-off entry.
    public var seriesId: String?
    public var occurrenceIndex: Int?

    public init(
        id: String = UUID().uuidString,
        title: String = "",
        notes: String? = nil,
        types: [String] = [],
        priorityRating: Int = 50,
        createDate: Date = Date(),
        estimatedDuration: Int? = nil,
        actualDuration: Int? = nil,
        scheduled: Schedule? = nil,
        deadline: Deadline? = nil,
        reminderLeadMinutes: Int? = nil,
        completion: Completion? = Completion(),
        rating: Rating? = Rating(),
        seriesId: String? = nil,
        occurrenceIndex: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.types = types
        self.priorityRating = priorityRating
        self.createDate = createDate
        self.estimatedDuration = estimatedDuration
        self.actualDuration = actualDuration
        self.scheduled = scheduled
        self.deadline = deadline
        self.reminderLeadMinutes = reminderLeadMinutes
        self.completion = completion
        self.rating = rating
        self.seriesId = seriesId
        self.occurrenceIndex = occurrenceIndex
    }

    // MARK: - Aspect predicates (D6.3)

    public var isCompletable: Bool { completion != nil }
    public var isCompleted: Bool { completion?.completedAt != nil }
    public var isRatable: Bool { rating != nil }
    /// Ratable ≠ rated: a value must actually be recorded (D6.3 / analytics D6.7).
    public var isRated: Bool { rating?.performanceRating != nil }

    // MARK: - Derived time / display

    /// The entry's ordering key (D7.1): `scheduled.start`, else `deadline.date`.
    public var timeKey: Date? { scheduled?.start ?? deadline?.date }

    /// True when the entry has neither a schedule nor a deadline (D7.1).
    public var isUntimed: Bool { timeKey == nil }

    /// A dated entry can carry a reminder (D9.1).
    public var isDated: Bool { scheduled != nil || deadline != nil }

    /// Display rule (D6.6): a scheduled entry shows as an **event**; otherwise a **task**.
    public var isEvent: Bool { scheduled != nil }

    /// Recurrence provenance (D15): part of a generated series.
    public var isSeriesMember: Bool { seriesId != nil }

    /// Estimate-vs-actual delta in minutes when both durations are present (D14.3):
    /// positive = over the estimate, negative = under. `nil` if either is missing.
    /// Display-only — it affects nothing else (D14.4).
    public var durationDeltaMinutes: Int? {
        guard let estimated = estimatedDuration, let actual = actualDuration else { return nil }
        return actual - estimated
    }
}
