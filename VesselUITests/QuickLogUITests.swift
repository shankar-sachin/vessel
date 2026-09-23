import XCTest

/// Drives the natural-language logging flow end to end.
///
/// This is the feature Phase 3 exists for: type a meal the way you'd say it and
/// get a real entry with real nutrition. The test asserts the *interpretation is
/// shown before saving*, because that's the design decision the whole feature
/// rests on — a parser that fills things in invisibly is only pleasant while
/// it's right.
@MainActor
final class QuickLogUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
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

    private func openQuickLog() {
        let prompt = app.buttons["quickLogPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "Today should offer quick log")
        prompt.tap()
        XCTAssertTrue(app.navigationBars["Quick log"].waitForExistence(timeout: 5))
    }

    private func type(_ text: String) {
        let field = app.textViews["quickLogField"].exists
            ? app.textViews["quickLogField"]
            : app.textFields["quickLogField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    func testTypingAMealShowsTheInterpretation() throws {
        openQuickLog()
        capture("40-quicklog-empty")

        type("two eggs and toast")

        // The parse must appear without saving anything.
        XCTAssertTrue(
            app.staticTexts["Vessel read this as"].waitForExistence(timeout: 6),
            "The interpretation should appear live"
        )
        XCTAssertTrue(app.staticTexts["A meal"].waitForExistence(timeout: 3),
                      "It should recognise this as a meal")
        capture("41-quicklog-parsed")

        // And it must have resolved real nutrition, not zeros.
        let calories = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '[1-9][0-9]* kcal'")
        ).firstMatch
        XCTAssertTrue(calories.waitForExistence(timeout: 5),
                      "Foods should resolve to real calorie figures")

        app.buttons["Save"].tap()

        // It should land in the Diet log.
        app.tabBars.buttons["Diet"].tap()
        let logged = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'egg'")
        ).firstMatch
        XCTAssertTrue(logged.waitForExistence(timeout: 5),
                      "The parsed meal should appear in the Diet log")
        capture("42-quicklog-saved")
    }

    func testDrinkIsRecognisedAsWater() throws {
        openQuickLog()
        type("a glass of water")

        XCTAssertTrue(app.staticTexts["A drink"].waitForExistence(timeout: 6),
                      "This should be read as a drink, not a meal")
        capture("43-quicklog-drink")
    }

    func testSymptomIsRecognised() throws {
        openQuickLog()
        type("feeling really bloated")

        XCTAssertTrue(app.staticTexts["A reaction"].waitForExistence(timeout: 6),
                      "This should be read as a reaction")
        capture("44-quicklog-symptom")
    }

    /// The phrase shapes v1.5.1 retrained for, checked in the running app rather
    /// than only in the package tests: a partitive that isn't a drink, a "with"
    /// that isn't a drink, and a drink next to a word that used to mean symptom.
    func testPhrasingsTheRetrainingFixed() throws {
        let cases: [(text: String, expected: String, shot: String)] = [
            ("a quarter of a melon", "A meal", "45-quicklog-partitive"),
            ("half a baguette with butter", "A meal", "46-quicklog-with-butter"),
            ("a bottle of water after my run", "A drink", "47-quicklog-after-run"),
        ]
        for (index, item) in cases.enumerated() {
            if index > 0 {
                app.terminate()
                app.launch()
            }
            openQuickLog()
            type(item.text)
            XCTAssertTrue(app.staticTexts[item.expected].waitForExistence(timeout: 6),
                          "\"\(item.text)\" should be read as \(item.expected.lowercased())")
            capture(item.shot)
        }
    }

    /// The manual route must be reachable from Quick log without typing, and
    /// must land on the form rather than stack a sheet on a sheet.
    func testManualRouteOpensTheFoodForm() throws {
        openQuickLog()
        let route = app.buttons["quickLogManualRoute"]
        XCTAssertTrue(route.waitForExistence(timeout: 3), "Choosing foods by hand should always be offered")
        capture("48-quicklog-manual-route")
        route.tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5),
                      "It should open the manual food form")
        XCTAssertFalse(app.navigationBars["Quick log"].exists, "Quick log should have made way for it")
        capture("49-manual-form-from-quicklog")
    }

    func testExamplesArePresentAndUsable() throws {
        openQuickLog()

        // The empty state teaches the feature by example rather than by tooltip.
        let example = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'two eggs'")
        ).firstMatch
        XCTAssertTrue(example.waitForExistence(timeout: 3), "Examples should be offered")
        example.tap()

        XCTAssertTrue(app.staticTexts["Vessel read this as"].waitForExistence(timeout: 6),
                      "Tapping an example should parse it")
    }
}
