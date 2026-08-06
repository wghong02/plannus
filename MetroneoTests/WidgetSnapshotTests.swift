import XCTest
@testable import Metroneo

/// The app↔widget snapshot (DESIGN — Widgets): the builder that turns the read model
/// into what the widgets render, and the App-Group store round-trip.
final class WidgetSnapshotTests: XCTestCase {

    private func open(_ id: String, _ title: String, due: Date? = nil, hasTime: Bool = false) -> TaskItem {
        TaskItem(reminder: ReminderData(id: id, title: title, dueDate: due, hasDueTime: hasTime), metadata: .empty)
    }
    private func done(_ id: String, _ title: String, at: Date, rating: Int? = nil) -> TaskItem {
        TaskItem(reminder: ReminderData(id: id, title: title, isCompleted: true, completionDate: at),
                 metadata: PerformanceMetadata(rating: rating))
    }

    func testBuilderTaskAndNeedsRatingRows() {
        let items = [open("a", "Alpha", due: day("2026-07-25")), open("b", "Beta")]
        let needs = [done("c", "Gamma", at: day("2026-07-20"))]
        let snap = WidgetSnapshotBuilder.make(items: items, needsRating: needs, rated: [], now: day("2026-07-22"))

        XCTAssertEqual(snap.tasks.map(\.title), ["Alpha", "Beta"])
        XCTAssertNotNil(snap.tasks[0].subtitle, "a due date is pre-formatted into the subtitle")
        XCTAssertNil(snap.tasks[1].subtitle, "no due date → no subtitle")
        XCTAssertEqual(snap.needsRating.map(\.title), ["Gamma"])
        XCTAssertEqual(snap.needsRating.first?.subtitle?.hasPrefix("Completed"), true)
    }

    func testBuilderWeeklyPerformance() {
        let now = day("2026-07-22")
        let rated = [done("r1", "R1", at: day("2026-07-22"), rating: 80),
                     done("r2", "R2", at: day("2026-07-21"), rating: 40),
                     done("old", "Old", at: day("2026-01-01"), rating: 100)] // outside the week
        let snap = WidgetSnapshotBuilder.make(items: [], needsRating: [], rated: rated, now: now)

        XCTAssertEqual(snap.weekly.count, 7, "seven daily buckets")
        XCTAssertEqual(snap.weeklyRatedTotal, 2, "only this week's ratings are counted")
        XCTAssertEqual(snap.weeklyAverage, 60, "(80 + 40) / 2 under default weights")
        XCTAssertEqual(snap.recentRated.map(\.title), ["R1", "R2"], "recent rated, newest first, this week")
    }

    func testBuilderCapsRowCount() {
        let items = (0..<20).map { open("i\($0)", "T\($0)") }
        let snap = WidgetSnapshotBuilder.make(items: items, needsRating: [], rated: [])
        XCTAssertEqual(snap.tasks.count, WidgetSnapshotBuilder.rowLimit, "rows are capped for the widget")
    }

    func testStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "widget-test-\(UUID().uuidString)")!
        XCTAssertEqual(WidgetSnapshotStore.read(from: defaults), .empty, "unset → empty")

        let snap = WidgetSnapshotBuilder.make(items: [open("a", "A")], needsRating: [], rated: [])
        WidgetSnapshotStore.write(snap, to: defaults)
        XCTAssertEqual(WidgetSnapshotStore.read(from: defaults).tasks.map(\.title), ["A"], "read matches write")
    }
}
