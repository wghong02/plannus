import XCTest
@testable import Metroneo

/// Calendar placement + within-day order (DESIGN.md test plan: EGRP-02..06).
final class CalendarGroupingTests: XCTestCase {

    func testMultiDaySpan() { // spec: EGRP-02
        let monEve = day("2026-07-20").addingTimeInterval(23 * 3600)  // Mon 23:00
        let tueEarly = day("2026-07-21").addingTimeInterval(1 * 3600) // Tue 01:00
        let spanning = Entry(scheduled: Schedule(start: monEve, end: tueEarly))
        let days = CalendarGrouping.days(of: spanning)
        XCTAssertTrue(days.contains(day("2026-07-20")))
        XCTAssertTrue(days.contains(day("2026-07-21")))
    }

    func testBothScheduledAndDeadlineDays() { // spec: EGRP-03
        let entry = Entry(
            scheduled: Schedule(start: day("2026-07-21").addingTimeInterval(9 * 3600),
                                end: day("2026-07-21").addingTimeInterval(10 * 3600)),
            deadline: Deadline(date: day("2026-07-24"))
        )
        let days = CalendarGrouping.days(of: entry)
        XCTAssertTrue(days.contains(day("2026-07-21")))
        XCTAssertTrue(days.contains(day("2026-07-24")))
    }

    func testUndatedOnNoDay() { // spec: EGRP-04
        XCTAssertTrue(CalendarGrouping.days(of: Entry()).isEmpty)
    }

    func testWithinDayOrderCompletedBelow() { // spec: EGRP-05, EGRP-04
        let d = day("2026-07-21")
        let timed = Entry(title: "Meeting",
                          scheduled: Schedule(start: d.addingTimeInterval(9 * 3600), end: d.addingTimeInterval(10 * 3600)))
        let allDay = Entry(title: "Holiday", scheduled: Schedule(start: d, end: d, allDay: true))
        let due = Entry(title: "Report", deadline: Deadline(date: d.addingTimeInterval(15 * 3600), hasTime: true))
        let doneEarly = Entry(title: "EarlyCall",
                              scheduled: Schedule(start: d.addingTimeInterval(8 * 3600), end: d.addingTimeInterval(8 * 3600 + 1800)),
                              completion: Completion(completedAt: Date()))
        let ordered = CalendarGrouping.entries([due, doneEarly, allDay, timed], on: d)
        XCTAssertEqual(ordered.map(\.title), ["Meeting", "Holiday", "Report", "EarlyCall"],
                       "incomplete timed→all-day→deadline, completed last despite its 8am time")
    }

    func testEntryScheduledAndDueSameDayAppearsOnce() { // spec: EGRP-06
        let d = day("2026-07-21")
        let both = Entry(title: "Both",
                         scheduled: Schedule(start: d.addingTimeInterval(9 * 3600), end: d.addingTimeInterval(10 * 3600)),
                         deadline: Deadline(date: d))
        let onDay = CalendarGrouping.entries([both], on: d)
        XCTAssertEqual(onDay.count, 1)
    }
}
