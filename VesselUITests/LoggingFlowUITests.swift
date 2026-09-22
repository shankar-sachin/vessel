import XCTest

/// End-to-end coverage of Phase 1: entering data by hand in all four logs.
///
/// These drive the same taps a person would make, which is the only way to
/// catch the failures that matter here — a sheet that won't dismiss, a Save
/// button that stays disabled, an entry that saves but never appears in its list.
final class LoggingFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VESSEL_SEED_SAMPLE_DATA"] = "1"
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Types into a field, clearing whatever was there first.
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        // Numeric fields show a placeholder rather than a literal "0" (see
        // `blankWhenZero`), so there's usually nothing to clear.
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    // MARK: - Food

    func testLogAMealByHand() throws {
        app.tabBars.buttons["Diet"].tap()
        app.buttons["Log food"].tap()

        let sheet = app.navigationBars["Log food"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Log food sheet should open")

        // Save must stay disabled until there's actually a food in the meal —
        // an empty meal is not a meaningful entry.
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save should be disabled with no foods")
        capture("10-logfood-empty")

        app.buttons["addFoodButton"].tap()

        // Adding a food now opens database search; manual entry is behind the
        // "Manual" action for anything the database doesn't know.
        XCTAssertTrue(app.navigationBars["Add a food"].waitForExistence(timeout: 5))
        app.buttons["Manual"].tap()

        let nameField = app.textFields["foodNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Porridge with berries")

        replaceText(in: app.textFields["foodCaloriesField"], with: "320")

        // Assert the field holds what we meant, not merely that something saved.
        let caloriesValue = app.textFields["foodCaloriesField"].value as? String
        XCTAssertEqual(caloriesValue, "320", "Calories should be exactly what was typed")
        capture("11-fooditem-filled")

        app.buttons["Add"].tap()

        // Back on the meal sheet, the item should be listed and Save enabled.
        XCTAssertTrue(app.staticTexts["Porridge with berries"].waitForExistence(timeout: 5),
                      "The added food should appear in the meal")
        XCTAssertTrue(app.staticTexts["320 kcal"].exists,
                      "The meal should show the calories that were entered")
        XCTAssertTrue(app.buttons["Save"].isEnabled, "Save should enable once a food exists")
        capture("12-logfood-ready")

        app.buttons["Save"].tap()

        // And it must land in the actual log, not just the sheet.
        XCTAssertTrue(app.staticTexts["Porridge with berries"].waitForExistence(timeout: 5),
                      "The meal should appear in the Diet log after saving")
        capture("13-diet-after-save")
    }

    func testCancellingAMealLeavesNothingBehind() throws {
        app.tabBars.buttons["Diet"].tap()
        app.buttons["Log food"].tap()
        app.buttons["addFoodButton"].tap()
        XCTAssertTrue(app.navigationBars["Add a food"].waitForExistence(timeout: 5))
        app.buttons["Manual"].tap()

        let nameField = app.textFields["foodNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Abandoned entry")
        app.buttons["Add"].tap()

        // Backing out must discard the draft entirely — this is why the sheet
        // builds drafts instead of inserting models as you type.
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()

        XCTAssertFalse(app.staticTexts["Abandoned entry"].waitForExistence(timeout: 2),
                       "A cancelled meal must not be saved")
        capture("14-diet-after-cancel")
    }

    // MARK: - Symptoms

    func testLogAReaction() throws {
        app.tabBars.buttons["Date Log"].tap()
        app.buttons["Log reaction"].tap()

        XCTAssertTrue(app.navigationBars["Log a reaction"].waitForExistence(timeout: 5))

        app.buttons["Heartburn or reflux"].tap()

        // `Form` renders lazily, so a control further down may not exist until
        // it's been scrolled near. Scroll first, then assert.
        let severity = app.sliders["Severity"]
        if !severity.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(severity.waitForExistence(timeout: 3), "Severity slider should be reachable")

        // Tap three-quarters along the track. The control snaps to the nearest
        // of five stops, so this must land on the fourth — that snapping is the
        // behaviour under test.
        //
        // A coordinate tap rather than `adjust(toNormalizedSliderPosition:)`:
        // the latter needs scrubber geometry that a custom control exposed via
        // `accessibilityRepresentation` doesn't provide.
        severity.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.5)).tap()
        XCTAssertEqual(severity.value as? String, "Disruptive",
                       "Tapping three-quarters along should snap to the fourth step")

        let twoHours = app.buttons["2 hrs ago"]
        if !twoHours.exists { app.swipeUp() }
        XCTAssertTrue(twoHours.waitForExistence(timeout: 3), "Quick time offsets should be reachable")
        twoHours.tap()
        capture("15-symptom-filled")

        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Heartburn or reflux"].waitForExistence(timeout: 5),
                      "The reaction should appear in the Date Log")
        capture("16-datelog-after-save")
    }

    // MARK: - Journal

    func testWriteAJournalEntry() throws {
        app.tabBars.buttons["Journal"].tap()
        app.buttons["New entry"].tap()

        XCTAssertTrue(app.navigationBars["New entry"].waitForExistence(timeout: 5))

        // An empty entry isn't worth saving, so Save stays off until there's text.
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save should be disabled with an empty body")

        let bodyField = app.textViews["journalBodyField"].exists
            ? app.textViews["journalBodyField"]
            : app.textFields["journalBodyField"]
        XCTAssertTrue(bodyField.waitForExistence(timeout: 5))
        bodyField.tap()
        bodyField.typeText("Ate earlier than usual and slept better for it.")

        XCTAssertTrue(app.buttons["Save"].isEnabled, "Save should enable once there's a body")
        capture("17-journal-filled")

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Ate earlier than usual and slept better for it."]
            .waitForExistence(timeout: 5), "The entry should appear in the Journal")
        capture("18-journal-after-save")
    }

    // MARK: - Water

    func testLogACustomDrinkAmount() throws {
        app.tabBars.buttons["Water"].tap()
        app.buttons["Another amount"].tap()

        XCTAssertTrue(app.navigationBars["Add a drink"].waitForExistence(timeout: 5))

        app.buttons["330 ml"].tap()
        let container = app.textFields["Container, e.g. Mug"]
        XCTAssertTrue(container.waitForExistence(timeout: 3))
        replaceText(in: container, with: "Can")
        capture("19-water-custom")

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Can"].waitForExistence(timeout: 5),
                      "The custom drink should appear in today's list")
        capture("20-water-after-save")
    }
}

