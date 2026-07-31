import XCTest

/// First-run onboarding flows (DESIGN.md D13) — both dismissal routes: **Skip**,
/// and paging **Next** through the pages to **Get Started**.
final class OnboardingUITests: UITestCase {

    @MainActor
    func testOnboardingSkipDismisses() throws { // spec: UITEST-2.1
        let app = launch(resetStore: false, skipOnboarding: false)
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "onboarding should appear on first run")
        skip.tap()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Calendar"].waitForExistence(timeout: 10),
                      "Skip dismisses onboarding to the tabs")
    }

    @MainActor
    func testOnboardingNextThroughPagesDismisses() throws { // spec: UITEST-2.2
        let app = launch(resetStore: false, skipOnboarding: false)
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "onboarding should appear on first run")

        // Page forward: "Next" advances each of the first three pages; the last
        // page swaps the button to "Get Started".
        for page in 1...3 {
            XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5), "page \(page) still shows Next")
            app.buttons["Next"].tap()
        }

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "the final page shows Get Started")
        getStarted.tap()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Calendar"].waitForExistence(timeout: 10),
                      "paging to Get Started dismisses onboarding to the tabs")
    }
}
