import Foundation
import Combine
@testable import Metroneo

/// In-memory ``ReminderStore`` for tests (DESIGNV2 R1.2) — no EventKit, no system
/// prompt. The join / sidecar / analytics layers are tested against this. *(When
/// the companion UI lands, a DEBUG copy in the app target will back UI-test
/// injection via a launch arg; for now it lives with the unit tests.)*
final class FakeReminderStore: ReminderStore {
    private var reminders: [String: ReminderData] = [:]
    private var reminderLists: [ReminderList]
    private let defaultList: String
    private let subject = PassthroughSubject<Void, Never>()

    var isAuthorized = true

    init(lists: [ReminderList] = [ReminderList(id: "default", title: "Reminders", isDefault: true)]) {
        self.reminderLists = lists
        self.defaultList = lists.first(where: \.isDefault)?.id ?? lists.first?.id ?? "default"
    }

    func requestAccess() async -> Bool { isAuthorized }
    func lists() -> [ReminderList] { reminderLists }
    func defaultListId() -> String? { defaultList }

    func incompleteReminders(inLists ids: [String]?) async -> [ReminderData] {
        sorted(reminders.values.filter { !$0.isCompleted && listMatch($0, ids) })
    }

    func completedReminders(since: Date, inLists ids: [String]?) async -> [ReminderData] {
        sorted(reminders.values.filter {
            $0.isCompleted && ($0.completionDate.map { $0 >= since } ?? false) && listMatch($0, ids)
        })
    }

    @discardableResult
    func save(_ reminder: ReminderData) -> ReminderData? {
        var r = reminder
        if r.id.isEmpty { r.id = UUID().uuidString }
        if r.listId.isEmpty { r.listId = defaultList }
        reminders[r.id] = r
        subject.send()
        return r
    }

    func setCompleted(id: String, _ completed: Bool) {
        guard var r = reminders[id] else { return }
        r.isCompleted = completed
        r.completionDate = completed ? Date() : nil
        reminders[id] = r
        subject.send()
    }

    func delete(id: String) {
        reminders[id] = nil
        subject.send()
    }

    @discardableResult
    func createList(named name: String) -> ReminderList? {
        let list = ReminderList(id: UUID().uuidString, title: name)
        reminderLists.append(list)
        return list
    }

    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    // MARK: - Test seeding

    /// Inserts a reminder as-is (e.g. a completed one with an explicit date).
    func seed(_ data: ReminderData) {
        var d = data
        if d.id.isEmpty { d.id = UUID().uuidString }
        reminders[d.id] = d
    }

    private func listMatch(_ r: ReminderData, _ ids: [String]?) -> Bool {
        guard let ids else { return true }
        return ids.contains(r.listId)
    }

    private func sorted(_ items: [ReminderData]) -> [ReminderData] {
        items.sorted { $0.title < $1.title }
    }
}
