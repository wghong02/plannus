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

    func testReconcilePrunesOrphans() { // spec: R3.2 (R3.2)
        let s = make()
        s.setMetadata(PerformanceMetadata(rating: 1), for: "live")
        s.setMetadata(PerformanceMetadata(rating: 2), for: "gone")

        s.reconcile(liveIds: ["live", "other"])
        XCTAssertEqual(s.metadata(for: "live").rating, 1, "live row kept")
        XCTAssertEqual(s.metadata(for: "gone"), .empty, "orphan pruned")
        XCTAssertEqual(s.storedIds(), ["live"])
    }
}
