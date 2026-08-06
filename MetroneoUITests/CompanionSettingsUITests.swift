import XCTest

/// The companion Settings tab (DESIGNV2 R5.3/R6.1a/R7.3): priority-weight editors,
/// the needs-rating window, and the Reminders list scope.
final class CompanionSettingsUITests: UITestCase {

    @MainActor
    func testSettingsRendersCompanionControls() throws { // spec: R5.3/R6.1a/R7.3
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        app.tabBars.firstMatch.buttons["Settings"].tap()

        XCTAssertTrue(app.steppers["weight-None"].waitForExistence(timeout: 5), "priority-weight editors render")
        XCTAssertTrue(app.steppers["weight-High"].exists)
        XCTAssertTrue(app.steppers["needsRatingWindowStepper"].exists, "the needs-rating window control renders")
        XCTAssertTrue(app.switches["listScope-Work"].exists, "list-scope toggles render")
        XCTAssertTrue(app.switches["listScope-Personal"].exists)
    }

    @MainActor
    func testListScopeNarrowsTasks() throws { // spec: R5.3
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["needsRating-Call dentist"].exists, "Personal's completed reminder starts in the inbox")

        app.tabBars.firstMatch.buttons["Settings"].tap()
        let personal = app.switches["listScope-Personal"]
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        flip(personal) // exclude the Personal list

        app.tabBars.firstMatch.buttons["Tasks"].tap()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 5), "Work stays in scope")
        XCTAssertFalse(app.staticTexts["Personal"].exists, "the excluded list disappears")
        XCTAssertFalse(app.buttons["needsRating-Call dentist"].exists,
                       "the excluded list's reminders leave the inbox")
    }
}
