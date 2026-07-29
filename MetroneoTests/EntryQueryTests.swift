import XCTest
@testable import Metroneo

/// Sort + filter (DESIGN.md test plan: SORT-02/03/04/06/07).
final class EntryQueryTests: XCTestCase {

    func testTimeAscendingUntimedLastWithTieBreak() { // spec: SORT-02
        let beta = Entry(title: "Beta", deadline: Deadline(date: day("2026-07-21")))
        let alpha = Entry(title: "alpha", deadline: Deadline(date: day("2026-07-21"))) // same key → title tie
        let later = Entry(title: "Zed", deadline: Deadline(date: day("2026-07-25")))
        let loose = Entry(title: "Loose") // untimed
        let sorted = EntryQuery.sort([later, loose, beta, alpha], by: .timeAscending)
        XCTAssertEqual(sorted.map(\.title), ["alpha", "Beta", "Zed", "Loose"])
    }

    func testTimeDescendingKeepsUntimedLast() { // spec: SORT-03
        let early = Entry(title: "Early", deadline: Deadline(date: day("2026-07-21")))
        let late = Entry(title: "Late", deadline: Deadline(date: day("2026-07-25")))
        let loose = Entry(title: "Loose")
        let sorted = EntryQuery.sort([early, loose, late], by: .timeDescending)
        XCTAssertEqual(sorted.map(\.title), ["Late", "Early", "Loose"])
    }

    func testAlphabeticalCaseInsensitive() { // spec: SORT-04
        let sorted = EntryQuery.sort(
            [Entry(title: "banana"), Entry(title: "Apple"), Entry(title: "cherry")],
            by: .alphabetical
        )
        XCTAssertEqual(sorted.map(\.title), ["Apple", "banana", "cherry"])
    }

    func testFilterAndAcrossFacets() { // spec: SORT-06, SORT-07
        let done = Entry(title: "done", types: ["work"], completion: Completion(completedAt: Date()))
        let todo = Entry(title: "todo", types: ["work"])
        let marker = Entry(title: "marker", types: ["work"], completion: nil) // non-completable
        let all = [done, todo, marker]

        XCTAssertEqual(EntryQuery.filter(all, with: EntryFilter(completion: .completed, tag: "work")).map(\.title), ["done"])
        XCTAssertEqual(EntryQuery.filter(all, with: EntryFilter(completion: .upcoming)).map(\.title), ["todo"],
                       "non-completable matches neither")
        XCTAssertEqual(EntryQuery.filter(all, with: EntryFilter(completion: .any)).count, 3)
        XCTAssertEqual(EntryQuery.filter(all, with: EntryFilter(tag: "home")).count, 0)
    }
}
