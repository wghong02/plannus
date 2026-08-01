import XCTest

/// Collection flows (DESIGN.md §7 / D5) — create a collection from the Tasks
/// By-collection mode.
final class CollectionUITests: UITestCase {

    @MainActor
    func testCreateCollection() throws { // spec: UITEST-4.1
        let app = launch()
        tab(app, "Tasks")
        app.buttons["Collections"].tap() // segmented control → By-collection mode
        tapAdd(app)

        let nameField = app.alerts.firstMatch.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "the New Collection alert should appear")
        nameField.typeText("Errands")
        app.alerts.firstMatch.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Errands"].waitForExistence(timeout: 5),
                      "the new collection displays")
    }

    /// Creates a collection with `name` from the Tasks By-collection mode.
    @MainActor private func createCollection(_ app: XCUIApplication, name: String) {
        tab(app, "Tasks")
        app.buttons["Collections"].tap()
        tapAdd(app)
        let nameField = app.alerts.firstMatch.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText(name)
        app.alerts.firstMatch.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddEntryToCollectionThenRemoveMember() throws { // spec: UITEST-4.2
        let app = launch()
        createCollection(app, name: "Errands")

        // Create "Milk" as an Errands member (toggle set before the title).
        app.buttons["All"].tap()
        openEditor(app)
        let errands = app.switches["Errands"]
        XCTAssertTrue(scrollDownTo(app, errands), "reach the Collections section")
        flip(errands)
        setTitle(app, "Milk")
        app.buttons["saveEntryButton"].tap()

        // Open the collection → the member is listed.
        app.buttons["Collections"].tap()
        app.staticTexts["Errands"].tap()
        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 5), "the member shows in the collection")

        // Swipe-remove drops it from the collection (no confirmation for member removal).
        app.cells.firstMatch.swipeLeft()
        let del = app.buttons["Delete"]
        XCTAssertTrue(del.waitForExistence(timeout: 5), "swipe reveals the remove action")
        del.tap()
        XCTAssertFalse(app.staticTexts["Milk"].waitForExistence(timeout: 3), "removing drops it from the collection")
    }

    @MainActor
    func testEmptyCollectionAndOrderingToggle() throws { // spec: UITEST-4.3
        let app = launch()
        createCollection(app, name: "Empty")

        app.staticTexts["Empty"].tap()
        XCTAssertTrue(app.staticTexts["No entries in this collection"].waitForExistence(timeout: 5),
                      "an empty collection shows the placeholder")

        // The ordering menu offers both modes.
        app.buttons["orderingMenu"].tap()
        let parallel = app.buttons["Parallel"]
        XCTAssertTrue(parallel.waitForExistence(timeout: 5), "ordering menu offers Parallel")
        parallel.tap()
        app.buttons["orderingMenu"].tap()
        let ordered = app.buttons["Ordered"]
        XCTAssertTrue(ordered.waitForExistence(timeout: 5), "ordering menu offers Ordered")
        ordered.tap()
    }
}
