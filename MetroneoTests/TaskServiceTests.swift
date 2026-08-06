import XCTest
@testable import Metroneo

/// The read-model join (DESIGNV2 R2/R3/R6): fetch reminders from the fake store,
/// join the sidecar, split out the Needs-rating inbox and the rated population, and
/// reconcile orphaned sidecar rows on refresh.
final class TaskServiceTests: XCTestCase {

    private func makeService(_ store: FakeReminderStore) -> (TaskService, PerformanceSidecarStore) {
        let sidecar = try! PerformanceSidecarStore(inMemory: true)
        return (TaskService(store: store, sidecar: sidecar), sidecar)
    }

    @MainActor
    func testRefreshSplitsItemsNeedsRatingAndRated() async { // spec: R2/R6.1
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        store.save(ReminderData(title: "Open"))
        store.seed(ReminderData(id: "d1", title: "DoneUnrated", isCompleted: true, completionDate: Date()))
        store.seed(ReminderData(id: "d2", title: "DoneRated", isCompleted: true, completionDate: Date()))
        sidecar.setMetadata(PerformanceMetadata(rating: 90), for: "d2")

        await svc.refresh()

        XCTAssertEqual(svc.items.map(\.title), ["Open"], "incomplete → items")
        XCTAssertEqual(svc.needsRating.map(\.title), ["DoneUnrated"], "completed + unrated → needs rating")
        XCTAssertEqual(svc.ratedItems.map(\.title), ["DoneRated"], "rated → analytics population")
        XCTAssertEqual(svc.ratedItems.first?.rating, 90, "the sidecar rating is joined in")
    }

    @MainActor
    func testRatingLeavesTheInboxAndJoinsRated() async { // spec: R6.2
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        store.seed(ReminderData(id: "d", title: "Task", isCompleted: true, completionDate: Date()))

        await svc.refresh()
        XCTAssertEqual(svc.needsRating.map(\.title), ["Task"])

        await svc.rate(id: "d", rating: 70)
        XCTAssertTrue(svc.needsRating.isEmpty, "a rated item leaves the Needs-rating inbox")
        XCTAssertEqual(svc.ratedItems.map(\.title), ["Task"])
        XCTAssertEqual(sidecar.metadata(for: "d").rating, 70)
    }

    @MainActor
    func testCreateEditCompleteRateDelete() async { // spec: R4
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)

        // Create.
        let saved = await svc.save(ReminderData(title: "Draft"))
        let id = saved!.id
        XCTAssertEqual(svc.items.map(\.title), ["Draft"], "a created reminder shows in items")

        // Edit (title + priority).
        await svc.save(ReminderData(id: id, title: "Final", priority: .high))
        XCTAssertEqual(svc.items.first?.title, "Final")
        XCTAssertEqual(svc.items.first?.priority, .high)

        // Complete → leaves items, enters the inbox.
        await svc.setCompleted(id: id, true)
        XCTAssertTrue(svc.items.isEmpty)
        XCTAssertEqual(svc.needsRating.map(\.title), ["Final"])

        // Rate → leaves the inbox, joins the rated population.
        await svc.rate(id: id, rating: 80)
        XCTAssertTrue(svc.needsRating.isEmpty)
        XCTAssertEqual(svc.ratedItems.first?.rating, 80)

        // Delete → gone, and its sidecar data is dropped.
        await svc.delete(id: id)
        XCTAssertTrue(svc.ratedItems.isEmpty)
        XCTAssertEqual(sidecar.metadata(for: id), .empty)
    }

    @MainActor
    func testNeedsRatingWindowExcludesOldCompletions() async { // spec: R6.1a
        let store = FakeReminderStore()
        let (svc, _) = makeService(store)
        svc.needsRatingWindow = 7 * 86_400 // 7 days
        store.seed(ReminderData(id: "recent", title: "Recent", isCompleted: true, completionDate: Date().addingTimeInterval(-2 * 86_400)))
        store.seed(ReminderData(id: "old", title: "Old", isCompleted: true, completionDate: Date().addingTimeInterval(-30 * 86_400)))

        await svc.refresh()
        XCTAssertEqual(svc.needsRating.map(\.title), ["Recent"], "only completions inside the window need rating")
    }

    @MainActor
    func testRefreshReconcilesOrphanSidecar() async { // spec: R3.2
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        // Sidecar carries data for a reminder that no longer exists.
        sidecar.setMetadata(PerformanceMetadata(rating: 55), for: "ghost")
        store.save(ReminderData(title: "Real"))

        await svc.refresh()
        XCTAssertEqual(sidecar.metadata(for: "ghost"), .empty, "refresh prunes the orphaned sidecar row")
    }

    @MainActor
    func testOldRatedCompletionSurvivesReconcile() async { // spec: R3.2 (window vs. delete)
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        svc.needsRatingWindow = 7 * 86_400
        // Completed long ago but still exists in Reminders, and it's rated.
        store.seed(ReminderData(id: "old", title: "OldRated", isCompleted: true, completionDate: Date().addingTimeInterval(-100 * 86_400)))
        sidecar.setMetadata(PerformanceMetadata(rating: 88), for: "old")

        await svc.refresh()
        XCTAssertEqual(sidecar.metadata(for: "old").rating, 88, "an old-but-alive reminder keeps its sidecar")
        XCTAssertEqual(svc.ratedItems.map(\.title), ["OldRated"], "and stays in the rated population")
        XCTAssertTrue(svc.needsRating.isEmpty, "but not in the inbox (outside the window / already rated)")
    }
}
