import XCTest

/// Phase 6's screen, driven rather than described.
///
/// A static screenshot of the Date Log proves the view compiles. This proves
/// the engine ran against a real seeded history and produced something a person
/// could read — including, deliberately, the sentence that says how many
/// occasions it is based on.
@MainActor
final class InsightsUITests: XCTestCase {

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

    func testDateLogShowsWhatTheLogSuggests() throws {
        app.tabBars.buttons["Date Log"].tap()

        XCTAssertTrue(
            app.staticTexts["What your log suggests"].waitForExistence(timeout: 8),
            "the insights section should be the first thing on the Date Log"
        )
        capture("60-insights-datelog")

        // A finding must carry its sample size. This is the one presentation
        // rule the feature cannot bend: a bare percentage is the same claim
        // with the part that lets you judge it removed.
        let sampleSize = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '.*[0-9]+ of [0-9]+ occasions.*'")
        ).firstMatch
        XCTAssertTrue(sampleSize.waitForExistence(timeout: 5),
                      "every finding states how many occasions it rests on")

        // And the disclaimer is not optional.
        let disclaimer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'not a diagnosis'")
        ).firstMatch
        XCTAssertTrue(disclaimer.exists, "the non-medical disclaimer must be on screen")
        capture("61-insights-finding")
    }
}
