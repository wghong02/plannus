import XCTest

/// Performance tab flows (DESIGN.md §8 / D16) — stat cards, the seeded charts, and
/// the Custom-period start-date picker.
final class PerformanceUITests: UITestCase {

    @MainActor
    func testPerformanceScreenRenders() throws { // spec: UITEST-6.1
        let app = launch()
        tab(app, "Performance")
        XCTAssertTrue(app.navigationBars["Performance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rated"].waitForExistence(timeout: 5), "stat cards render")
        XCTAssertTrue(app.staticTexts["Average"].exists)
    }

    @MainActor
    func testPerformanceChartsRender() throws { // spec: UITEST-6.2
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
    func testPerformanceCustomPeriodRevealsStartPicker() throws { // spec: UITEST-6.3
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

    @MainActor
    func testEmptyStateWhenNothingRated() throws { // spec: UITEST-6.4
        let app = launch() // clean store, no rated entries
        tab(app, "Performance")
        XCTAssertTrue(app.staticTexts["No rated entries in this period"].waitForExistence(timeout: 5),
                      "the trend card shows the empty state with no data")
        XCTAssertFalse(app.staticTexts["Rated Entries"].exists, "no distribution section without data")
    }

    @MainActor
    func testSwitchingPeriodKeepsChartsRendered() throws { // spec: UITEST-6.5
        let app = launchSeeded()
        tab(app, "Performance")
        XCTAssertTrue(app.staticTexts["Trends"].waitForExistence(timeout: 5))

        // The seed spans the last ~30 days, so Week and All Time both have data.
        app.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Rated Entries"].waitForExistence(timeout: 5),
                      "Week still renders the distribution")
        app.buttons["All Time"].tap()
        XCTAssertTrue(app.staticTexts["Rated Entries"].waitForExistence(timeout: 5),
                      "All Time still renders the distribution")
    }
}
