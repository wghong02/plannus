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
