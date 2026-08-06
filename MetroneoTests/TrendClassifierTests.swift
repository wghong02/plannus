import XCTest
@testable import Metroneo

/// Overall-trend classification (DESIGN D12) — the live path used by the
/// Performance tab's "Overall Trend" insight, with configurable thresholds.
final class TrendClassifierTests: XCTestCase {

    func testNeutralBandAndDirections() { // default ±5%
        func c(_ first: Double, _ last: Double) -> TrendClassifier.Direction {
            TrendClassifier.classify(firstAverage: first, lastAverage: last, improvingPercent: 5, decliningPercent: -5)
        }
        XCTAssertEqual(c(80, 82), .neutral, "+2.5% within the band")
        XCTAssertEqual(c(80, 84), .neutral, "+5% is not > 5")
        XCTAssertEqual(c(80, 88), .improving, "+10%")
        XCTAssertEqual(c(80, 72), .declining, "-10%")
    }

    func testZeroFirstBucketSpecialCase() {
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 0, lastAverage: 50, improvingPercent: 5, decliningPercent: -5), .improving)
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 0, lastAverage: 0, improvingPercent: 5, decliningPercent: -5), .neutral)
    }

    func testConfigurableThresholds() {
        // A +10% change is "improving" by default but "neutral" under a stricter +15% cutoff.
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 80, lastAverage: 88, improvingPercent: 15, decliningPercent: -15), .neutral)
        XCTAssertEqual(TrendClassifier.classify(firstAverage: 80, lastAverage: 88, improvingPercent: 8, decliningPercent: -8), .improving)
    }
}
