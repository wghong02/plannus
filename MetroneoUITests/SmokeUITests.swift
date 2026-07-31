import XCTest

/// Launch/navigation smoke check (DESIGN.md §1) — the four tabs render and
/// navigate. Onboarding lives in ``OnboardingUITests``.
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
}
