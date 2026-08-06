import XCTest

/// The companion Performance tab (DESIGNV2 R2/R7), driven by the seeded in-memory
/// fake store. Charts render off the rated `TaskItem` population; rating a reminder
/// in the Tasks tab feeds this tab through the sidecar.
final class CompanionPerformanceUITests: UITestCase {

    @MainActor
    func testPerformanceTabRendersEmptyState() throws { // spec: R2
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))

        app.tabBars.firstMatch.buttons["Performance"].tap()

        // Wiring check: the stat cards + trend section render; nothing is rated yet.
        XCTAssertTrue(app.staticTexts["Rated"].waitForExistence(timeout: 5), "the Performance tab renders")
        XCTAssertTrue(app.staticTexts["Trends"].exists)
        XCTAssertTrue(app.staticTexts["No rated reminders in this period"].exists)
    }

    @MainActor
    func testRatingFeedsPerformance() throws { // spec: R2.3/R6.2
        let app = launchCompanion()

        // Rate the completed-unrated reminder from the inbox.
        let inbox = app.buttons["needsRating-Call dentist"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        inbox.tap()
        let save = app.buttons["saveRatingButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // It now shows up as rated in the Performance tab's Recent list.
        app.tabBars.firstMatch.buttons["Performance"].tap()
        XCTAssertTrue(app.staticTexts["Recent Performance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Call dentist"].waitForExistence(timeout: 5),
                      "a rated reminder appears in Recent Performance")
    }
}
