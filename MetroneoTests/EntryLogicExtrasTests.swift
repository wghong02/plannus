import XCTest
@testable import Metroneo

/// Remaining pure-logic rows (DESIGN.md test plan: SLD-02, DUR-01/03, COL-07,
/// EGRP-01).
final class EntryLogicExtrasTests: XCTestCase {

    func testSliderClamp() { // spec: SLD-02
        XCTAssertEqual(SliderField.clamp("150"), 100)
        XCTAssertEqual(SliderField.clamp("-5"), 0)
        XCTAssertEqual(SliderField.clamp("42"), 42)
        XCTAssertNil(SliderField.clamp("abc"), "non-numeric → keep current")
        XCTAssertNil(SliderField.clamp(""), "blank → keep current")
    }

    func testDurationDelta() { // spec: DUR-01, DUR-03
        XCTAssertNil(Entry(estimatedDuration: 30).durationDeltaMinutes, "actual missing")
        XCTAssertNil(Entry(actualDuration: 30).durationDeltaMinutes, "estimate missing")
        XCTAssertEqual(Entry(estimatedDuration: 30, actualDuration: 45).durationDeltaMinutes, 15, "over")
        XCTAssertEqual(Entry(estimatedDuration: 30, actualDuration: 20).durationDeltaMinutes, -10, "under")
    }

    func testCollectionMemberDisplayOrder() { // spec: COL-07
        let xray = Entry(title: "Xray", deadline: Deadline(date: day("2026-07-25")))
        let apple = Entry(title: "Apple", deadline: Deadline(date: day("2026-07-21")))
        let entries = [xray, apple]

        let ordered = EntryCollection(name: "O", ordering: .ordered, memberIds: [xray.id, apple.id])
        XCTAssertEqual(CollectionMembers.resolve(ordered, from: entries, sort: .timeAscending).map(\.title),
                       ["Xray", "Apple"], "ordered uses memberIds sequence")

        let parallel = EntryCollection(name: "P", ordering: .parallel, memberIds: [xray.id, apple.id])
        XCTAssertEqual(CollectionMembers.resolve(parallel, from: entries, sort: .timeAscending).map(\.title),
                       ["Apple", "Xray"], "parallel uses the active D7 sort (Apple is due sooner)")
    }

    func testEntriesOnEmptyDay() { // spec: EGRP-01
        let due = Entry(deadline: Deadline(date: day("2026-07-21")))
        XCTAssertEqual(CalendarGrouping.entries([due], on: day("2026-07-22")).count, 0, "a day with none → []")
    }
}
