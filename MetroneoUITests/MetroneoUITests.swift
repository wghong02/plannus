import XCTest

/// End-to-end UI flows for the v2 app. These exercise real wiring that unit tests
/// can't reach — create → display, complete, collections, calendar placement —
/// plus the tab/onboarding smoke checks. Each flow launches with a clean store
/// (`-UITEST-RESET`) and skips onboarding unless it's the subject.
final class MetroneoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    // MARK: - Helpers

    @MainActor
    private func launch(resetStore: Bool = true, skipOnboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if resetStore { app.launchArguments += ["-UITEST-RESET"] }
        app.launchArguments += ["-@onboarding_seen", skipOnboarding ? "YES" : "NO"]
        app.launch()
        return app
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        app.tabBars.firstMatch.buttons[name].tap()
    }

    private func tapAdd(_ app: XCUIApplication) {
        let add = app.buttons["addButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "add button present")
        add.tap()
    }

    /// Fills the editor's title and saves (assumes the editor sheet is showing).
    private func fillTitleAndSave(_ app: XCUIApplication, _ title: String) {
        let field = app.textFields["entryTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "editor should present")
        field.tap()
        field.typeText(title)
        app.buttons["saveEntryButton"].tap()
    }

    // MARK: - Smoke

    @MainActor
    func testTabsRenderAndNavigate() throws {
        let app = launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.buttons["Calendar"].waitForExistence(timeout: 10))
        XCTAssertTrue(tabs.buttons["Tasks"].exists)
        XCTAssertTrue(tabs.buttons["Performance"].exists)
        XCTAssertTrue(tabs.buttons["Settings"].exists)

        tab(app, "Tasks");       XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
        tab(app, "Settings");    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingSkipDismisses() throws {
        let app = launch(resetStore: false, skipOnboarding: false)
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "onboarding should appear on first run")
        skip.tap()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Calendar"].waitForExistence(timeout: 10),
                      "Skip dismisses onboarding to the tabs")
    }

    // MARK: - Flows

    @MainActor
    func testCreateEntryAppearsInTasks() throws {
        let app = launch()
        tab(app, "Tasks")
        tapAdd(app)
        fillTitleAndSave(app, "Buy milk")
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5),
                      "a created entry displays in the Tasks list")
    }

    @MainActor
    func testCompleteEntryFlow() throws {
        let app = launch()
        tab(app, "Tasks")
        tapAdd(app)
        fillTitleAndSave(app, "Workout")
        XCTAssertTrue(app.staticTexts["Workout"].waitForExistence(timeout: 5))

        app.buttons["completeToggle"].firstMatch.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "completing opens the completion sheet")
        done.tap()
        XCTAssertTrue(app.staticTexts["Workout"].waitForExistence(timeout: 5),
                      "the entry remains after completion")
    }

    @MainActor
    func testCreateCollection() throws {
        let app = launch()
        tab(app, "Tasks")
        app.buttons["Collections"].tap() // segmented control → By-collection mode
        tapAdd(app)

        let nameField = app.alerts.firstMatch.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "the New Collection alert should appear")
        nameField.typeText("Errands")
        app.alerts.firstMatch.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Errands"].waitForExistence(timeout: 5),
                      "the new collection displays")
    }

    @MainActor
    func testCalendarAddShowsEntryOnDay() throws {
        let app = launch()
        // Calendar is the default tab; Add defaults a deadline on the selected (today) day.
        tapAdd(app)
        fillTitleAndSave(app, "Dentist")
        XCTAssertTrue(app.staticTexts["Dentist"].waitForExistence(timeout: 5),
                      "a calendar-added entry lands on the selected day")
    }

    @MainActor
    func testPerformanceScreenRenders() throws {
        let app = launch()
        tab(app, "Performance")
        XCTAssertTrue(app.navigationBars["Performance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rated"].waitForExistence(timeout: 5), "stat cards render")
        XCTAssertTrue(app.staticTexts["Average"].exists)
    }

    @MainActor
    func testPerformanceChartsRender() throws {
        let app = XCUIApplication()
        // Seed rated entries across recent weeks so the charts have data (D16).
        app.launchArguments += ["-SEED-PERF", "-@onboarding_seen", "YES"]
        app.launch()
        tab(app, "Performance")

        XCTAssertTrue(app.staticTexts["Trends"].waitForExistence(timeout: 5))
        // The distribution section + legend only appear when the charts have data.
        XCTAssertTrue(app.staticTexts["Rated Entries"].waitForExistence(timeout: 5),
                      "distribution chart renders with seeded data")
        XCTAssertTrue(app.staticTexts["Excellent"].exists, "legend uses custom level labels")
        XCTAssertTrue(app.staticTexts["Poor"].exists)
    }
}
