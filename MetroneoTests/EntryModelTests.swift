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

    func testMoveMemberOutOfRangeIsNoOp() { // spec: COL-01 (guarded reorder)
        var c = EntryCollection(name: "A", ordering: .ordered, memberIds: ["x", "y"])
        c.moveMember(fromOffsets: IndexSet(integer: 5), toOffset: 0) // bad source
        XCTAssertEqual(c.memberIds, ["x", "y"], "out-of-range source is a no-op, not a trap")
        c.moveMember(fromOffsets: IndexSet(integer: 0), toOffset: 9) // bad destination
        XCTAssertEqual(c.memberIds, ["x", "y"], "out-of-range destination is a no-op")
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

    func testIsOverdue() { // spec: ENT-OVR-01
        let now = day("2026-07-21").addingTimeInterval(12 * 3600) // noon, Jul 21
        // Timed deadline in the past, still open → overdue.
        let pastDue = Entry(deadline: Deadline(date: now.addingTimeInterval(-3600), hasTime: true))
        XCTAssertTrue(pastDue.isOverdue(asOf: now))
        // Completed → never overdue.
        var done = pastDue; done.completion = Completion(completedAt: now)
        XCTAssertFalse(done.isOverdue(asOf: now))
        // Not completable (no completion aspect) → never overdue.
        XCTAssertFalse(Entry(deadline: Deadline(date: now.addingTimeInterval(-3600), hasTime: true),
                             completion: nil).isOverdue(asOf: now))
        // Future deadline → not overdue.
        XCTAssertFalse(Entry(deadline: Deadline(date: now.addingTimeInterval(3600), hasTime: true)).isOverdue(asOf: now))
        // Untimed → not overdue.
        XCTAssertFalse(Entry(title: "x").isOverdue(asOf: now))
        // Date-only deadline yesterday → overdue (past that day's end).
        XCTAssertTrue(Entry(deadline: Deadline(date: day("2026-07-20"), hasTime: false)).isOverdue(asOf: now))
        // All-day event today → NOT overdue until the day ends.
        XCTAssertFalse(Entry(scheduled: Schedule(start: day("2026-07-21"), end: day("2026-07-21"), allDay: true))
                        .isOverdue(asOf: now), "all-day today isn't overdue at noon")
    }

    func testDueReminderCount() { // spec: REM-09
        let now = day("2026-07-21").addingTimeInterval(12 * 3600) // noon
        func reminder(at date: Date, lead: Int = 0, completed: Bool = false) -> Entry {
            Entry(deadline: Deadline(date: date, hasTime: true),
                  reminderLeadMinutes: lead,
                  completion: completed ? Completion(completedAt: now) : Completion())
        }
        let entries = [
            reminder(at: now.addingTimeInterval(-3600)), // fired an hour ago, incomplete → due
            reminder(at: now.addingTimeInterval(-60), completed: true), // fired but completed → excluded
            reminder(at: now.addingTimeInterval(3600)), // fires later → not due
            Entry(deadline: Deadline(date: now.addingTimeInterval(-3600))), // no reminder → excluded
            Entry(title: "undated", reminderLeadMinutes: 0), // no time key → excluded
        ]
        XCTAssertEqual(ReminderTiming.dueReminderCount(entries, by: now), 1, "only overdue, incomplete reminders count")
        // Widening the horizon past the future reminder counts it too.
        XCTAssertEqual(ReminderTiming.dueReminderCount(entries, by: now.addingTimeInterval(7200)), 2)
    }
}
