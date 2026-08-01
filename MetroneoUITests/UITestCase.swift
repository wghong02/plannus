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

    /// Opens the add-entry editor. The editor does **not** auto-focus the title, so
    /// no keyboard is up — configure the toggle/section controls first (they stay
    /// hittable), then call `setTitle` last to name it before saving.
    func openEditor(_ app: XCUIApplication) {
        tapAdd(app)
        XCTAssertTrue(app.textFields["entryTitleField"].waitForExistence(timeout: 5), "editor should present")
    }

    /// Types into the editor's title field. Call after configuring sections and
    /// right before saving, so the keyboard it raises can't occlude other controls.
    func setTitle(_ app: XCUIApplication, _ title: String) {
        let field = app.textFields["entryTitleField"]
        scrollUpTo(app, field)
        field.tap()
        field.typeText(title)
    }

    /// Replaces a text field's current single-token value (double-tap selects it,
    /// then the typed text overwrites the selection). Reliable for one-word titles
    /// and numeric fields.
    func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        field.doubleTap()
        field.typeText(text)
    }

    /// Number of list rows whose visible title equals `title`.
    func rowCount(_ app: XCUIApplication, title: String) -> Int {
        app.staticTexts.matching(NSPredicate(format: "label == %@", title)).count
    }

    /// Flips a SwiftUI `Toggle`. A plain `.tap()` lands on the switch element's
    /// center — often the label, which doesn't flip it — so tap the trailing
    /// control where the switch actually sits.
    func flip(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "toggle exists")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// Scrolls a Form/List down until `element` is on-screen and hittable (rows in
    /// a long editor render lazily, so a deep control may not exist until scrolled).
    @discardableResult
    func scrollDownTo(_ app: XCUIApplication, _ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// Scrolls back up until `element` is on-screen and hittable.
    @discardableResult
    func scrollUpTo(_ app: XCUIApplication, _ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            app.swipeDown()
            swipes += 1
        }
        return element.exists && element.isHittable
    }
}
