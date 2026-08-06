import XCTest

/// The first-run walkthrough (DESIGN D13/R1.1). Forced on with `-SHOW-ONBOARDING`
/// (UI tests otherwise skip it); the seeded fake store reports access granted, so
/// finishing lands on the Tasks tab.
final class OnboardingUITests: UITestCase {

    @MainActor
    func testWalkthroughConnectsAndDismisses() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-FAKE-REMINDERS", "-SHOW-ONBOARDING"]
        app.launch()

        // First card shows over the app.
        XCTAssertTrue(app.staticTexts["Your reminders, leveled up"].waitForExistence(timeout: 10),
                      "the walkthrough appears on first launch")

        app.buttons["onboardingNext"].tap()
        app.buttons["onboardingNext"].tap()
        let connect = app.buttons["onboardingGetStarted"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5), "the final card offers Connect Reminders")
        connect.tap()

        // Onboarding dismisses and the Tasks tab renders.
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 5),
                      "finishing the walkthrough reveals the app")
        XCTAssertFalse(app.staticTexts["Your reminders, leveled up"].exists)
    }

    @MainActor
    func testOnboardingSkippedByDefaultInTests() throws {
        // The plain companion launch (no -SHOW-ONBOARDING) goes straight to Tasks.
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Your reminders, leveled up"].exists,
                       "the walkthrough is skipped for deterministic UI tests")
    }
}
