import XCTest
@testable import Metroneo

/// Series edit/delete scopes + M2M membership (DESIGN.md test plan: SER-08, COL-02).
final class SeriesScopeTests: XCTestCase {
    private func makeDB() -> EntryDatabase { try! EntryDatabase(inMemory: true) }

    private func makeSeries() -> (EntryService, SeriesService, Series) {
        let db = makeDB()
        let entries = EntryService(db: db)
        let series = SeriesService(db: db, entries: entries)
        let template = Entry(title: "Standup", deadline: Deadline(date: day("2026-07-20")))
        let s = series.createSeries(template: template, rule: RecurrenceRule(frequency: .daily, interval: 1, end: .afterCount(3)))
        return (entries, series, s)
    }

    func testEditThisOnlyDetaches() { // spec: SER-08
        let (entries, series, s) = makeSeries()
        var occ1 = entries.entries.first { $0.seriesId == s.id && $0.occurrenceIndex == 1 }!
        occ1.title = "Detached"
        series.edit(occ1, scope: .thisOnly)

        let detached = entries.entries.first { $0.title == "Detached" }!
        XCTAssertNil(detached.seriesId, "this-only detaches the occurrence")
        XCTAssertNil(detached.occurrenceIndex)
        XCTAssertEqual(entries.entries.filter { $0.seriesId == s.id }.count, 2, "siblings stay in the series")
    }

    func testEditAllPropagatesAndRegenerates() { // spec: SER-08
        let (entries, series, s) = makeSeries()
        var occ0 = entries.entries.first { $0.occurrenceIndex == 0 }!
        occ0.title = "Renamed"
        series.edit(occ0, scope: .all)

        let members = entries.entries.filter { $0.seriesId == s.id }
        XCTAssertEqual(members.count, 3)
        XCTAssertTrue(members.allSatisfy { $0.title == "Renamed" }, "all occurrences take the edit")
    }

    func testEditThisAndFutureSplits() { // spec: SER-08
        let (entries, series, _) = makeSeries()
        var occ1 = entries.entries.first { $0.occurrenceIndex == 1 }!
        occ1.title = "Changed"
        series.edit(occ1, scope: .thisAndFuture)

        XCTAssertEqual(entries.entries.filter { $0.title == "Standup" }.count, 1, "past occurrence unchanged")
        XCTAssertEqual(entries.entries.filter { $0.title == "Changed" }.count, 2, "this + future regenerated")
    }

    func testDeleteThisAndFuture() { // spec: SER-08
        let (entries, series, s) = makeSeries()
        let occ1 = entries.entries.first { $0.occurrenceIndex == 1 }!
        series.delete(occ1, scope: .thisAndFuture)
        XCTAssertEqual(entries.entries.filter { $0.seriesId == s.id }.count, 1, "only occurrence 0 remains")
    }

    // MARK: - Edit returns the surviving occurrence id (membership target)

    func testEditThisOnlyReturnsDetachedLiveId() { // spec: SER-08
        let (entries, series, _) = makeSeries()
        var occ1 = entries.entries.first { $0.occurrenceIndex == 1 }!
        occ1.title = "Detached"
        let survivor = series.edit(occ1, scope: .thisOnly)
        XCTAssertEqual(survivor, occ1.id, "this-only keeps the same id")
        XCTAssertTrue(entries.entries.contains { $0.id == survivor }, "survivor is a live entry")
    }

    func testEditAllReturnsLiveRegeneratedId() { // spec: SER-08
        let (entries, series, s) = makeSeries()
        var occ1 = entries.entries.first { $0.occurrenceIndex == 1 }!
        let originalId = occ1.id
        occ1.title = "Renamed"
        let survivor = series.edit(occ1, scope: .all)

        XCTAssertFalse(entries.entries.contains { $0.id == originalId }, "the edited occurrence is regenerated away")
        let survivorId = try? XCTUnwrap(survivor)
        XCTAssertNotNil(survivorId)
        XCTAssertTrue(entries.entries.contains { $0.id == survivorId }, "edit reports a live survivor, not the deleted id")
        XCTAssertEqual(entries.entries.first { $0.id == survivorId }?.seriesId, s.id, "survivor stays in the series")
        XCTAssertEqual(entries.entries.first { $0.id == survivorId }?.occurrenceIndex, 1, "survivor is the same index")
    }

    func testEditThisAndFutureReturnsNewSeriesFirstOccurrence() { // spec: SER-08
        let (entries, series, _) = makeSeries()
        var occ1 = entries.entries.first { $0.occurrenceIndex == 1 }!
        let originalId = occ1.id
        occ1.title = "Changed"
        let survivor = series.edit(occ1, scope: .thisAndFuture)

        XCTAssertFalse(entries.entries.contains { $0.id == originalId }, "the edited occurrence is regenerated away")
        let survivorId = try? XCTUnwrap(survivor)
        XCTAssertTrue(entries.entries.contains { $0.id == survivorId }, "survivor is a live entry")
        XCTAssertEqual(entries.entries.first { $0.id == survivorId }?.occurrenceIndex, 0, "survivor is occurrence 0 of the new series")
    }

    /// End-to-end for the editor's membership sync: an "All" edit must not strand
    /// collection membership on the deleted occurrence or leave a dangling id.
    func testMembershipReAttachesToLiveOccurrenceAfterEditAll() { // spec: SER-08 / COL-02
        let db = makeDB()
        let entries = EntryService(db: db)
        let series = SeriesService(db: db, entries: entries)
        let cols = CollectionService(db: db)
        let template = Entry(title: "Standup", deadline: Deadline(date: day("2026-07-20")))
        let s = series.createSeries(template: template, rule: RecurrenceRule(frequency: .daily, interval: 1, end: .afterCount(3)))

        let occ1 = entries.entries.first { $0.seriesId == s.id && $0.occurrenceIndex == 1 }!
        let collection = cols.createCollection(name: "Focus", ordering: .ordered)
        cols.addMember(collectionId: collection.id, entryId: occ1.id)

        var edited = occ1
        edited.title = "Renamed"
        let survivor = series.edit(edited, scope: .all)

        // Mirror the editor: refresh the cache after the regenerate, then sync.
        cols.loadCollections()
        let survivorId = survivor!
        cols.addMember(collectionId: collection.id, entryId: survivorId)

        let members = cols.collections.first { $0.id == collection.id }!.memberIds
        XCTAssertEqual(members, [survivorId], "membership lands on the live occurrence, not the deleted id")
        XCTAssertTrue(members.allSatisfy { id in entries.entries.contains { $0.id == id } },
                      "collection has no dangling member ids")
    }

    func testM2MIndependentMembership() { // spec: COL-02
        let db = makeDB()
        let cols = CollectionService(db: db)
        let a = cols.createCollection(name: "A", ordering: .ordered)
        let b = cols.createCollection(name: "B", ordering: .ordered)
        for id in ["x", "y", "z"] { cols.addMember(collectionId: a.id, entryId: id) }
        cols.addMember(collectionId: b.id, entryId: "z")

        cols.reorder(collectionId: a.id, fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(cols.collections.first { $0.id == a.id }?.memberIds, ["z", "x", "y"])
        XCTAssertEqual(cols.collections.first { $0.id == b.id }?.memberIds, ["z"], "B's order is independent of A")
    }
}
