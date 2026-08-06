import XCTest

/// Shared base for the companion UI suites (DESIGN). Flows launch the app backed
/// by the seeded in-memory fake reminder store (`-FAKE-REMINDERS`), so they run
/// without EventKit or its permission prompt. Controls carry stable
/// `accessibilityIdentifier`s.
class UITestCase: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// Launches the app on the seeded in-memory fake store.
    @MainActor
    func launchCompanion() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-FAKE-REMINDERS"]
        app.launch()
        return app
    }

    /// Flips a SwiftUI `Toggle`. A plain `.tap()` lands on the switch element's
    /// center — often the label, which doesn't flip it — so tap the trailing
    /// control where the switch actually sits.
    func flip(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "toggle exists")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
}
