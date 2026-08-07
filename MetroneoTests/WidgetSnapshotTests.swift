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

    // MARK: - Widget interaction logic (what the AppIntents run)

    func testPerformanceToggleFlipsSharedMode() { // TogglePerformanceModeIntent
        let d = UserDefaults(suiteName: "widget-test-\(UUID().uuidString)")!
        XCTAssertFalse(WidgetSnapshotStore.showRatedMode(from: d), "starts on the chart view")
        XCTAssertTrue(WidgetSnapshotStore.toggleRatedMode(in: d), "toggle → rated list")
        XCTAssertTrue(WidgetSnapshotStore.showRatedMode(from: d))
        XCTAssertFalse(WidgetSnapshotStore.toggleRatedMode(in: d), "toggle → back to chart")
    }

    func testCompleteCircleRemovesTaskFromSnapshot() { // CompleteReminderIntent optimistic update
        let d = UserDefaults(suiteName: "widget-test-\(UUID().uuidString)")!
        let snap = WidgetSnapshot(
            tasks: [WidgetTask(id: "a", title: "A", subtitle: nil), WidgetTask(id: "b", title: "B", subtitle: nil)],
            needsRating: [], weekly: [], weeklyRatedTotal: 0, weeklyAverage: 0, recentRated: [], generatedAt: Date())
        WidgetSnapshotStore.write(snap, to: d)
        WidgetSnapshotStore.removeTask(id: "a", in: d)
        XCTAssertEqual(WidgetSnapshotStore.read(from: d).tasks.map(\.id), ["b"],
                       "tapping the complete circle drops the row from the widget snapshot")
    }

    // MARK: - Full pipeline: TaskService refresh → App-Group store → widget read path

    private final class SuitePublisher: WidgetSnapshotPublishing {
        let defaults: UserDefaults
        init(_ defaults: UserDefaults) { self.defaults = defaults }
        func publish(_ snapshot: WidgetSnapshot) { WidgetSnapshotStore.write(snapshot, to: defaults) }
    }

    @MainActor
    func testRefreshPipelineReachesWidgetReadPath() async {
        let group = UserDefaults(suiteName: "widget-test-\(UUID().uuidString)")! // stands in for the App Group
        let store = FakeReminderStore()
        let sidecar = try! PerformanceSidecarStore(inMemory: true)
        let svc = TaskService(store: store, sidecar: sidecar,
                              defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
                              widgetPublisher: SuitePublisher(group))
        store.save(ReminderData(title: "Open"))
        store.seed(ReminderData(id: "d", title: "DoneUnrated", isCompleted: true, completionDate: Date()))

        await svc.refresh()

        // Exactly what SnapshotProvider reads for its timeline entry:
        let snapshot = WidgetSnapshotStore.read(from: group)
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Open"], "the widget's read path sees the published tasks")
        XCTAssertEqual(snapshot.needsRating.map(\.title), ["DoneUnrated"])
    }
}
