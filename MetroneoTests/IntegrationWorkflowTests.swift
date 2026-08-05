import XCTest
@testable import Metroneo

/// Cross-service workflow integration — the seams that unit tests exercise in
/// isolation but a real flow chains together: reminder side-effects (D9/D15.7),
/// the complete+rate → analytics pipeline (D6.7 → D16), series-scope deletes vs
/// the collection cache (D1.6/D5.6), and filter ∘ calendar grouping (D7/D6.5).
final class IntegrationWorkflowTests: XCTestCase {
    private func makeDB() -> EntryDatabase { try! EntryDatabase(inMemory: true) }

    /// Records the reminder side-effects `EntryService` drives (D9) without the
    /// real notification system.
    private final class ReminderSchedulingSpy: ReminderScheduling {
        private(set) var rescheduled: [String] = []
        private(set) var cancelled: [String] = []
        private(set) var lastBadge: Int?
        func reschedule(for entry: Entry, allEntries: [Entry]) { rescheduled.append(entry.id) }
        func cancel(entryId: String) { cancelled.append(entryId) }
        func setBadgeCount(_ count: Int) { lastBadge = count }
        func reset() { rescheduled = []; cancelled = [] }
    }

    // MARK: - 1. Reminder side-effects across an entry's lifecycle

    func testReminderSideEffectsAcrossLifecycle() { // spec: D9.5 (scheduler wiring)
        let spy = ReminderSchedulingSpy()
        let entries = EntryService(db: makeDB(), scheduler: spy)

        let e = Entry(title: "Standup", deadline: Deadline(date: day("2027-01-01")), reminderLeadMinutes: 15)
        entries.upsertEntry(e)
        XCTAssertEqual(spy.rescheduled, [e.id], "upsert (re)schedules the entry")

        spy.reset()
        entries.completeEntry(id: e.id)
        XCTAssertEqual(spy.rescheduled, [e.id], "completing reschedules (cancels a completed reminder, D9.5)")

        spy.reset()
        entries.uncompleteEntry(id: e.id)
        XCTAssertEqual(spy.rescheduled, [e.id], "uncompleting re-arms")

        spy.reset()
        entries.deleteEntry(id: e.id)
        XCTAssertEqual(spy.cancelled, [e.id], "deleting cancels the reminder")
        XCTAssertTrue(spy.rescheduled.isEmpty, "delete doesn't reschedule")
    }

    func testAppBadgeReflectsDueReminders() { // spec: REM-10
        let spy = ReminderSchedulingSpy()
        let entries = EntryService(db: makeDB(), scheduler: spy)

        // An entry whose reminder fire time is already in the past (overdue), not done.
        let overdue = Entry(title: "Overdue",
                            deadline: Deadline(date: Date().addingTimeInterval(-3600)),
                            reminderLeadMinutes: 0)
        entries.upsertEntry(overdue)
        XCTAssertEqual(spy.lastBadge, 1, "an overdue, incomplete reminder bumps the badge")

        entries.completeEntry(id: overdue.id)
        XCTAssertEqual(spy.lastBadge, 0, "completing it clears it from the due count")
    }

    func testSeriesThisAndFutureReArmsRegeneratedOccurrences() { // spec: D15.7
        let db = makeDB()
        let spy = ReminderSchedulingSpy()
        let entries = EntryService(db: db, scheduler: spy)
        let series = SeriesService(db: db, entries: entries)
        let template = Entry(title: "Standup", deadline: Deadline(date: day("2026-07-20")), reminderLeadMinutes: 15)
        let s = series.createSeries(template: template, rule: RecurrenceRule(frequency: .daily, interval: 1, end: .afterCount(3)))
        XCTAssertEqual(spy.rescheduled.count, 3, "each generated occurrence schedules its own reminder")

        let occ1 = entries.entries.first { $0.seriesId == s.id && $0.occurrenceIndex == 1 }!
        let occ2 = entries.entries.first { $0.seriesId == s.id && $0.occurrenceIndex == 2 }!
        spy.reset()

        var edited = occ1
        edited.title = "Changed"
        series.edit(edited, scope: .thisAndFuture)

        XCTAssertTrue(spy.cancelled.contains(occ1.id) && spy.cancelled.contains(occ2.id),
                      "future occurrences are cancelled on regenerate (D15.7)")
        XCTAssertEqual(spy.rescheduled.count, 2, "the two regenerated occurrences are re-armed")
    }

    // MARK: - 2. Complete + rate → analytics population

