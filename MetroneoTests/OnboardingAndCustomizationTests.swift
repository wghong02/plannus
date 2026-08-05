import XCTest
@testable import Metroneo

/// Onboarding gate + performance customization persistence (DESIGN.md test plan:
/// TUT-01/02, LBL-01/02, CLR-01, TRND-02).
final class OnboardingAndCustomizationTests: XCTestCase {
    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: "test-\(UUID().uuidString)")! }

    // MARK: - Onboarding (D13)

    func testOnboardingShowsOnceAndReplays() { // spec: TUT-01, TUT-02
        let d = makeDefaults()
        XCTAssertTrue(OnboardingGate.shouldShow(d), "shown on first launch")
        OnboardingGate.markSeen(d)
        XCTAssertFalse(OnboardingGate.shouldShow(d), "not shown again after seen")
        XCTAssertFalse(OnboardingGate.shouldShow(d), "flag persists")
        OnboardingGate.replay(d)
        XCTAssertTrue(OnboardingGate.shouldShow(d), "replayable from Settings")
    }

    // MARK: - Labels (D8)

    func testLabelsCustomBlankFallbackAndPersist() { // spec: LBL-01, LBL-02
        let d = makeDefaults()
        let s = PerformanceCustomizationService(defaults: d)
        XCTAssertEqual(s.label(for: .excellent), "Excellent", "default label")
        s.setLabel("Crushed it", for: .excellent)
        XCTAssertEqual(s.label(for: .excellent), "Crushed it")
        s.setLabel("   ", for: .excellent)
        XCTAssertEqual(s.label(for: .excellent), "Excellent", "blank → default")

        s.setLabel("Nailed it", for: .good)
        XCTAssertEqual(PerformanceCustomizationService(defaults: d).label(for: .good), "Nailed it", "persists across instances")
    }

    // MARK: - Colors (D10)

    func testPriorityWeightsPersistAndDefault() { // spec: R7.3
        let d = makeDefaults()
        let s = PerformanceCustomizationService(defaults: d)
        XCTAssertEqual(s.priorityWeights, .defaults)
        XCTAssertEqual(s.priorityWeights.weight(for: .high), 4, "default High weight")
        XCTAssertEqual(s.priorityWeights.weight(for: .none), 1)

        s.setPriorityWeights(PriorityWeights(none: 0, low: 1, medium: 2, high: 3))
        XCTAssertEqual(PerformanceCustomizationService(defaults: d).priorityWeights.weight(for: .high), 3, "persists + reloads")
    }

    func testCustomizationDecodesLegacyWithoutPriorityWeights() throws { // spec: R7.3 (upgrade safety)
        // Stored prefs from before priorityWeights existed must still decode, keeping
        // their labels/colors and defaulting the new field (not wiping everything).
        let legacy = #"{"labels":{"good":"Nice"},"colorsHex":{},"trendImprovingPercent":5,"trendDecliningPercent":-5,"trendLabels":{"improving":"Up","neutral":"N","declining":"Down","na":"NA"}}"#
        let c = try JSONDecoder().decode(PerformanceCustomization.self, from: Data(legacy.utf8))
        XCTAssertEqual(c.labels["good"], "Nice", "existing fields survive the upgrade")
        XCTAssertEqual(c.priorityWeights, .defaults, "missing field defaults, decode doesn't fail")
    }

    func testColorHexStorageAndInvalidFallback() { // spec: CLR-01
        let d = makeDefaults()
        let s = PerformanceCustomizationService(defaults: d)
        XCTAssertNil(s.hex(for: .good), "unset → nil (caller uses Palette default)")
        s.setHex("#123456FF", for: .good)
        XCTAssertEqual(s.hex(for: .good), "#123456FF")
        s.setHex("garbage", for: .good)
        XCTAssertNil(s.hex(for: .good), "invalid hex → nil fallback")
    }

    // MARK: - Trend (D12)

    func testTrendThresholdsAndLabelsPersist() { // spec: TRND-02
        let d = makeDefaults()
        let s = PerformanceCustomizationService(defaults: d)
        s.setTrendThresholds(improving: 10, declining: -8)
        s.setTrendLabels(TrendLabels(improving: "Up", neutral: "   ", declining: "Down", na: "—"))
        XCTAssertEqual(s.trendLabel(\.improving), "Up")
        XCTAssertEqual(s.trendLabel(\.neutral), "Neutral", "blank → default")

        let reloaded = PerformanceCustomizationService(defaults: d)
        XCTAssertEqual(reloaded.trendImprovingPercent, 10)
        XCTAssertEqual(reloaded.trendDecliningPercent, -8)
        XCTAssertEqual(reloaded.trendLabel(\.declining), "Down")
    }
}
