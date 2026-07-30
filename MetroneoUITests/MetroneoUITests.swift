import XCTest

/// Smoke UI tests for the v2 app: the four tabs render and navigate, and the
/// first-run onboarding dismisses (the one behavior that can't be unit-tested —
/// see TUT rows in DESIGN.md).
final class MetroneoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testTabsRenderAndNavigate() throws {
        let app = XCUIApplication()
        // Skip onboarding for this test (argument domain overrides the stored flag).
        app.launchArguments += ["-@onboarding_seen", "YES"]
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.buttons["Calendar"].waitForExistence(timeout: 10))
        XCTAssertTrue(tabs.buttons["Tasks"].exists)
        XCTAssertTrue(tabs.buttons["Performance"].exists)
        XCTAssertTrue(tabs.buttons["Settings"].exists)

        tabs.buttons["Tasks"].tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))

        tabs.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingSkipDismisses() throws {
        let app = XCUIApplication()
        // Force the walkthrough regardless of any stored flag.
        app.launchArguments += ["-@onboarding_seen", "NO"]
        app.launch()

        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "onboarding should appear on first run")
        skip.tap()

        XCTAssertTrue(app.tabBars.firstMatch.buttons["Calendar"].waitForExistence(timeout: 10),
                      "Skip dismisses onboarding to the tabs")
    }
}
