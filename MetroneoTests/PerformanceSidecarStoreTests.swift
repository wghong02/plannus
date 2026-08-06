import XCTest
@testable import Metroneo

/// The performance sidecar (DESIGN R3): per-entry upsert/read/drop and the
/// orphan-reconciliation invariant (R3.2).
final class PerformanceSidecarStoreTests: XCTestCase {
    private func make() -> PerformanceSidecarStore { try! PerformanceSidecarStore(inMemory: true) }

    func testUpsertReadAndDropWhenEmpty() { // spec: R3.1
        let s = make()
        XCTAssertEqual(s.metadata(for: "x"), .empty, "unset → empty")

        s.setMetadata(PerformanceMetadata(rating: 80, estimatedDuration: 30), for: "x")
        XCTAssertEqual(s.metadata(for: "x").rating, 80)
        XCTAssertEqual(s.metadata(for: "x").estimatedDuration, 30)

        // Updating one field keeps the row; clearing to empty drops it.
        s.setMetadata(PerformanceMetadata(rating: 90), for: "x")
        XCTAssertEqual(s.metadata(for: "x").rating, 90)
        XCTAssertNil(s.metadata(for: "x").estimatedDuration)

        s.setMetadata(.empty, for: "x")
        XCTAssertEqual(s.metadata(for: "x"), .empty)
        XCTAssertTrue(s.storedIds().isEmpty, "empty metadata drops the row")
    }

    func testReconcilePrunesOrphansAfterGrace() { // spec: R3.2 (two-sync grace)
        let s = make()
        s.setMetadata(PerformanceMetadata(rating: 1), for: "live")
        s.setMetadata(PerformanceMetadata(rating: 2), for: "gone")

        // First successful sync: an absent id is marked pending, NOT pruned yet.
        s.reconcile(liveIds: ["live"], fetchSucceeded: true)
        XCTAssertEqual(s.metadata(for: "gone").rating, 2, "not pruned on first absence")

        // Second consecutive sync still absent → pruned.
        s.reconcile(liveIds: ["live"], fetchSucceeded: true)
        XCTAssertEqual(s.metadata(for: "live").rating, 1, "live row kept")
        XCTAssertEqual(s.metadata(for: "gone"), .empty, "orphan pruned after two syncs")
        XCTAssertEqual(s.storedIds(), ["live"])
    }

    func testReconcileReappearanceClearsPending() { // spec: R3.2 (grace resets)
        let s = make()
        s.setMetadata(PerformanceMetadata(rating: 5), for: "flaky")
        s.reconcile(liveIds: [], fetchSucceeded: true)        // absent once (pending)
        s.reconcile(liveIds: ["flaky"], fetchSucceeded: true) // reappears → clears pending
        s.reconcile(liveIds: [], fetchSucceeded: true)        // absent again → only first strike
        XCTAssertEqual(s.metadata(for: "flaky").rating, 5, "a reappearance resets the grace, so no prune")
    }

    func testReconcileEmptyGuardSkipsPruning() { // spec: R3.2 (empty-guard)
        let s = make()
        s.setMetadata(PerformanceMetadata(rating: 7), for: "keep")
        // An empty live set while the sidecar has data is "unknown", not "all gone".
        s.reconcile(liveIds: [], fetchSucceeded: true)
        s.reconcile(liveIds: [], fetchSucceeded: true)
        XCTAssertEqual(s.metadata(for: "keep").rating, 7, "empty fetch never prunes")
        // A failed fetch also prunes nothing.
        s.reconcile(liveIds: ["something"], fetchSucceeded: false)
        s.reconcile(liveIds: ["something"], fetchSucceeded: false)
        XCTAssertEqual(s.metadata(for: "keep").rating, 7, "failed fetch never prunes")
    }

    func testReconcileExemptsOccurrenceSnapshots() { // spec: R3.2/R3.3
        let s = make()
        let occDate = Date(timeIntervalSince1970: 1_000_000)
        let occId = s.recordOccurrence(seriesId: "series", title: "Water plants", listId: "home",
                                       priority: .medium, occurrenceDate: occDate, completionDate: occDate)
        s.setMetadata(PerformanceMetadata(rating: 88), for: occId)

        // The series id is absent from the live set across many syncs; the historical
        // occurrence snapshot must never be pruned.
        s.reconcile(liveIds: [], fetchSucceeded: true)
        s.reconcile(liveIds: ["unrelated"], fetchSucceeded: true)
        s.reconcile(liveIds: ["unrelated"], fetchSucceeded: true)
        XCTAssertEqual(s.metadata(for: occId).rating, 88, "occurrence snapshots are exempt from reconciliation")
        XCTAssertEqual(s.occurrences().count, 1)
    }

    func testRecordOccurrenceIsIdempotent() { // spec: R3.3
        let s = make()
        let occDate = Date(timeIntervalSince1970: 2_000_000)
        let id1 = s.recordOccurrence(seriesId: "s", title: "A", listId: "l", priority: .high,
                                     occurrenceDate: occDate, completionDate: occDate)
        s.setMetadata(PerformanceMetadata(rating: 70), for: id1)
        // A later best-effort capture of the same occurrence must not duplicate or
        // clobber the exact (rated) record.
        let id2 = s.recordOccurrence(seriesId: "s", title: "A", listId: "l", priority: .high,
                                     occurrenceDate: occDate, completionDate: occDate.addingTimeInterval(999))
        XCTAssertEqual(id1, id2, "same occurrence → same id")
        XCTAssertEqual(s.occurrences().count, 1, "no duplicate row")
        XCTAssertEqual(s.metadata(for: id1).rating, 70, "existing rating preserved")
    }
}
