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
        svc.setListScope(["work"])
        await svc.refresh()
        await svc.refresh()

        XCTAssertEqual(sidecar.metadata(for: "p1").rating, 91,
                       "narrowing scope must not delete out-of-scope performance data")
        XCTAssertFalse(svc.ratedItems.contains { $0.id == "p1" }, "but it's hidden from the scoped view")
    }

    @MainActor
    func testSyncStatusReflectsStoreBacking() async { // spec: Sync (iCloud on/off hint)
        let store = FakeReminderStore()
        // In-memory sidecar is never cloud-backed → the hint reflects "sync off".
        let sidecar = try! PerformanceSidecarStore(inMemory: true)
        let configured = TaskService(store: store, sidecar: sidecar,
                                     defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
                                     syncConfigured: true)
        await configured.syncNow()
        XCTAssertTrue(configured.syncConfigured, "hint is wired up in the real app")
        XCTAssertFalse(configured.iCloudSyncing, "local store ⇒ not syncing")

        let notConfigured = TaskService(store: store, sidecar: sidecar,
                                        defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        XCTAssertFalse(notConfigured.syncConfigured, "tests/fakes ⇒ no hint")
    }

    @MainActor
    func testClearPerformanceByDate() async { // spec: Sync / Settings (clear by age)
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        let now = day("2026-08-06")
        store.seed(ReminderData(id: "recent", title: "Recent", isCompleted: true, completionDate: day("2026-08-01")))
        store.seed(ReminderData(id: "old", title: "Old", isCompleted: true, completionDate: day("2026-01-01")))
        sidecar.setMetadata(PerformanceMetadata(rating: 80), for: "recent")
        sidecar.setMetadata(PerformanceMetadata(rating: 40), for: "old")
        await svc.refresh()
        XCTAssertEqual(Set(svc.ratedItems.map(\.title)), ["Recent", "Old"])

        await svc.clearPerformance(olderThanDays: 30, now: now)
        XCTAssertEqual(sidecar.metadata(for: "old"), .empty, "ratings older than the cutoff are cleared")
        XCTAssertEqual(sidecar.metadata(for: "recent").rating, 80, "recent ratings are kept")

        await svc.clearPerformance(olderThanDays: nil, now: now)
        XCTAssertEqual(sidecar.metadata(for: "recent"), .empty, "clear-all removes the rest")
    }

    private final class SpyWidgetPublisher: WidgetSnapshotPublishing {
        var last: WidgetSnapshot?
        func publish(_ snapshot: WidgetSnapshot) { last = snapshot }
    }

    @MainActor
    func testRefreshPublishesWidgetSnapshot() async { // spec: Widgets
        let store = FakeReminderStore()
        let spy = SpyWidgetPublisher()
        let sidecar = try! PerformanceSidecarStore(inMemory: true)
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let svc = TaskService(store: store, sidecar: sidecar, defaults: defaults, widgetPublisher: spy)
        store.save(ReminderData(title: "Open"))
        store.seed(ReminderData(id: "d1", title: "DoneUnrated", isCompleted: true, completionDate: Date()))
        store.seed(ReminderData(id: "d2", title: "DoneRated", isCompleted: true, completionDate: Date()))
        sidecar.setMetadata(PerformanceMetadata(rating: 88), for: "d2")

        await svc.refresh()

        XCTAssertEqual(spy.last?.tasks.map(\.title), ["Open"], "incomplete → widget tasks")
        XCTAssertEqual(spy.last?.needsRating.map(\.title), ["DoneUnrated"], "unrated completed → needs-rating widget")
        XCTAssertEqual(spy.last?.recentRated.map(\.title), ["DoneRated"], "rated → performance widget population")
    }

    @MainActor
    func testSetListScopeUpdatesStateSynchronously() { // spec: R5.3 (toggle must not revert)
        let store = FakeReminderStore(lists: [ReminderList(id: "work", title: "Work", isDefault: true),
                                              ReminderList(id: "personal", title: "Personal")])
        let (svc, _) = makeService(store)

        // A bound Toggle re-reads its value right after `set`; the scope change must
        // land synchronously or the switch rubber-bands back on ("can't toggle off").
        svc.setListScope(["work"])
        XCTAssertEqual(svc.listScope, ["work"], "scope narrows synchronously")
        svc.setListScope(nil)
        XCTAssertNil(svc.listScope, "clearing to all lists is synchronous too")
    }

    @MainActor
    func testEmptyListScopeIsNoneNotAll() async { // spec: R5.3 (turning off the last list sticks)
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = FakeReminderStore(lists: [ReminderList(id: "only", title: "Only", isDefault: true)])
        let sidecar = try! PerformanceSidecarStore(inMemory: true)
        let svc = TaskService(store: store, sidecar: sidecar, defaults: defaults)
        store.save(ReminderData(title: "A task", listId: "only"))
        await svc.refresh()
        XCTAssertEqual(svc.items.map(\.title), ["A task"], "the sole list's task shows by default")

        // Turning off the only (last) list is an explicit empty scope — NOT "all".
        svc.setListScope([])
        await svc.refresh()
        XCTAssertEqual(svc.listScope, [], "empty scope is preserved, not coerced to nil/all")
        XCTAssertTrue(svc.items.isEmpty, "no lists in scope ⇒ nothing shown")

        // And it survives a reload (a fresh service reading the same defaults).
        let reloaded = TaskService(store: store, sidecar: sidecar, defaults: defaults)
        XCTAssertEqual(reloaded.listScope, [], "empty scope persists across launches")
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
        await svc.recordRating(id: occId, rating: 75, notes: nil, estimatedMinutes: nil, actualMinutes: 20)
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
    func testRecordRatingCapturesBothDurationsForBars() async { // spec: R6.2/D14/D17
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        store.seed(ReminderData(id: "d", title: "Task", isCompleted: true, completionDate: Date()))
        await svc.refresh()

        // A completed reminder is only reachable via the rating sheet; capturing the
        // estimate there means the estimated-vs-actual bars (D17) get data.
        await svc.recordRating(id: "d", rating: 80, notes: nil, estimatedMinutes: 30, actualMinutes: 45)
        XCTAssertEqual(sidecar.metadata(for: "d").estimatedDuration, 30)
        XCTAssertEqual(sidecar.metadata(for: "d").actualDuration, 45)

        let totals = PerformanceAnalytics.durationTotals(svc.ratedItems, period: .allTime)
        XCTAssertEqual(totals, DurationTotals(estimated: 30, actual: 45, count: 1),
                       "rating with both durations populates the estimated-vs-actual bars")
    }

    @MainActor
    func testCompletedReminderFieldsAreEditable() async { // spec: R6.5 / R4 (edit all fields)
        let store = FakeReminderStore()
        let (svc, _) = makeService(store)
        store.seed(ReminderData(id: "c", title: "Old", isCompleted: true,
                                completionDate: Date(), priority: .none))
        await svc.refresh()

        // Edit all reminder fields of a completed reminder (as Browse Completed does).
        var edited = (await svc.browseCompleted()).first { $0.id == "c" }!.reminderData
        edited.title = "New"
        edited.priority = .high
        edited.notes = "follow up"
        await svc.save(edited)

        let item = (await svc.browseCompleted()).first { $0.id == "c" }!
        XCTAssertEqual(item.title, "New", "a completed reminder's fields are editable")
        XCTAssertEqual(item.priority, .high)
        XCTAssertEqual(item.notes, "follow up")
        XCTAssertTrue(item.isCompleted, "editing fields leaves it completed")
    }

    @MainActor
    func testDeleteCompletedRemovesReminderAndSidecar() async { // spec: R6.5 / R4.1 / R3.2
        let store = FakeReminderStore()
        let (svc, sidecar) = makeService(store)
        store.seed(ReminderData(id: "c", title: "Done", isCompleted: true, completionDate: Date()))
        sidecar.setMetadata(PerformanceMetadata(rating: 70), for: "c")
        await svc.refresh()
        let before = await svc.browseCompleted()
        XCTAssertEqual(before.map(\.title), ["Done"])

        // The Browse Completed swipe-left → Delete path.
        await svc.delete(id: "c")
        let after = await svc.browseCompleted()
        XCTAssertTrue(after.isEmpty, "deleting removes it from Browse Completed")
        XCTAssertEqual(sidecar.metadata(for: "c"), .empty, "and drops its sidecar data")
    }

    @MainActor
    func testRatedPopulationFiltersByListForPerformance() async { // spec: D16 (performance list filter)
        let work = ReminderList(id: "work", title: "Work", isDefault: true)
        let home = ReminderList(id: "home", title: "Home")
        let store = FakeReminderStore(lists: [work, home])
        let (svc, sidecar) = makeService(store)
        store.seed(ReminderData(id: "w", title: "W", isCompleted: true, completionDate: Date(), listId: "work"))
        store.seed(ReminderData(id: "h", title: "H", isCompleted: true, completionDate: Date(), listId: "home"))
        sidecar.setMetadata(PerformanceMetadata(rating: 80), for: "w")
        sidecar.setMetadata(PerformanceMetadata(rating: 20), for: "h")
        await svc.refresh()

        XCTAssertEqual(svc.ratedItems.count, 2, "unfiltered rated population keeps both lists")
        let workRated = PerformanceAnalytics.inList(svc.ratedItems, "work")
        XCTAssertEqual(workRated.map(\.title), ["W"], "the Performance list filter narrows to one list")
        XCTAssertEqual(PerformanceAnalytics.average(PerformanceAnalytics.samples(from: workRated)), 80,
                       "and the average reflects only that list")
    }

    @MainActor
    func testCompletedFiltersByList() async { // spec: R6.5 (pick by list)
        let work = ReminderList(id: "work", title: "Work", isDefault: true)
        let personal = ReminderList(id: "personal", title: "Personal")
        let store = FakeReminderStore(lists: [work, personal])
        let (svc, _) = makeService(store)
        store.seed(ReminderData(id: "w", title: "WorkDone", isCompleted: true, completionDate: Date(), listId: "work"))
        store.seed(ReminderData(id: "p", title: "PersonalDone", isCompleted: true, completionDate: Date(), listId: "personal"))
        await svc.refresh()

        let all = await svc.browseCompleted()
        XCTAssertEqual(Set(all.map(\.title)), ["WorkDone", "PersonalDone"], "default (nil) shows all lists")

        let workOnly = await svc.browseCompleted(inList: "work")
        XCTAssertEqual(workOnly.map(\.title), ["WorkDone"], "filtering shows only the picked list")
        let personalOnly = await svc.browseCompleted(inList: "personal")
        XCTAssertEqual(personalOnly.map(\.title), ["PersonalDone"])
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
