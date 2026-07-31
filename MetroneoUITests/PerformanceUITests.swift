import XCTest

/// Performance tab flows (DESIGN.md §8 / D16) — stat cards, the seeded charts, and
/// the Custom-period start-date picker.
final class PerformanceUITests: UITestCase {

    @MainActor
    func testPerformanceScreenRenders() throws { // spec: UITEST-07
        let app = launch()
        tab(app, "Performance")
        XCTAssertTrue(app.navigationBars["Performance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rated"].waitForExistence(timeout: 5), "stat cards render")
        XCTAssertTrue(app.staticTexts["Average"].exists)
    }

    @MainActor
    func testPerformanceChartsRender() throws { // spec: UITEST-08
        let app = launchSeeded() // rated entries across recent weeks so the charts have data
        tab(app, "Performance")

        XCTAssertTrue(app.staticTexts["Trends"].waitForExistence(timeout: 5))
        // The distribution section + legend only appear when the charts have data.
        XCTAssertTrue(app.staticTexts["Rated Entries"].waitForExistence(timeout: 5),
                      "distribution chart renders with seeded data")
        XCTAssertTrue(app.staticTexts["Excellent"].exists, "legend uses custom level labels")
        XCTAssertTrue(app.staticTexts["Poor"].exists)
    }

    @MainActor
    func testPerformanceCustomPeriodRevealsStartPicker() throws { // spec: UITEST-09
        let app = launchSeeded()
        tab(app, "Performance")

        XCTAssertTrue(app.staticTexts["Trends"].waitForExistence(timeout: 5))
        // The custom start-date picker is hidden until the Custom period is chosen.
        let picker = app.descendants(matching: .any)["customStartPicker"]
        XCTAssertFalse(picker.exists, "start-date picker is hidden for non-custom periods")

        app.buttons["Custom"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "choosing Custom reveals the start-date picker")
    }
}
