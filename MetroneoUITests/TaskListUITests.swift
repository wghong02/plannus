import XCTest

/// Tasks-list filtering (DESIGN.md §7 / D7) — the leading filter narrows the
/// visible entries by completion state.
final class TaskListUITests: UITestCase {

    @MainActor
    func testCompletionFilterNarrowsList() throws { // spec: UITEST-7.1
        let app = launch()
        tab(app, "Tasks")

        // Two untimed entries; complete one so the completion facet can split them.
        tapAdd(app); fillTitleAndSave(app, "Alpha task")
        tapAdd(app); fillTitleAndSave(app, "Beta task")
        XCTAssertTrue(app.staticTexts["Beta task"].waitForExistence(timeout: 5))

        // Complete "Alpha task" — first row (untimed entries sort by title A→Z).
        app.buttons["completeToggle"].firstMatch.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "completing opens the completion sheet")
        done.tap()
        XCTAssertTrue(app.staticTexts["Alpha task"].waitForExistence(timeout: 5))

        // Filter → Upcoming hides the completed entry.
        app.buttons["filterMenu"].tap()
        app.buttons["Upcoming"].tap()
        XCTAssertTrue(app.staticTexts["Beta task"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Alpha task"].exists, "Upcoming hides completed entries")

        // Filter → Completed inverts it.
        app.buttons["filterMenu"].tap()
        app.buttons["Completed"].tap()
        XCTAssertTrue(app.staticTexts["Alpha task"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Beta task"].exists, "Completed hides upcoming entries")
    }
}
