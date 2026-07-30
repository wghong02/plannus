import XCTest
@testable import Metroneo

/// Occurrence generation (DESIGN.md test plan: SER-01..06).
final class RecurrenceEngineTests: XCTestCase {

    private func ymd(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    func testAfterCountGeneratesNIndependentOccurrences() { // spec: SER-03, SER-06
        let template = Entry(title: "Gym", deadline: Deadline(date: day("2026-07-20")))
        let rule = RecurrenceRule(frequency: .daily, interval: 1, end: .afterCount(3))
        let occ = RecurrenceEngine.generate(template: template, rule: rule, seriesId: "S")
        XCTAssertEqual(occ.map(\.occurrenceIndex), [0, 1, 2])
        XCTAssertEqual(Set(occ.map(\.id)).count, 3, "independent ids")
        XCTAssertTrue(occ.allSatisfy { $0.seriesId == "S" })
    }

    func testRuleClampAndAfterCountFloor() { // spec: SER-01, SER-03
        let rule = RecurrenceRule(frequency: .daily, interval: 0, end: .afterCount(0))
        XCTAssertEqual(rule.interval, 1, "interval clamped to ≥ 1")
        let occ = RecurrenceEngine.generate(template: Entry(deadline: Deadline(date: day("2026-07-01"))), rule: rule, seriesId: "S")
        XCTAssertEqual(occ.count, 1, "afterCount floored to 1")
    }

    func testWeeklyIntervalOffsets() { // spec: SER-04
        let start = day("2026-07-06").addingTimeInterval(9 * 3600) // Mon 09:00
        let template = Entry(scheduled: Schedule(start: start, end: start.addingTimeInterval(3600)))
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, end: .afterCount(3))
        let occ = RecurrenceEngine.generate(template: template, rule: rule, seriesId: "S")
        XCTAssertEqual(occ.map { $0.scheduled!.start },
                       [start, start.addingTimeInterval(14 * 86400), start.addingTimeInterval(28 * 86400)],
                       "+0, +14, +28 days; time-of-day preserved")
    }

    func testMonthlyRFC5545Clamp() { // spec: SER-05
        let template = Entry(deadline: Deadline(date: day("2026-01-31")))
        let rule = RecurrenceRule(frequency: .monthly, interval: 1, end: .afterCount(4))
        let occ = RecurrenceEngine.generate(template: template, rule: rule, seriesId: "S")
        XCTAssertEqual(occ.map { ymd($0.deadline!.date) },
                       ["2026-1-31", "2026-2-28", "2026-3-31", "2026-4-30"],
                       "anchor 31 preserved; March returns to 31 (no drift)")
    }

    func testUntilInclusiveAndBeforeStart() { // spec: SER-03
        let template = Entry(deadline: Deadline(date: day("2026-07-01")))
        let inclusive = RecurrenceEngine.generate(
            template: template,
            rule: RecurrenceRule(frequency: .daily, interval: 1, end: .until(day("2026-07-03"))),
            seriesId: "S"
        )
        XCTAssertEqual(inclusive.count, 3, "Jul 1, 2, 3 inclusive")

        let beforeStart = RecurrenceEngine.generate(
            template: template,
            rule: RecurrenceRule(frequency: .daily, interval: 1, end: .until(day("2026-06-15"))),
            seriesId: "S"
        )
        XCTAssertEqual(beforeStart.count, 1, "d before start → just occurrence 0")
    }

    func testTrackingValuesResetOnOccurrences() { // spec: SER-06
        var template = Entry(deadline: Deadline(date: day("2026-07-01")))
        template.completion = Completion(completedAt: Date())
        template.rating = Rating(performanceRating: 90)
        let occ = RecurrenceEngine.generate(
            template: template,
            rule: RecurrenceRule(frequency: .daily, interval: 1, end: .afterCount(2)),
            seriesId: "S"
        )
        XCTAssertTrue(occ.allSatisfy { $0.isCompletable && !$0.isCompleted }, "aspect kept, value reset")
        XCTAssertTrue(occ.allSatisfy { $0.isRatable && !$0.isRated })
    }
}
