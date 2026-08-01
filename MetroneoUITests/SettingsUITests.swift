import XCTest

/// Settings flows (DESIGN.md §9 / D8/D10/D12/D13) — the Performance customization
/// screen (labels, cutoff validation) and the tutorial replay. The customization
/// tests tap **Reset to Defaults** so they leave persisted prefs untouched.
final class SettingsUITests: UITestCase {

    @MainActor private func openCustomization(_ app: XCUIApplication) {
        tab(app, "Settings")
        app.buttons["performanceSettingsLink"].tap()
        XCTAssertTrue(app.buttons["Reset to Defaults"].waitForExistence(timeout: 5),
                      "the Performance customization screen renders")
    }

    @MainActor
    func testRenameLevelLabelThenReset() throws { // spec: UITEST-10.1
        let app = launch()
        openCustomization(app)

        // Clean slate.
        let reset = app.buttons["Reset to Defaults"]
        XCTAssertTrue(scrollDownTo(app, reset)); reset.tap()

        let excellent = app.textFields["label-excellent"]
        XCTAssertTrue(scrollUpTo(app, excellent), "reach the Labels section")
        XCTAssertEqual(excellent.value as? String, "Excellent", "the default label shows as the placeholder")

        replaceText(excellent, with: "Crushed")
        XCTAssertEqual(excellent.value as? String, "Crushed", "the rename takes")

        // Reset restores the default (and cleans up so nothing persists).
        XCTAssertTrue(scrollDownTo(app, reset)); reset.tap()
        XCTAssertTrue(scrollUpTo(app, app.textFields["label-excellent"]))
        XCTAssertEqual(app.textFields["label-excellent"].value as? String, "Excellent",
                       "Reset to Defaults restores the built-in label")
    }

    @MainActor
    func testInvalidCutoffsShowAlert() throws { // spec: UITEST-10.2
        let app = launch()
        openCustomization(app)

        let fair = app.textFields["cutoff-Fair"]
        XCTAssertTrue(scrollUpTo(app, fair), "reach the Cutoffs section")
        replaceText(fair, with: "95") // Fair > Good(75) violates the non-decreasing rule
        app.staticTexts["Cutoffs"].tap() // dismiss the number pad

        let save = app.buttons["Save Cutoffs"]
        XCTAssertTrue(scrollDownTo(app, save)); save.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5),
                      "a decreasing cutoff is rejected with an alert")
        app.alerts.firstMatch.buttons["OK"].tap()

        // The rejected save didn't persist; reset anyway to be safe.
        let reset = app.buttons["Reset to Defaults"]
        XCTAssertTrue(scrollDownTo(app, reset)); reset.tap()
    }

    @MainActor
    func testShowTutorialAgainReopensOnboarding() throws { // spec: UITEST-10.3
        let app = launch()
        tab(app, "Settings")
        app.buttons["Show Tutorial Again"].tap()

        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "replaying re-presents the onboarding walkthrough")
        skip.tap() // dismiss so the flag returns to seen
    }
}
