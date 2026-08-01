import XCTest

/// Calendar placement flow (DESIGN.md §6 / D6.5) — a calendar-added entry lands on
/// the selected day (dated by default).
final class CalendarUITests: UITestCase {

    @MainActor
    func testCalendarAddShowsEntryOnDay() throws { // spec: UITEST-5.1
        let app = launch()
        // Calendar is the default tab; Add defaults a deadline on the selected (today) day.
        tapAdd(app)
        fillTitleAndSave(app, "Dentist")
        XCTAssertTrue(app.staticTexts["Dentist"].waitForExistence(timeout: 5),
                      "a calendar-added entry lands on the selected day")
    }

    @MainActor
    func testEmptyDayShowsPlaceholder() throws { // spec: UITEST-5.2
        let app = launch() // clean store, Calendar is the default tab
        XCTAssertTrue(app.staticTexts["No entries for this day"].waitForExistence(timeout: 5),
                      "a day with no entries shows the placeholder")
    }

    @MainActor
    func testCompleteFromCalendarKeepsEntry() throws { // spec: UITEST-5.3
        let app = launch()
        tapAdd(app); fillTitleAndSave(app, "Checkup")
        XCTAssertTrue(app.staticTexts["Checkup"].waitForExistence(timeout: 5))

        app.buttons["completeToggle"].firstMatch.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "completing opens the sheet from the calendar too")
        done.tap()
        XCTAssertTrue(app.staticTexts["Checkup"].waitForExistence(timeout: 5),
                      "a completed calendar entry stays on its day")
    }

    @MainActor
    func testDeleteFromCalendarWithConfirmation() throws { // spec: UITEST-5.4
        let app = launch()
        tapAdd(app); fillTitleAndSave(app, "Appt")
        XCTAssertTrue(app.staticTexts["Appt"].waitForExistence(timeout: 5))

        app.cells.firstMatch.swipeLeft()
        let swipeDelete = app.buttons["Delete"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5), "swipe reveals Delete")
        swipeDelete.tap()
        let dialog = app.sheets.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "delete asks for confirmation")
        dialog.buttons["Delete"].tap()

        XCTAssertFalse(app.staticTexts["Appt"].waitForExistence(timeout: 3), "the entry is removed from the day")
    }
}
