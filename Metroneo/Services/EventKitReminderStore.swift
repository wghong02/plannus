import Foundation
import Combine
import EventKit

/// `ReminderStore` backed by EventKit / Apple Reminders (DESIGNV2 R1). Maps
/// `EKReminder` ⇄ ``ReminderData`` so callers stay EventKit-free and testable.
public final class EventKitReminderStore: ReminderStore {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    // MARK: - Access (R1.1)

    public var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    // MARK: - Lists (R5)

    public func lists() -> [ReminderList] {
        let defaultId = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder).map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title, isDefault: $0.calendarIdentifier == defaultId)
        }
    }

    public func defaultListId() -> String? {
        store.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    private func calendars(for ids: [String]?) -> [EKCalendar]? {
        guard let ids else { return nil } // nil ⇒ all
        let byId = Dictionary(store.calendars(for: .reminder).map { ($0.calendarIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byId[$0] }
    }

    // MARK: - Reads (R2/R6)

    public func incompleteReminders(inLists ids: [String]?) async -> [ReminderData] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars(for: ids))
        return await fetch(predicate)
    }

    public func completedReminders(since: Date, inLists ids: [String]?) async -> [ReminderData] {
        let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: nil, calendars: calendars(for: ids))
        return await fetch(predicate)
    }

    private func fetch(_ predicate: NSPredicate) async -> [ReminderData] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.data(from:)))
            }
        }
    }

    // MARK: - Writes (R4)

    @discardableResult
    public func save(_ reminder: ReminderData) -> ReminderData? {
        let ek = existing(reminder.id) ?? EKReminder(eventStore: store)
        if ek.calendar == nil {
            ek.calendar = reminder.listId.isEmpty
                ? store.defaultCalendarForNewReminders()
                : (calendars(for: [reminder.listId])?.first ?? store.defaultCalendarForNewReminders())
        } else if !reminder.listId.isEmpty, ek.calendar.calendarIdentifier != reminder.listId {
            ek.calendar = calendars(for: [reminder.listId])?.first ?? ek.calendar
        }
        apply(reminder, to: ek)
        guard (try? store.save(ek, commit: true)) != nil else { return nil }
        return Self.data(from: ek)
    }

    public func setCompleted(id: String, _ completed: Bool) {
        guard let ek = existing(id) else { return }
        ek.isCompleted = completed // EventKit sets/clears completionDate
        try? store.save(ek, commit: true)
    }

    public func delete(id: String) {
        guard let ek = existing(id) else { return }
        try? store.remove(ek, commit: true)
    }

    @discardableResult
    public func createList(named name: String) -> ReminderList? {
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first { $0.sourceType == .local } ?? store.sources.first
        guard calendar.source != nil, (try? store.saveCalendar(calendar, commit: true)) != nil else { return nil }
        return ReminderList(id: calendar.calendarIdentifier, title: calendar.title)
    }

    // MARK: - Changes (R1.3)

    public var changes: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged).map { _ in () }.eraseToAnyPublisher()
    }

    // MARK: - Mapping

    private func existing(_ externalId: String) -> EKReminder? {
        guard !externalId.isEmpty else { return nil }
        return store.calendarItems(withExternalIdentifier: externalId).compactMap { $0 as? EKReminder }.first
    }

    private func apply(_ data: ReminderData, to ek: EKReminder) {
        ek.title = data.title
        ek.notes = data.notes
        ek.priority = Self.ekPriority(data.priority)
        if let due = data.dueDate {
            let fields: Set<Calendar.Component> = data.hasDueTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            ek.dueDateComponents = Calendar.current.dateComponents(fields, from: due)
        } else {
            ek.dueDateComponents = nil
        }
        (ek.alarms ?? []).forEach { ek.removeAlarm($0) }
        for minutesBefore in data.alarmOffsetMinutes {
            ek.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutesBefore * 60)))
        }
    }

    static func data(from ek: EKReminder) -> ReminderData {
        let due = ek.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let hasTime = ek.dueDateComponents?.hour != nil
        let offsets = (ek.alarms ?? []).map { Int((-$0.relativeOffset) / 60) }
        return ReminderData(
            id: ek.calendarItemExternalIdentifier ?? "",
            title: ek.title ?? "",
            notes: ek.notes,
            dueDate: due,
            hasDueTime: hasTime,
            isCompleted: ek.isCompleted,
            completionDate: ek.completionDate,
            priority: priority(from: ek.priority),
            listId: ek.calendar?.calendarIdentifier ?? "",
            isRecurring: ek.hasRecurrenceRules,
            alarmOffsetMinutes: offsets
        )
    }

    /// EventKit priority (0 none, 1–4 high, 5 medium, 6–9 low) → bucket.
    static func priority(from ek: Int) -> ReminderPriority {
        switch ek {
        case 0: return .none
        case 1...4: return .high
        case 5: return .medium
        default: return .low
        }
    }

    /// Bucket → EventKit priority (none 0, high 1, medium 5, low 9).
    static func ekPriority(_ p: ReminderPriority) -> Int {
        switch p {
        case .none: return 0
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }
}
