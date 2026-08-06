import XCTest
@testable import Metroneo

/// The read-model join (DESIGN R2/R3/R6): fetch reminders from the fake store,
/// join the sidecar, split out the Needs-rating inbox and the rated population, and
/// reconcile orphaned sidecar rows on refresh.
final class TaskServiceTests: XCTestCase {

    private func makeService(_ store: FakeReminderStore) -> (TaskService, PerformanceSidecarStore) {
        let sidecar = try! PerformanceSidecarStore(inMemory: true)
        // Isolated defaults per test — list scope / window / recurring-due state must
        // not leak across tests via UserDefaults.standard.
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return (TaskService(store: store, sidecar: sidecar, defaults: defaults), sidecar)
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
    func testRefreshReconcilesOrphanSidecar() async { // spec: R3.2 (two-sync grace)
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        // Sidecar carries data for a reminder that no longer exists.
        sidecar.setMetadata(PerformanceMetadata(rating: 55), for: "ghost")
        store.save(ReminderData(title: "Real"))

        await svc.refresh()
        XCTAssertEqual(sidecar.metadata(for: "ghost").rating, 55, "first sync marks pending, doesn't prune")
        await svc.refresh()
        XCTAssertEqual(sidecar.metadata(for: "ghost"), .empty, "second consecutive sync prunes the orphan")
    }

    @MainActor
    func testListScopeDoesNotPruneOutOfScopeSidecar() async { // spec: R3.2 (scope-independent reconcile)
        let work = ReminderList(id: "work", title: "Work", isDefault: true)
        let personal = ReminderList(id: "personal", title: "Personal")
        let store = FakeReminderStore(lists: [work, personal])
        let (svc, sidecar) = makeService(store)
        store.seed(ReminderData(id: "p1", title: "Personal task", isCompleted: true, completionDate: Date(), listId: "personal"))
        sidecar.setMetadata(PerformanceMetadata(rating: 91), for: "p1")

        // Narrow the display scope to Work only, then refresh repeatedly.
        await svc.setListScope(["work"])
        await svc.refresh()
        await svc.refresh()

        XCTAssertEqual(sidecar.metadata(for: "p1").rating, 91,
                       "narrowing scope must not delete out-of-scope performance data")
        XCTAssertFalse(svc.ratedItems.contains { $0.id == "p1" }, "but it's hidden from the scoped view")
    }

    @MainActor
    func testExternalChangeTriggersRefresh() async { // spec: R1.3
        let store = FakeReminderStore()
        let (svc, _) = makeService(store)
        svc.observeExternalChanges()
        await svc.refresh()
        XCTAssertTrue(svc.items.isEmpty)

        // A change originating outside the app (Reminders/Siri) posts on `changes`.
        store.save(ReminderData(title: "Added elsewhere"))
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(svc.items.map(\.title), ["Added elsewhere"], "the store's change signal drives a refresh")
    }

    @MainActor
    func testRecurringInAppCompletionCreatesRatableOccurrence() async { // spec: R3.3/R8.1
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        let due = day("2026-08-01")
        store.seed(ReminderData(id: "rec", title: "Water plants", dueDate: due, priority: .medium, isRecurring: true))

        await svc.refresh(now: due)
        XCTAssertEqual(svc.items.map(\.title), ["Water plants"], "the recurring series is an open item")
        XCTAssertTrue(svc.needsRating.isEmpty)

        await svc.setCompleted(id: "rec", true, now: due)

        // The series advanced (still open) and the completed occurrence needs rating.
        XCTAssertEqual(svc.items.count, 1, "series advanced to the next occurrence, still open")
        XCTAssertTrue(svc.items[0].dueDate! > due, "due date advanced")
        XCTAssertEqual(svc.needsRating.map(\.title), ["Water plants"], "the completed occurrence needs rating")

        // Rate the occurrence via its composite id.
        let occId = PerformanceSidecarStore.occurrenceId(seriesId: "rec", occurrenceDate: due)
        await svc.recordRating(id: occId, rating: 75, notes: nil, actualMinutes: 20)
        XCTAssertTrue(svc.needsRating.isEmpty, "rated occurrence leaves the inbox")
        XCTAssertEqual(svc.ratedItems.first(where: { $0.id == occId })?.rating, 75, "and joins the rated population")
        XCTAssertEqual(sidecar.metadata(for: occId).actualDuration, 20)
    }

    @MainActor
    func testExternalRecurringAdvanceCapturesOccurrence() async { // spec: R3.3 (best-effort external)
        let store = FakeReminderStore()
        let (svc, _) = makeService(store)
        let due = day("2026-08-01")
        store.seed(ReminderData(id: "rec", title: "Standup", dueDate: due, isRecurring: true))
        await svc.refresh(now: due) // records last-seen due

        // Completed in Siri/Reminders → Apple advances the due date (still open).
        store.setCompleted(id: "rec", true)
        await svc.refresh(now: day("2026-08-02"))

        XCTAssertEqual(svc.needsRating.map(\.title), ["Standup"],
                       "an externally-advanced occurrence is captured for rating")
    }

    @MainActor
    func testBrowseCompletedSurfacesOutOfWindowCompletions() async { // spec: R6.5
        let store = FakeReminderStore()
        let (svc, _) = makeService(store)
        svc.needsRatingWindow = 7 * 86_400
        store.seed(ReminderData(id: "recent", title: "Recent", isCompleted: true, completionDate: Date().addingTimeInterval(-2 * 86_400)))
        store.seed(ReminderData(id: "old", title: "Old", isCompleted: true, completionDate: Date().addingTimeInterval(-30 * 86_400)))
        await svc.refresh()

        XCTAssertEqual(svc.needsRating.map(\.title), ["Recent"], "the inbox only shows recent completions")
        let browse = await svc.browseCompleted()
        XCTAssertEqual(browse.map(\.title), ["Recent", "Old"], "Browse Completed surfaces all, newest first")
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
