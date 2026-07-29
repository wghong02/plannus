import XCTest
@testable import Metroneo

/// Storage + service integration (DESIGN.md test plan: EDB-*, ENT-TTL-01,
/// ENT-TYP-01, ESVC-*, COL-08/09/10, SER-06/10).
final class EntryStoreTests: XCTestCase {
    private func makeDB() -> EntryDatabase { try! EntryDatabase(inMemory: true) }

    // MARK: - EntryDatabase

    func testUpsertInsertsAndUpdatesOneEntity() { // spec: EDB-01, EDB-02
        let db = makeDB()
        let a = Entry(title: "A"), b = Entry(title: "B")
        try! db.upsertEntry(a); try! db.upsertEntry(b)
        XCTAssertEqual(Set(try! db.loadEntries().map(\.title)), ["A", "B"])

        var a2 = a; a2.title = "A2"
        try! db.upsertEntry(a2)
        let titles = try! db.loadEntries().map(\.title)
        XCTAssertEqual(titles.count, 2)
        XCTAssertTrue(titles.contains("A2") && titles.contains("B"))
    }

    func testTitleRejectedNotCoerced() { // spec: ENT-TTL-01
        XCTAssertThrowsError(try makeDB().upsertEntry(Entry(title: "   ")))
    }

    func testEmptyTypesRoundTripAsEmptyArray() { // spec: ENT-TYP-01 (inverts testEmptyTypesRoundTripToNil)
        let db = makeDB()
        try! db.upsertEntry(Entry(title: "T", types: []))
        XCTAssertEqual(try! db.loadEntries().first?.types, [], "[] stays [], never nil")
    }

    func testDeleteEntryDropsFromCollectionsAndUnknownIdNoOp() { // spec: EDB-03, COL-09
        let db = makeDB()
        let e = Entry(title: "E")
        try! db.upsertEntry(e)
        try! db.upsertCollection(EntryCollection(id: "C", name: "c", memberIds: [e.id]))
        try! db.deleteEntry(id: e.id)
        XCTAssertEqual(try! db.loadEntries().count, 0)
        XCTAssertEqual(try! db.loadCollections().first?.memberIds, [], "id dropped from every collection")
        XCTAssertNoThrow(try db.deleteEntry(id: "unknown"), "unknown-id delete is a no-op")
    }

    func testStoreIsolationAndRoundTrip() { // spec: EDB-01
        let db = makeDB()
        let e = Entry(title: "Persisted", priorityRating: 42,
                      scheduled: Schedule(start: day("2026-07-21"), end: day("2026-07-21").addingTimeInterval(3600)),
                      completion: Completion(completedAt: day("2026-07-22")),
                      rating: Rating(performanceRating: 88, performanceNotes: "great"))
        try! db.upsertEntry(e)
        let loaded = try! db.loadEntries().first!
        XCTAssertEqual(loaded.priorityRating, 42)
        XCTAssertNotNil(loaded.scheduled)
        XCTAssertTrue(loaded.isCompleted)
        XCTAssertEqual(loaded.rating?.performanceRating, 88)
    }

    // MARK: - EntryService

    func testCompleteGatingNoOp() { // spec: ESVC-04
        let db = makeDB()
        let s = EntryService(db: db)
        let e = Entry(title: "X", completion: nil) // not completable
        s.upsertEntry(e)
        s.completeEntry(id: e.id)
        XCTAssertFalse(s.entries[0].isCompleted)
        XCTAssertNil(s.entries[0].completion, "no aspect auto-added")
    }

    func testCompleteAndRatePersist() { // spec: ESVC-02, ESVC-03
        let db = makeDB()
        let s = EntryService(db: db)
        let e = Entry(title: "X")
        s.upsertEntry(e)
        s.completeEntry(id: e.id)
        s.rateEntry(id: e.id, performance: 80, notes: "ok")
        XCTAssertTrue(s.entries[0].isCompleted)
        XCTAssertEqual(s.entries[0].rating?.performanceRating, 80)
        XCTAssertTrue(EntryService(db: db).loadEntries().first!.isCompleted, "persisted for a fresh service")
    }

    func testMissingIdMutationNoOp() { // spec: ESVC-05
        let s = EntryService(db: makeDB())
        s.completeEntry(id: "nope")
        s.rateEntry(id: "nope", performance: 50)
        XCTAssertTrue(s.entries.isEmpty)
    }

    // MARK: - CollectionService

    func testMembershipDedupRemovalAndCollectionDeleteKeepEntries() { // spec: COL-03, COL-08, COL-10
        let db = makeDB()
        let entries = EntryService(db: db)
        let cols = CollectionService(db: db)
        let e = Entry(title: "E"); entries.upsertEntry(e)
        let c = cols.createCollection(name: "C", ordering: .ordered)
        cols.addMember(collectionId: c.id, entryId: e.id)
        cols.addMember(collectionId: c.id, entryId: e.id)
        XCTAssertEqual(cols.collections[0].memberIds, [e.id], "de-duplicated")
        cols.removeMember(collectionId: c.id, entryId: e.id)
        XCTAssertEqual(cols.collections[0].memberIds, [])
        XCTAssertEqual(entries.entries.count, 1, "entry survives remove-from-collection")
        cols.deleteCollection(id: c.id)
        XCTAssertTrue(cols.collections.isEmpty)
        XCTAssertEqual(entries.loadEntries().count, 1, "member entries survive collection delete")
    }

    // MARK: - SeriesService

    func testCreateSeriesIndependentOccurrencesAndDeleteAll() { // spec: SER-06, SER-10
        let db = makeDB()
        let entries = EntryService(db: db)
        let series = SeriesService(db: db, entries: entries)
        let template = Entry(title: "Standup", deadline: Deadline(date: day("2026-07-20")))
        let s = series.createSeries(template: template, rule: RecurrenceRule(frequency: .daily, interval: 1, end: .afterCount(3)))
        XCTAssertEqual(entries.entries.count, 3)
        XCTAssertEqual(series.series.count, 1)

        let occ0 = entries.entries.first { $0.occurrenceIndex == 0 }!
        entries.completeEntry(id: occ0.id)
        XCTAssertEqual(entries.entries.filter { $0.isCompleted }.count, 1, "occurrences track independently")

        series.delete(entries.entries.first { $0.seriesId == s.id }!, scope: .all)
        XCTAssertEqual(entries.entries.count, 0)
        XCTAssertTrue(series.series.isEmpty, "series pruned on delete-all")
    }
}
