import XCTest

/// Drives the real app on a simulator.
///
/// These exist because the parts of Vessel most worth getting right — a liquid
/// that rises when you tap, a streak ring that fills — can't be judged from a
/// unit test or a static launch screenshot. Each test attaches before/after
/// screenshots so a visual regression is visible in the result bundle.
@MainActor
final class WaterLoggingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VESSEL_SEED_SAMPLE_DATA"] = "1"
        // Keep animations real: the whole point here is to exercise them.
        app.launch()
    }

    /// Captures the screen under a readable name in the result bundle.
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testQuickAddPoursIntoTheVessel() throws {
        app.tabBars.buttons["Water"].tap()

        let heroTotal = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'ml'")
        ).firstMatch
        XCTAssertTrue(heroTotal.waitForExistence(timeout: 5), "Water screen should show a running total")

        capture("01-water-before")

        // Accessibility label comes from QuickAddButton: "Add <title>".
        let glass = app.buttons["Add Glass"]
        XCTAssertTrue(glass.waitForExistence(timeout: 5), "Glass quick-add should be present")
        glass.tap()

        // Grab a frame while the rising label and the slosh are still in flight.
        capture("02-water-midpour")

        // Let the spring settle before asserting the resting state.
        Thread.sleep(forTimeInterval: 2.0)
        capture("03-water-after")

        // The drink must actually be recorded, not merely animated.
        XCTAssertTrue(
            app.staticTexts["Glass"].waitForExistence(timeout: 3),
            "The logged drink should appear in today's list"
        )
    }

    func testRepeatedTapsStackWithoutLosingEntries() throws {
        app.tabBars.buttons["Water"].tap()

        let bottle = app.buttons["Add Bottle"]
        XCTAssertTrue(bottle.waitForExistence(timeout: 5))

        // Rapid repeats are the realistic case — catching up on a day's drinks
        // at once — and each must land even while the previous is animating.
        for _ in 0..<3 { bottle.tap() }
        capture("04-water-rapid-taps")

        Thread.sleep(forTimeInterval: 2.0)
        capture("05-water-rapid-settled")

        let bottleRows = app.staticTexts.matching(identifier: "Bottle").count
        XCTAssertGreaterThanOrEqual(bottleRows, 3, "Every rapid tap should be recorded")
    }

    func testTodayTitleAndStreakRender() throws {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        capture("06-today")
    }
}
