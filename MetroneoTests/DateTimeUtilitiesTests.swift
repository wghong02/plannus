import XCTest
@testable import Metroneo

final class DateTimeUtilitiesTests: XCTestCase {
    // [DTU-07] `incompleteTasks(_:forDate:)` was retired in v2 — calendar placement
    // is now `CalendarGrouping` (see CalendarGroupingTests).

    func testDeadlineComposition() {
        let cal = Calendar.current
        let d = day("2026-07-21")

        let eod = DateTimeUtilities.endOfDay(d)
        XCTAssertEqual(cal.component(.hour, from: eod), 23)
        XCTAssertEqual(cal.component(.minute, from: eod), 59)

        let nineThirty = cal.date(bySettingHour: 9, minute: 30, second: 0, of: d)!
        let combined = DateTimeUtilities.combine(day: d, time: nineThirty)
        XCTAssertEqual(cal.component(.hour, from: combined), 9)
        XCTAssertEqual(cal.component(.minute, from: combined), 30)
    }

    func testFormatDeadlineShowsTimeOnlyWhenFlagged() {
        let cal = Calendar.current
        let deadline = cal.date(bySettingHour: 9, minute: 30, second: 0, of: day("2026-07-21"))!
        XCTAssertFalse(DateTimeUtilities.formatDeadline(deadline, hasTime: false).contains("at"))
        XCTAssertTrue(DateTimeUtilities.formatDeadline(deadline, hasTime: true).contains("at"))
    }

    func testStartOfDayZeroesTime() {
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 34, second: 56, of: day("2026-07-21"))!
        let start = DateTimeUtilities.startOfDay(noon)
        XCTAssertEqual(start, day("2026-07-21"))
        XCTAssertEqual(cal.component(.hour, from: start), 0)
        XCTAssertEqual(cal.component(.minute, from: start), 0)
    }

    func testTimeSetsHourAndMinuteToday() {
        let cal = Calendar.current
        let t = DateTimeUtilities.time(hour: 8, minute: 15)
        XCTAssertEqual(cal.component(.hour, from: t), 8)
        XCTAssertEqual(cal.component(.minute, from: t), 15)
        XCTAssertTrue(cal.isDateInToday(t))
    }

    func testShortDateIsDateOnly() {
        // Localized, so assert structure rather than an exact string: non-empty and
        // carrying no time component (date-only styles never use a colon).
        let s = DateTimeUtilities.shortDate(day("2026-07-21"))
        XCTAssertFalse(s.isEmpty)
        XCTAssertFalse(s.contains(":"))
    }
}
