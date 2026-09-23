import XCTest

/// iPad-only behaviour: keyboard shortcuts and the split layout.
@MainActor
final class iPadUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad only")
        }
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

    func testKeyboardShortcuts() throws {
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 6))
        capture("ipad-today")

        // ⌘3 — the third module, Water.
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Water Diary"].waitForExistence(timeout: 4), "⌘3 should open Water")
        capture("ipad-water")

        // ⌘2 — Diet.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Diet Tracker"].waitForExistence(timeout: 4), "⌘2 should open Diet")
        capture("ipad-diet")

        // ⌘N — Quick log, from anywhere.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Quick log"].waitForExistence(timeout: 4), "⌘N should open Quick log")
        capture("ipad-quicklog")
    }
}
