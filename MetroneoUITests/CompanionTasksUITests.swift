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
        // (Query the row's stable button id: a due-date-less row's title is the
        // button's own label, not a separate static text.)
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 5))
        app.staticTexts["Work"].tap()
        XCTAssertTrue(app.buttons["edit-Plan trip"].waitForExistence(timeout: 5),
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

    @MainActor
    func testBrowseCompletedTapShowsEditAndRate() throws { // spec: R6.5
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        app.buttons["browseCompletedLink"].tap()

        let row = app.buttons["browseCompleted-Call dentist"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // Combined detail: reminder fields (edit) on top, rating (rate) below.
        let title = app.textFields["reminderTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the edit UI (all reminder fields) is on top")
        XCTAssertTrue(app.textFields["ratingActualField"].exists, "the rate UI is below")
        XCTAssertEqual(title.value as? String, "Call dentist", "pre-filled with the reminder")

        title.tap(); title.typeText(" back")
        app.buttons["saveReminderButton"].tap()
        XCTAssertTrue(app.buttons["browseCompleted-Call dentist back"].waitForExistence(timeout: 5),
                      "editing fields from the combined detail persists")
    }

    @MainActor
    func testBrowseCompletedSwipeLeftEditsAndDeletes() throws { // spec: R6.5
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        app.buttons["browseCompletedLink"].tap()

        let row = app.buttons["browseCompleted-Call dentist"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // Swiping left reveals BOTH Edit and Delete. (Right-swipe has no row actions —
        // it's left to the system back-gesture — so it isn't asserted here.)
        row.swipeLeft()
        XCTAssertTrue(app.buttons["editCompleted-Call dentist"].waitForExistence(timeout: 5), "Edit is revealed")
        let del = app.buttons["deleteCompleted-Call dentist"]
        XCTAssertTrue(del.exists, "Delete is revealed")
        del.tap()

        XCTAssertFalse(app.buttons["browseCompleted-Call dentist"].waitForExistence(timeout: 5),
                       "deleting removes the completed reminder from the list")
    }

    @MainActor
    func testCompletedFilterByList() throws { // spec: R6.5 (pick by list)
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        // Complete a Work reminder so Completed spans two lists (seed has a Personal one).
        app.staticTexts["Work"].tap()
        let complete = app.buttons["complete-Review PR"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5)); complete.tap()

        app.buttons["browseCompletedLink"].tap()
        XCTAssertTrue(app.buttons["browseCompleted-Review PR"].waitForExistence(timeout: 5), "Work item shows")
        XCTAssertTrue(app.buttons["browseCompleted-Call dentist"].exists, "Personal item shows under the default All Lists")

        // Pick the Work list — only Work completions remain.
        app.buttons["completedListPicker"].tap()
        app.buttons["Work"].tap()
        XCTAssertTrue(app.buttons["browseCompleted-Review PR"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browseCompleted-Call dentist"].exists,
                       "the Personal completion is hidden when filtered to Work")
    }

    @MainActor
    func testCompleteCircleMovesReminderToNeedsRating() throws { // spec: R4.3/R6.1
        let app = launchCompanion()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 10))
        app.staticTexts["Work"].tap() // expand the list

        XCTAssertTrue(app.staticTexts["Review PR"].waitForExistence(timeout: 5))
        let complete = app.buttons["complete-Review PR"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5), "the leading complete circle is reachable")
        complete.tap()

        // Completing writes back to Reminders and the item lands in the inbox to rate.
        XCTAssertTrue(app.buttons["needsRating-Review PR"].waitForExistence(timeout: 5),
                      "tapping the complete circle moves the reminder into the Needs-rating inbox")
    }
}
