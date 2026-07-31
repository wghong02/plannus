import XCTest

/// Entry create + complete flows (DESIGN.md §7 / D1.5 / D6) — create → display,
/// and complete → completion sheet → the entry remains.
final class EntryFlowUITests: UITestCase {

    @MainActor
    func testCreateEntryAppearsInTasks() throws { // spec: UITEST-3.1
        let app = launch()
        tab(app, "Tasks")
        tapAdd(app)
        fillTitleAndSave(app, "Buy milk")
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5),
                      "a created entry displays in the Tasks list")
    }

    @MainActor
    func testCompleteEntryFlow() throws { // spec: UITEST-3.2
        let app = launch()
        tab(app, "Tasks")
        tapAdd(app)
        fillTitleAndSave(app, "Workout")
        XCTAssertTrue(app.staticTexts["Workout"].waitForExistence(timeout: 5))

        app.buttons["completeToggle"].firstMatch.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "completing opens the completion sheet")
        done.tap()
        XCTAssertTrue(app.staticTexts["Workout"].waitForExistence(timeout: 5),
                      "the entry remains after completion")
    }

    @MainActor
    func testUncollectedEntryShowsUnderUngrouped() throws { // spec: UITEST-3.3
        let app = launch()
        tab(app, "Tasks")
        tapAdd(app)
        fillTitleAndSave(app, "Buy milk")
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5))

        // In By-collection mode, an entry that belongs to no collection lists under
        // the "Ungrouped" pseudo-group (D5.5).
        app.buttons["Collections"].tap()
        XCTAssertTrue(app.staticTexts["Ungrouped"].waitForExistence(timeout: 5),
                      "an entry in no collection appears under the Ungrouped section")
        XCTAssertTrue(app.staticTexts["Buy milk"].exists, "the ungrouped entry is listed there")
    }
}
