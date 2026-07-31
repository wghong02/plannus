import XCTest

/// Shared base for the end-to-end UI suites (DESIGN.md §UI flows). Concrete suites
/// — Smoke / EntryFlow / Collection / Calendar / Performance — subclass this so the
/// flows stay small and grouped by concern while reusing one set of launch +
/// navigation helpers. Flows launch with a clean store (`-UITEST-RESET`) and skip
/// onboarding unless it's the subject; controls carry stable
/// `accessibilityIdentifier`s (`addButton`, `entryTitleField`, `saveEntryButton`,
/// `completeToggle`).
class UITestCase: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    // MARK: - Launch

    @MainActor
    func launch(resetStore: Bool = true, skipOnboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if resetStore { app.launchArguments += ["-UITEST-RESET"] }
        app.launchArguments += ["-@onboarding_seen", skipOnboarding ? "YES" : "NO"]
        app.launch()
        return app
    }

    /// Launches with the Performance seed (`-SEED-PERF`) so the charts have data (D16).
    @MainActor
    func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-SEED-PERF", "-@onboarding_seen", "YES"]
        app.launch()
        return app
    }

    // MARK: - Navigation

    func tab(_ app: XCUIApplication, _ name: String) {
        app.tabBars.firstMatch.buttons[name].tap()
    }

    func tapAdd(_ app: XCUIApplication) {
        let add = app.buttons["addButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "add button present")
        add.tap()
    }

    /// Fills the editor's title and saves (assumes the editor sheet is showing).
    func fillTitleAndSave(_ app: XCUIApplication, _ title: String) {
        let field = app.textFields["entryTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "editor should present")
        field.tap()
        field.typeText(title)
        app.buttons["saveEntryButton"].tap()
    }
}
