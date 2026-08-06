import XCTest

/// The companion Settings tab (DESIGN R5.3/R6.1a/R7.3): priority-weight editors,
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
    func testListScopeTogglesEachListOffAndBackOn() throws { // spec: R5.3 (toggle must not revert)
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        app.tabBars.firstMatch.buttons["Settings"].tap()

        let personal = app.switches["listScope-Personal"]
        let work = app.switches["listScope-Work"]
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        XCTAssertEqual(personal.value as? String, "1", "all lists start in scope")
        XCTAssertEqual(work.value as? String, "1")

        // Turn BOTH lists off. The second one is the last enabled list — the case the
        // old code snapped back to "all". Each must go, and stay, off.
        flip(personal)
        XCTAssertTrue(waitForValue(personal, "0"), "a list toggle can be turned off")
        flip(work)
        XCTAssertTrue(waitForValue(work, "0"), "the LAST list can be turned off too (no revert)")
        XCTAssertEqual(personal.value as? String, "0", "and the first stays off")

        // Persist across a tab round-trip.
        app.tabBars.firstMatch.buttons["Tasks"].tap()
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertTrue(waitForValue(work, "0"), "the off state persists")
        XCTAssertEqual(personal.value as? String, "0")

        // Turn them back on.
        flip(work)
        XCTAssertTrue(waitForValue(work, "1"), "a list can be turned back on")
        flip(personal)
        XCTAssertTrue(waitForValue(personal, "1"), "and back to all-on")
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
