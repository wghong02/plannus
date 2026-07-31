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
}
