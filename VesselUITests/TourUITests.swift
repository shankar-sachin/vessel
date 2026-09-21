import XCTest

/// Walks the app the way a person would, capturing each screen.
///
/// Exists to produce review material — screenshots and a screen recording —
/// from the real app rather than from mockups, so what gets shared is what
/// actually ships.
final class TourUITests: XCTestCase {

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

    private func pause(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func testFullTour() throws {
        // Today
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 6))
        pause()
        capture("tour-1-today")

        // Quick log, typed the way you'd say it
        app.buttons["quickLogPrompt"].tap()
        XCTAssertTrue(app.navigationBars["Quick log"].waitForExistence(timeout: 5))
        pause(0.8)
        capture("tour-2-quicklog-empty")

        let field = app.textViews["quickLogField"].exists
            ? app.textViews["quickLogField"]
            : app.textFields["quickLogField"]
        field.tap()
        field.typeText("two eggs and a slice of toast")

        // Give the debounce time to settle before capturing, or the shot shows
        // a half-finished parse.
        XCTAssertTrue(app.staticTexts["Vessel read this as"].waitForExistence(timeout: 6))
        pause(1.5)
        capture("tour-3-quicklog-parsed")

        app.buttons["Save"].tap()
        pause()

        // Each module
        for (tab, name) in [("Diet", "tour-4-diet"), ("Water", "tour-5-water"),
                            ("Journal", "tour-6-journal"), ("Date Log", "tour-7-datelog")] {
            app.tabBars.buttons[tab].tap()
            pause()
            capture(name)
        }

        // Water is the one with motion worth seeing
        app.tabBars.buttons["Water"].tap()
        pause(0.6)
        app.buttons["Add Glass"].tap()
        pause(0.4)
        capture("tour-8-water-pour")
        pause(1.6)
        capture("tour-9-water-settled")

        // Settings, including the fasting plans and backup
        app.tabBars.buttons["Today"].tap()
        pause(0.6)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        pause()
        capture("tour-10-settings")
    }
}
