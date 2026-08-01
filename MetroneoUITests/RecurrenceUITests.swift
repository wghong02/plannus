import XCTest

/// Recurring-series flows (DESIGN.md D15) — creating a series from the editor and
/// editing an occurrence under each scope. Frequency/interval math is unit-tested
/// (RecurrenceEngine); these drive the actual UI: the Repeats section, the
/// end-mode branch, and the This / All scope prompt.
final class RecurrenceUITests: UITestCase {

    /// Creates a repeating entry (default: weekly, 5 occurrences) titled `title`.
    /// Repeats is toggled before the title so the keyboard can't occlude it.
    @MainActor private func createRepeating(_ app: XCUIApplication, title: String) {
        openEditor(app)
        let repeats = app.switches["Repeats"]
        XCTAssertTrue(scrollDownTo(app, repeats), "reach the Recurrence section")
        flip(repeats)
        setTitle(app, title)
        app.buttons["saveEntryButton"].tap()
    }

    @MainActor
    func testCreateRepeatingEntryGeneratesOccurrences() throws { // spec: UITEST-9.1
        let app = launch()
        tab(app, "Tasks")
        createRepeating(app, title: "Standup")

        XCTAssertTrue(app.staticTexts["Standup"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rowCount(app, title: "Standup"), 5, "the default afterCount(5) generates five occurrences")
    }

    @MainActor
    func testEndAfterCountToggleRevealsUntilPicker() throws { // spec: UITEST-9.2
        let app = launch()
        tab(app, "Tasks")
        openEditor(app)
        let repeats = app.switches["Repeats"]
        XCTAssertTrue(scrollDownTo(app, repeats))
        flip(repeats)

        let endAfter = app.switches["End after count"]
        XCTAssertTrue(scrollDownTo(app, endAfter))
        XCTAssertFalse(app.descendants(matching: .any)["recurrenceUntilPicker"].exists,
                       "count mode shows no Until picker")
        flip(endAfter) // → until-date mode
        XCTAssertTrue(app.descendants(matching: .any)["recurrenceUntilPicker"].waitForExistence(timeout: 5),
                      "disabling 'End after count' reveals the Until date picker")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testEditOccurrenceAllInSeries() throws { // spec: UITEST-9.3
        let app = launch()
        tab(app, "Tasks")
        createRepeating(app, title: "Standup")
        XCTAssertEqual(rowCount(app, title: "Standup"), 5)

        app.staticTexts["Standup"].firstMatch.tap()
        let field = app.textFields["entryTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(field, with: "Renamed")
        app.buttons["saveEntryButton"].tap()

        let allInSeries = app.buttons["All in Series"]
        XCTAssertTrue(allInSeries.waitForExistence(timeout: 5), "editing an occurrence prompts for scope")
        allInSeries.tap()

        XCTAssertTrue(app.staticTexts["Renamed"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rowCount(app, title: "Renamed"), 5, "All-in-series applies to every occurrence")
        XCTAssertEqual(rowCount(app, title: "Standup"), 0, "no occurrence keeps the old title")
    }

    @MainActor
    func testEditOccurrenceThisOnlyDetachesOne() throws { // spec: UITEST-9.4
        let app = launch()
        tab(app, "Tasks")
        createRepeating(app, title: "Standup")
        XCTAssertEqual(rowCount(app, title: "Standup"), 5)

        app.staticTexts["Standup"].firstMatch.tap()
        let field = app.textFields["entryTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(field, with: "Detached")
        app.buttons["saveEntryButton"].tap()

        let thisEntry = app.buttons["This Entry"]
        XCTAssertTrue(thisEntry.waitForExistence(timeout: 5))
        thisEntry.tap()

        XCTAssertTrue(app.staticTexts["Detached"].waitForExistence(timeout: 5))
        XCTAssertEqual(rowCount(app, title: "Detached"), 1, "only the edited occurrence changes")
        XCTAssertEqual(rowCount(app, title: "Standup"), 4, "the other four are untouched")
    }
}
