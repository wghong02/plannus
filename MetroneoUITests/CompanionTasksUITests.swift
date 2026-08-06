import XCTest

/// The companion Tasks tab (DESIGN R2/R5/R6), driven by the seeded in-memory
/// fake reminder store: per-list expandable groups, the Needs-rating inbox, and
/// the rating sheet.
final class CompanionTasksUITests: UITestCase {

    @MainActor
    func testTasksRenderGroupsAndNeedsRating() throws { // spec: R2/R5
        let app = launchCompanion()

        // Per-list groups render; a completed-unrated reminder is in the inbox.
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10), "list groups render")
        XCTAssertTrue(app.staticTexts["Personal"].exists)
        XCTAssertTrue(app.buttons["needsRating-Call dentist"].exists, "a completed-unrated reminder needs rating")

        // Groups start collapsed; expanding shows the reminders.
        XCTAssertFalse(app.staticTexts["Ship release notes"].exists, "collapsed by default")
        app.staticTexts["Work"].tap()
        XCTAssertTrue(app.staticTexts["Ship release notes"].waitForExistence(timeout: 5), "expanding reveals the reminders")
        XCTAssertTrue(app.staticTexts["Review PR"].exists)
    }

    @MainActor
    func testRateFromNeedsRatingInbox() throws { // spec: R6.2
        let app = launchCompanion()

        let inbox = app.buttons["needsRating-Call dentist"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        inbox.tap()

        let save = app.buttons["saveRatingButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the rating sheet opens")
        save.tap()

        XCTAssertFalse(app.buttons["needsRating-Call dentist"].waitForExistence(timeout: 3),
                       "a rated reminder leaves the Needs-rating inbox")
    }

    @MainActor
    func testCreateReminderAppearsInDefaultList() throws { // spec: R4.1/R5
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))

        app.buttons["addReminderButton"].tap()
        let field = app.textFields["reminderTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the reminder editor presents")
        field.tap()
        field.typeText("Plan trip")
        app.buttons["saveReminderButton"].tap()

        // A new reminder lands in the default list ("Work"); expanding shows it.
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 5))
        app.staticTexts["Work"].tap()
        XCTAssertTrue(app.staticTexts["Plan trip"].waitForExistence(timeout: 5),
                      "the created reminder appears in its list")
    }

    @MainActor
    func testTapRowOpensPrefilledEditor() throws { // spec: R4.2
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        app.staticTexts["Work"].tap() // expand

        let row = app.staticTexts["Review PR"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // The editor opens pre-filled with the reminder's title.
        let field = app.textFields["reminderTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the editor opens for the tapped reminder")
        XCTAssertEqual(field.value as? String, "Review PR", "the editor is pre-filled")
    }

    // Note: completing a reminder → write-back → it moving into the Needs-rating
    // inbox is covered at the service level by TaskServiceTests
    // (`testCreateEditCompleteRateDelete`). A UI test of the complete toggle isn't
    // added here: the toggle lives inside a collapsible DisclosureGroup row, where
    // XCUITest's discovery of the nested button is unreliable — not worth a flaky test.
}