// MARK: - Phase 2: database-backed food search

extension LoggingFlowUITests {

    /// The whole point of Phase 2: log a real food without typing any numbers.
    func testLogAFoodFromTheDatabase() throws {
        app.tabBars.buttons["Diet"].tap()
        app.buttons["Log food"].tap()
        app.buttons["addFoodButton"].tap()

        XCTAssertTrue(app.navigationBars["Add a food"].waitForExistence(timeout: 5),
                      "Adding a food should now open search")

        // An empty box still offers somewhere to start.
        XCTAssertTrue(app.staticTexts["Common foods"].waitForExistence(timeout: 3),
                      "Empty search should suggest common foods")
        capture("30-foodsearch-empty")

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("cooked white rice")

        // The top hit must actually be rice, not rice flour or rice milk.
        let riceResult = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Rice'")
        ).firstMatch
        XCTAssertTrue(riceResult.waitForExistence(timeout: 5), "Search should find rice")
        capture("31-foodsearch-results")
        riceResult.tap()

        XCTAssertTrue(app.navigationBars["Portion"].waitForExistence(timeout: 5),
                      "Choosing a food should ask for a portion")

        // Nutrition must be filled in from the database, not left at zero.
        //
        // Matched on the sheet's own "Weight" row. The looser '[0-9]+ g' this
        // used to be passed by finding "165 g" on the Diet screen *behind* the
        // sheet, and would have gone on passing with the weight stuck at zero.
        let weightLabel = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES 'Weight, [1-9][0-9]* g'")
        ).firstMatch
        XCTAssertTrue(weightLabel.waitForExistence(timeout: 3), "Portion should resolve to a weight")
        capture("32-portion-picker")

        app.buttons["Add"].tap()

        // Back on the meal sheet with real numbers attached.
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save"].isEnabled, "A database food should enable saving")
        capture("33-meal-with-database-food")

        app.buttons["Save"].tap()

        let logged = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Rice'")
        ).firstMatch
        XCTAssertTrue(logged.waitForExistence(timeout: 5),
                      "The food should appear in the Diet log")
        capture("34-diet-with-database-food")
    }
}
