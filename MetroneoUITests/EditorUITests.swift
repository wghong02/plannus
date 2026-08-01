import XCTest

/// Entry editor field flows (DESIGN.md §6.1/§7.1 / D6) — the editor's optional
/// sections under different configurations: schedule/all-day, deadline, tracking
/// aspects, and tags. Toggles are set *before* the title so the keyboard never
/// occludes them; date *values* stay at their defaults (the pickers aren't driven
/// here — that math is unit-tested).
final class EditorUITests: UITestCase {

    @MainActor
    func testScheduledAllDayEntryShowsAllDaySubtitle() throws { // spec: UITEST-8.1
        let app = launch()
        tab(app, "Tasks")
        openEditor(app)

        flip(app.switches["Scheduled (time block)"])
        let allDay = app.switches["All Day"]
        XCTAssertTrue(allDay.waitForExistence(timeout: 5), "enabling schedule reveals the All Day toggle")
        flip(allDay)
        setTitle(app, "Meeting")
        app.buttons["saveEntryButton"].tap()

        XCTAssertTrue(app.staticTexts["Meeting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["All day"].exists, "a scheduled all-day entry shows the All day subtitle")
    }

    @MainActor
    func testDeadlineEntryShowsDueSubtitle() throws { // spec: UITEST-8.2
        let app = launch()
        tab(app, "Tasks")
        openEditor(app)

        flip(app.switches["Deadline (due by)"])
        setTitle(app, "Report")
        app.buttons["saveEntryButton"].tap()

        XCTAssertTrue(app.staticTexts["Report"].waitForExistence(timeout: 5))
        let due = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Due")).firstMatch
        XCTAssertTrue(due.waitForExistence(timeout: 5), "a deadline entry shows a 'Due …' subtitle")
    }

    @MainActor
    func testNonCompletableEntryHasNoCompleteToggle() throws { // spec: UITEST-8.3
        let app = launch()
        tab(app, "Tasks")
        openEditor(app)

        let completable = app.switches["Completable"]
        XCTAssertTrue(scrollDownTo(app, completable), "reach the Tracking section")
        flip(completable) // default on → turn off
        setTitle(app, "Reference note")
        app.buttons["saveEntryButton"].tap()

        XCTAssertTrue(app.staticTexts["Reference note"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "completeToggle").count, 0,
                       "a non-completable entry shows no complete toggle")
    }

    @MainActor
    func testAddAndRemoveTagChip() throws { // spec: UITEST-8.4
        let app = launch()
        tab(app, "Tasks")
        openEditor(app)

        let tagField = app.textFields["Add tag"]
        XCTAssertTrue(scrollDownTo(app, tagField), "reach the Tags section")
        tagField.tap(); tagField.typeText("work")
        app.buttons["addTagButton"].tap()
        XCTAssertTrue(app.staticTexts["work"].waitForExistence(timeout: 5), "the tag chip appears")

        app.buttons["removeTag-work"].tap()
        XCTAssertFalse(app.staticTexts["work"].exists, "removing the chip drops the tag")
    }
}
