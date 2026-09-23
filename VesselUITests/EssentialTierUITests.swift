import XCTest

/// The iOS 18 experience, driven on a 26+ simulator.
///
/// No iOS 18 simulator runtime ships with current Xcode, so the tier is forced
/// with a DEBUG-only launch variable. That exercises every Essential code path;
/// what it can't show is a 26-only symbol reached on a real iOS 18 device —
/// which the compiler's availability checking guards against, since the
/// deployment target is 18.
@MainActor
final class EssentialTierUITests: XCTestCase {

    private func launch(seed: Bool, freshCard: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VESSEL_FORCE_TIER"] = "essential"
        if freshCard { app.launchEnvironment["VESSEL_RESET_UPGRADE_PROMPT"] = "1" }
        if seed { app.launchEnvironment["VESSEL_SEED_SAMPLE_DATA"] = "1" }
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The card, scrolled into reach, or nil if Today doesn't show it.
    ///
    /// Presence is judged by existence, not by being tappable: after other
    /// tests have logged meals, Today is long and the card starts below the
    /// floating tab bar. Scrolling then brings it within reach.
    private func findCard(in app: XCUIApplication) -> XCUIElement? {
        // SwiftUI leaves off-screen scroll content out of the accessibility
        // tree, so the card only exists once it has been scrolled near.
        let card = app.descendants(matching: .any)["upgradeCard"]
        for _ in 0..<12 where !(card.exists && card.buttons["Dismiss"].isHittable) {
            app.swipeUp()
        }
        return card.exists ? card : nil
    }

    func testUpgradeCardAppearsOnceAndStaysDismissed() throws {
        // Fresh card: the simulator keeps its data between runs, and a card
        // dismissed by an earlier run is correctly still dismissed.
        var app = launch(seed: true, freshCard: true)
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 6))

        let card = try XCTUnwrap(findCard(in: app), "The Essential tier should offer the upgrade once")
        XCTAssertTrue(card.buttons["Dismiss"].isHittable, "The card sits at the top of Today, no scrolling needed")
        XCTAssertTrue(card.buttons["openSoftwareUpdate"].exists, "The card offers a way to update")
        capture("essential-upgrade-card")
        card.buttons["Dismiss"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 2), "Dismissing should remove it")

        // It must not come back on the next launch: a prompt that returns is a nag.
        app.terminate()
        app = launch(seed: false)
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 6))
        XCTAssertNil(findCard(in: app).flatMap { $0.exists ? $0 : nil },
                     "A dismissed upgrade card must stay dismissed")
    }

    func testEssentialTierIsAWholeApp() throws {
        let app = launch(seed: true)
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 6))
        capture("essential-today")

        // Every module opens and logging works without 26+ features.
        for tab in ["Diet", "Water", "Journal", "Date Log"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 4), "\(tab) should open")
        }
        app.buttons["floatingLogButton"].tap()
        let field = app.textViews["quickLogField"].exists ? app.textViews["quickLogField"] : app.textFields["quickLogField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("two slices of toast")
        XCTAssertTrue(app.staticTexts["A meal"].waitForExistence(timeout: 6),
                      "The parser is the app's own and needs nothing from 26+")
        capture("essential-quicklog")
    }
}
