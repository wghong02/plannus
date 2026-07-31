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
}
