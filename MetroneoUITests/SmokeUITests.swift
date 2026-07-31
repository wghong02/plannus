import XCTest

/// Launch/navigation smoke checks (DESIGN.md §1 / D13) — the tabs render and the
/// first-run onboarding appears and dismisses.
final class SmokeUITests: UITestCase {

    @MainActor
    func testTabsRenderAndNavigate() throws { // spec: UITEST-01
        let app = launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.buttons["Calendar"].waitForExistence(timeout: 10))
        XCTAssertTrue(tabs.buttons["Tasks"].exists)
        XCTAssertTrue(tabs.buttons["Performance"].exists)
        XCTAssertTrue(tabs.buttons["Settings"].exists)

        tab(app, "Tasks");    XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
        tab(app, "Settings"); XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingSkipDismisses() throws { // spec: UITEST-02
        let app = launch(resetStore: false, skipOnboarding: false)
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "onboarding should appear on first run")
        skip.tap()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Calendar"].waitForExistence(timeout: 10),
                      "Skip dismisses onboarding to the tabs")
    }
}
