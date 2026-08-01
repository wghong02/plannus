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

    @MainActor
    func testEditExistingEntryTitle() throws { // spec: UITEST-3.4
        let app = launch()
        tab(app, "Tasks")
        tapAdd(app); fillTitleAndSave(app, "Milk")
        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 5))

        // Tap the row → editor → rename → save (non-series ⇒ no scope prompt).
        app.staticTexts["Milk"].tap()
        let field = app.textFields["entryTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "tapping a row opens the editor")
        replaceText(field, with: "Bread")
        app.buttons["saveEntryButton"].tap()

        XCTAssertTrue(app.staticTexts["Bread"].waitForExistence(timeout: 5), "the edit is saved")
        XCTAssertFalse(app.staticTexts["Milk"].exists, "the old title is gone")
    }

    @MainActor
    func testDeleteEntryWithConfirmation() throws { // spec: UITEST-3.5
        let app = launch()
        tab(app, "Tasks")
        tapAdd(app); fillTitleAndSave(app, "Solo")
        XCTAssertTrue(app.staticTexts["Solo"].waitForExistence(timeout: 5))

        app.cells.firstMatch.swipeLeft()
        let swipeDelete = app.buttons["Delete"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5), "swipe reveals Delete")
        swipeDelete.tap()

        // A confirmation action sheet gates the delete; scope the confirm to it so
        // it doesn't collide with the swipe action's own Delete.
        let dialog = app.sheets.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "delete asks for confirmation")
        dialog.buttons["Delete"].tap()

        XCTAssertFalse(app.staticTexts["Solo"].waitForExistence(timeout: 3), "the entry is gone after confirming")
    }

    @MainActor
    func testCompleteThenUncomplete() throws { // spec: UITEST-3.6
        let app = launch()
        tab(app, "Tasks")
        tapAdd(app); fillTitleAndSave(app, "Gym")
        XCTAssertTrue(app.staticTexts["Gym"].waitForExistence(timeout: 5))

        // Complete via the sheet.
        app.buttons["completeToggle"].firstMatch.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        // Filter to Completed: the entry shows there (and stays completable).
        app.buttons["filterMenu"].tap(); app.buttons["Completed"].tap()
        XCTAssertTrue(app.staticTexts["Gym"].waitForExistence(timeout: 5), "Completed shows the finished entry")

        // Uncomplete it (a completed toggle uncompletes directly, no sheet) → it
        // leaves the Completed-filtered list.
        app.buttons["completeToggle"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["Gym"].waitForExistence(timeout: 3),
                       "uncompleting drops it from the Completed filter")
    }
}
