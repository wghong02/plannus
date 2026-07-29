import XCTest
@testable import Metroneo

/// Pure model + small-utility behaviors (DESIGN.md test plan: ENT-*, COL-01/03,
/// CLR-01/03, TRND-01, REM-02/03/04).
final class EntryModelTests: XCTestCase {

    func testEntryInitDefaults() { // spec: ENT-01
        let e = Entry()
        XCTAssertNotNil(UUID(uuidString: e.id), "id is a UUID assigned at construction")
        XCTAssertEqual(e.title, "")
        XCTAssertEqual(e.types, [])
        XCTAssertEqual(e.priorityRating, 50)
        XCTAssertNil(e.scheduled); XCTAssertNil(e.deadline)
        XCTAssertNil(e.reminderLeadMinutes)
        XCTAssertNil(e.seriesId); XCTAssertNil(e.occurrenceIndex)
        XCTAssertTrue(e.isCompletable && e.isRatable, "tracking on by default")
        XCTAssertFalse(e.isCompleted || e.isRated, "present-but-empty, not yet recorded")
    }

    func testAspectPredicates() { // spec: ENT-02
        let none = Entry(completion: nil, rating: nil)
        XCTAssertFalse(none.isCompletable); XCTAssertFalse(none.isRatable)

        var e = Entry()
        XCTAssertTrue(e.isCompletable && !e.isCompleted)
        XCTAssertTrue(e.isRatable && !e.isRated)
        e.rating = Rating(performanceRating: 80)
        XCTAssertTrue(e.isRated)
        e.completion = Completion(completedAt: Date())
        XCTAssertTrue(e.isCompleted)
    }

    func testDisplayRuleAndTimeKey() { // spec: ENT-03, SORT-01
        let start = day("2026-07-21").addingTimeInterval(9 * 3600)
        let scheduled = Entry(scheduled: Schedule(start: start, end: start.addingTimeInterval(3600)))
        XCTAssertTrue(scheduled.isEvent)
        XCTAssertEqual(scheduled.timeKey, start)

        let deadlineOnly = Entry(deadline: Deadline(date: day("2026-07-21")))
        XCTAssertFalse(deadlineOnly.isEvent)
        XCTAssertEqual(deadlineOnly.timeKey, day("2026-07-21"))

        XCTAssertTrue(Entry().isUntimed)
    }

    func testCollectionDedupAndReorder() { // spec: COL-01, COL-03
        var c = EntryCollection(name: "A", ordering: .ordered, memberIds: ["x", "y", "x"])
        XCTAssertEqual(c.memberIds, ["x", "y"], "init de-dupes")
        c.addMember("x")
        XCTAssertEqual(c.memberIds, ["x", "y"], "adding a present id is a no-op")
        c.addMember("z")
        XCTAssertEqual(c.memberIds, ["x", "y", "z"])
        c.moveMember(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(c.memberIds, ["z", "x", "y"])
        c.removeMember("x")
        XCTAssertEqual(c.memberIds, ["z", "y"])
    }

    func testColorHexRoundTripAndContrast() { // spec: CLR-01, CLR-03
        let parsed = ColorHex.parse("#1B5E20FF")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(ColorHex.string(parsed!), "#1B5E20FF")
        XCTAssertNil(ColorHex.parse("nope"))
        XCTAssertTrue(ColorHex.preferBlackText(onFill: ColorHex.parse("#FFF176FF")!), "light yellow → black")
        XCTAssertFalse(ColorHex.preferBlackText(onFill: ColorHex.parse("#1B5E20FF")!), "dark green → white")
    }

    func testTrendClassification() { // spec: TRND-01
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 60, lastAverage: 66, improvingPercent: 5, decliningPercent: -5), .improving)
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 60, lastAverage: 66, improvingPercent: 15, decliningPercent: -15), .neutral)
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 80, lastAverage: 60, improvingPercent: 5, decliningPercent: -5), .declining)
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 0, lastAverage: 5, improvingPercent: 5, decliningPercent: -5), .improving)
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 0, lastAverage: 0, improvingPercent: 5, decliningPercent: -5), .neutral)
    }

    func testReminderTimingAndValidity() { // spec: REM-02, REM-03, REM-04
        let deadline = day("2026-07-21").addingTimeInterval(17 * 3600) // 17:00
        var e = Entry(deadline: Deadline(date: deadline, hasTime: true), reminderLeadMinutes: 30)
        XCTAssertEqual(ReminderTiming.fireDate(for: e), deadline.addingTimeInterval(-30 * 60))
        e.reminderLeadMinutes = 0
        XCTAssertEqual(ReminderTiming.fireDate(for: e), deadline, "at time")
        XCTAssertNil(ReminderTiming.fireDate(for: Entry()), "no reminder / undated")
        XCTAssertFalse(ReminderTiming.shouldSchedule(fireDate: deadline.addingTimeInterval(-60), now: deadline))
        XCTAssertTrue(ReminderTiming.shouldSchedule(fireDate: deadline.addingTimeInterval(60), now: deadline))

        XCTAssertTrue(ReminderLead.preset(minutes: 0).isValid)
        XCTAssertTrue(ReminderLead.custom(minutes: 45).isValid)
        XCTAssertFalse(ReminderLead.custom(minutes: 0).isValid, "custom must be > 0")
        XCTAssertFalse(ReminderLead.preset(minutes: 7).isValid)
    }
}
