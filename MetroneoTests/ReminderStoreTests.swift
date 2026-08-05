import XCTest
@testable import Metroneo

/// Contract of the ``ReminderStore`` abstraction (DESIGNV2 R1/R4/R5), exercised
/// against the in-memory ``FakeReminderStore`` — the double the join/sidecar/
/// analytics layers build on. Also covers the `EKReminder` priority mapping used
/// by the real store.
final class ReminderStoreTests: XCTestCase {

    func testSaveAssignsIdAndDefaultsList() async { // spec: R4.1/R5.3
        let store = FakeReminderStore()
        let saved = store.save(ReminderData(title: "Buy milk"))
        XCTAssertNotNil(saved)
        XCTAssertFalse(saved!.id.isEmpty, "save assigns a stable id")
        XCTAssertEqual(saved!.listId, store.defaultListId(), "a blank list saves into the default list")

        let incomplete = await store.incompleteReminders(inLists: nil)
        XCTAssertEqual(incomplete.map(\.title), ["Buy milk"])
    }

    func testCompleteMovesBetweenIncompleteAndCompleted() async { // spec: R4.3
        let store = FakeReminderStore()
        let r = store.save(ReminderData(title: "Gym"))!
        store.setCompleted(id: r.id, true)

        let inc = await store.incompleteReminders(inLists: nil)
        XCTAssertTrue(inc.isEmpty, "completed reminder leaves the incomplete set")
        let done = await store.completedReminders(since: .distantPast, inLists: nil)
        XCTAssertEqual(done.map(\.title), ["Gym"])
    }

    func testCompletedRespectsSinceWindow() async { // spec: R6.1
        let store = FakeReminderStore()
        store.seed(ReminderData(id: "a", title: "Old", isCompleted: true, completionDate: Date().addingTimeInterval(-3 * 86400)))
        store.seed(ReminderData(id: "b", title: "Recent", isCompleted: true, completionDate: Date().addingTimeInterval(-3600)))

        let within = await store.completedReminders(since: Date().addingTimeInterval(-86400), inLists: nil)
        XCTAssertEqual(within.map(\.title), ["Recent"], "only completions inside the look-back window")
    }

    func testDeleteRemoves() async { // spec: R4.1
        let store = FakeReminderStore()
        let r = store.save(ReminderData(title: "Temp"))!
        store.delete(id: r.id)
        let inc = await store.incompleteReminders(inLists: nil)
        XCTAssertTrue(inc.isEmpty)
    }

    func testListFilteringAndCreate() async { // spec: R5.1/R5.2
        let store = FakeReminderStore()
        let work = store.createList(named: "Work")!
        store.save(ReminderData(title: "Report", listId: work.id))
        store.save(ReminderData(title: "Personal")) // → default list

        let workOnly = await store.incompleteReminders(inLists: [work.id])
        XCTAssertEqual(workOnly.map(\.title), ["Report"], "list filter scopes to that list")
        XCTAssertTrue(store.lists().contains { $0.title == "Work" }, "the new list is listed")
    }

    func testEventKitPriorityRoundTrip() { // spec: R7.1
        for bucket in ReminderPriority.allCases {
            let ek = EventKitReminderStore.ekPriority(bucket)
            XCTAssertEqual(EventKitReminderStore.priority(from: ek), bucket, "\(bucket) round-trips through EK priority")
        }
        // EventKit's numeric ranges map onto the four buckets.
        XCTAssertEqual(EventKitReminderStore.priority(from: 0), .none)
        XCTAssertEqual(EventKitReminderStore.priority(from: 3), .high)   // 1–4 → high
        XCTAssertEqual(EventKitReminderStore.priority(from: 5), .medium)
        XCTAssertEqual(EventKitReminderStore.priority(from: 8), .low)    // 6–9 → low
    }
}
