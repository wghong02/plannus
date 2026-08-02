import XCTest

/// Settings flows (DESIGN.md §9 / D8/D10/D12/D13) — the Performance customization
/// screen (labels, cutoff validation) and the tutorial replay. The customization
/// tests tap **Reset to Defaults** so they leave persisted prefs untouched.
final class SettingsUITests: UITestCase {

    @MainActor private func openCustomization(_ app: XCUIApplication) {
        tab(app, "Settings")
        let link = app.buttons["performanceSettingsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "the customization link is present")
        link.tap()
        // Assert on the pushed screen's nav bar (top, always rendered) — the Reset
        // button lives at the bottom of a lazy form and may not exist yet.
        XCTAssertTrue(app.navigationBars["Performance"].waitForExistence(timeout: 5),
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

    // Note: "Show Tutorial Again" (the replay wiring) is covered without the UI —
    // OnboardingAndCustomizationTests exercises OnboardingGate replay/shouldShow, and
    // OnboardingUITests (2.1/2.2) covers the walkthrough display. A UI test of the
    // Settings button is omitted: the @AppStorage flag interacts with the launch
    // argument domain in a way that makes the first-run re-arm non-deterministic
    // under XCUITest.
}
