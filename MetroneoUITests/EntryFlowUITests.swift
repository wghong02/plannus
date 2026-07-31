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
}
