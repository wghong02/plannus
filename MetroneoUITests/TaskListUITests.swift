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

    @MainActor
    func testAlphabeticalSortOrdersRows() throws { // spec: UITEST-7.2
        let app = launch()
        tab(app, "Tasks")
        // Create out of alphabetical order; both are untimed.
        tapAdd(app); fillTitleAndSave(app, "Zebra")
        tapAdd(app); fillTitleAndSave(app, "Apple")
        XCTAssertTrue(app.staticTexts["Apple"].waitForExistence(timeout: 5))

        // Select the A–Z sort (note: en dash in the label).
        app.buttons["sortMenu"].tap()
        app.buttons["A\u{2013}Z"].tap()

        let apple = app.staticTexts["Apple"], zebra = app.staticTexts["Zebra"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5) && zebra.exists)
        XCTAssertLessThan(apple.frame.minY, zebra.frame.minY, "A–Z orders Apple above Zebra")
    }

    @MainActor
    func testCollectionFilterFacet() throws { // spec: UITEST-7.3
        let app = launch()
        tab(app, "Tasks")

        // A collection with one member ("Report") plus a non-member ("Personal").
        app.buttons["Collections"].tap()
        tapAdd(app)
        let nameField = app.alerts.firstMatch.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Work")
        app.alerts.firstMatch.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 5))

        app.buttons["All"].tap()
        openEditor(app)
        let workToggle = app.switches["Work"]
        XCTAssertTrue(scrollDownTo(app, workToggle), "reach the Collections section")
        flip(workToggle)
        setTitle(app, "Report")
        app.buttons["saveEntryButton"].tap()
        tapAdd(app); fillTitleAndSave(app, "Personal")
        XCTAssertTrue(app.staticTexts["Personal"].waitForExistence(timeout: 5))

        // Filter → Collection → Work: only the member shows.
        app.buttons["filterMenu"].tap()
        app.buttons["Collection"].tap()
        app.buttons["Work"].tap()
        XCTAssertTrue(app.staticTexts["Report"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Personal"].exists, "the collection filter shows only members")
    }
}
