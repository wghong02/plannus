import XCTest

/// Completion sheet flows (DESIGN.md §7.2 / D6) — completing with and without a
/// rating, cancelling, and the completion → analytics pipeline surfacing on the
/// Performance tab.
final class CompletionUITests: UITestCase {

    /// Adds an entry and taps its complete toggle, opening the completion sheet.
    @MainActor private func beginCompletion(_ app: XCUIApplication, title: String) {
        tab(app, "Tasks")
        tapAdd(app); fillTitleAndSave(app, title)
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        app.buttons["completeToggle"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "completing opens the sheet")
    }

    @MainActor
    func testCompleteWithRatingShowsBadge() throws { // spec: UITEST-11.1
        let app = launch()
        beginCompletion(app, title: "Rated task")
        // Rating is on by default (ratable entry) → Done records the default 50.
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5),
                      "a rated completion shows its rating on the row")
    }

    @MainActor
    func testCompleteWithoutRatingShowsNoBadge() throws { // spec: UITEST-11.2
        let app = launch()
        beginCompletion(app, title: "Unrated task")
        flip(app.switches["Rate this"]) // turn rating off
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Unrated task"].waitForExistence(timeout: 5), "the entry is completed")
        XCTAssertFalse(app.staticTexts["50"].exists, "skipping the rating records none")
    }

    @MainActor
    func testCancelCompletionLeavesEntryIncomplete() throws { // spec: UITEST-11.3
        let app = launch()
        beginCompletion(app, title: "Maybe task")
        app.buttons["Cancel"].tap()
        // Still incomplete: tapping the toggle reopens the completion sheet.
        app.buttons["completeToggle"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5),
                      "cancel left the entry incomplete (the toggle reopens the sheet)")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testRatedCompletionAppearsInPerformance() throws { // spec: UITEST-11.4
        let app = launch()
        beginCompletion(app, title: "FocusWork")
        app.buttons["Done"].tap() // completes + rates (50)

        tab(app, "Performance")
        XCTAssertTrue(app.staticTexts["FocusWork"].waitForExistence(timeout: 5),
                      "a rated completion flows into Recent Performance")
    }
}