    func testCompleteAndRateFlowsIntoAnalytics() { // spec: D6.7 → D16
        let entries = EntryService(db: makeDB())
        let e = Entry(title: "Session")
        entries.upsertEntry(e)
        entries.rateEntry(id: e.id, performance: 82)
        entries.completeEntry(id: e.id, at: Date())

        let samples = PerformanceAnalytics.samples(from: entries.entries)
        XCTAssertEqual(samples.count, 1, "a completed+rated entry becomes one analytics sample")
        XCTAssertEqual(samples.first?.performanceRating, 82)

        XCTAssertEqual(PerformanceAnalytics.windowedRated(entries.entries, period: .month).map(\.title),
                       ["Session"], "it appears in the current period's Recent list")
        let bucketTotal = PerformanceAnalytics.trendSeries(samples, period: .month).reduce(0) { $0 + $1.taskCount }
        XCTAssertEqual(bucketTotal, 1, "and in exactly one trend bucket")
    }

    func testEstimatedAndActualFlowIntoDurationTotals() { // spec: D17
        let entries = EntryService(db: makeDB())
        // An entry with an estimate; complete it and record a differing actual.
        let e = Entry(title: "Deep work", estimatedDuration: 60)
        entries.upsertEntry(e)
        entries.setActualDuration(id: e.id, minutes: 75)
        entries.completeEntry(id: e.id, at: Date())

        let totals = PerformanceAnalytics.durationTotals(entries.entries, period: .month)
        XCTAssertEqual(totals.count, 1, "the time-tracked entry is counted")
        XCTAssertEqual(totals.estimated, 60)
        XCTAssertEqual(totals.actual, 75)
    }

    // MARK: - 3. Series-scope delete keeps the collection cache coherent (D1.6)

    func testSeriesScopeDeletePrunesCollectionCache() { // spec: D1.6 / D5.6
        let db = makeDB()
        let entries = EntryService(db: db)
        let series = SeriesService(db: db, entries: entries)
        let cols = CollectionService(db: db)
        entries.deletionObserver = cols // wired at bootstrap in MetroneoApp

        let template = Entry(title: "Standup", deadline: Deadline(date: day("2026-07-20")))
        let s = series.createSeries(template: template, rule: RecurrenceRule(frequency: .daily, interval: 1, end: .afterCount(3)))
        let coll = cols.createCollection(name: "Focus", ordering: .ordered)
        for occ in entries.entries where occ.seriesId == s.id { cols.addMember(collectionId: coll.id, entryId: occ.id) }
        XCTAssertEqual(cols.collections.first { $0.id == coll.id }?.memberIds.count, 3)

        series.delete(entries.entries.first { $0.seriesId == s.id }!, scope: .all)

        XCTAssertEqual(cols.collections.first { $0.id == coll.id }?.memberIds, [],
                       "a series-scope delete prunes every occurrence from the collection cache")
        XCTAssertTrue(entries.entries.isEmpty, "all occurrences are gone")
    }

    // MARK: - 4. Membership reattaches through a This-and-future split

    func testMembershipReAttachesToLiveOccurrenceAfterEditThisAndFuture() { // spec: SER-11 / D15.6
        let db = makeDB()
        let entries = EntryService(db: db)
        let series = SeriesService(db: db, entries: entries)
        let cols = CollectionService(db: db)
        entries.deletionObserver = cols

        let template = Entry(title: "Standup", deadline: Deadline(date: day("2026-07-20")))
        let s = series.createSeries(template: template, rule: RecurrenceRule(frequency: .daily, interval: 1, end: .afterCount(3)))
        let occ1 = entries.entries.first { $0.seriesId == s.id && $0.occurrenceIndex == 1 }!
        let coll = cols.createCollection(name: "Focus", ordering: .ordered)
        cols.addMember(collectionId: coll.id, entryId: occ1.id)

        var edited = occ1
        edited.title = "Changed"
        let survivorId = series.edit(edited, scope: .thisAndFuture)!
        cols.addMember(collectionId: coll.id, entryId: survivorId) // mirrors the editor's sync

        let members = cols.collections.first { $0.id == coll.id }!.memberIds
        XCTAssertEqual(members, [survivorId], "membership follows the occurrence across a this-and-future split")
        XCTAssertTrue(members.allSatisfy { id in entries.entries.contains { $0.id == id } }, "no dangling ids")
        XCTAssertEqual(entries.entries.first { $0.id == survivorId }?.title, "Changed")
    }

    // MARK: - 5. Filter ∘ calendar grouping composition

    func testFilterThenCalendarGroupingComposition() { // spec: D7.4 / D6.5
        let d = day("2026-07-21")
        let completed = Entry(title: "Done",
                              scheduled: Schedule(start: d.addingTimeInterval(9 * 3600), end: d.addingTimeInterval(10 * 3600)),
                              completion: Completion(completedAt: d))
        let upcoming = Entry(title: "Todo", deadline: Deadline(date: d))
        let all = [completed, upcoming]

        let upcomingOnly = EntryQuery.filter(all, with: EntryFilter(completion: .upcoming))
        XCTAssertEqual(CalendarGrouping.entries(upcomingOnly, on: d).map(\.title), ["Todo"],
                       "the completion filter composes with calendar placement")

        XCTAssertEqual(CalendarGrouping.entries(all, on: d).map(\.title), ["Todo", "Done"],
                       "within a day, incomplete sorts above completed")
    }
}
