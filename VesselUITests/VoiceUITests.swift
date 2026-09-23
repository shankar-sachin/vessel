import XCTest

/// Tapping the microphone must not kill the app.
///
/// There was no test here, which is exactly why a crash on the first tap
/// survived a release: the simulator has no microphone, so every *other* voice
/// path fails early and looks like a clean refusal. The crash was never in the
/// audio at all — it was in the permission callbacks, which run on whatever
/// queue Speech feels like using and fire before a microphone is ever needed.
///
/// So this test asserts something deliberately weak: that the app is still
/// running afterwards. That is the bug, and a weak assertion that would have
/// caught it beats a strong one nobody wrote.
@MainActor
final class VoiceUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VESSEL_SEED_SAMPLE_DATA"] = "1"
        app.launch()
    }

    /// Answers a system permission alert if one is up.
    ///
    /// The alert has to actually be dismissed. Leaving it on screen is how the
    /// first version of this test passed while the bug was still there: the
    /// permission handler never ran, so the crash it causes never happened, and
    /// a screenshot of an unanswered dialog looked like a working microphone.
    @discardableResult
    private func answerPermissionAlert(_ button: String = "Allow", timeout: TimeInterval = 8) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let action = springboard.buttons[button]
        guard action.waitForExistence(timeout: timeout) else { return false }
        action.tap()
        return true
    }

    func testTappingTheMicrophoneDoesNotCrash() throws {
        let prompt = app.buttons["quickLogPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        prompt.tap()

        let mic = app.buttons["quickLogMic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()

        // Speech recognition first, then the microphone — the order the
        // transcriber asks in.
        answerPermissionAlert()
        answerPermissionAlert(timeout: 4)

        // The handlers land on a background queue the moment the alert is
        // answered. If they are main-actor isolated, the process is already
        // gone by the time this runs.
        XCTAssertEqual(app.state, .runningForeground, "the app died on the microphone tap")

        // And it must resolve to something rather than hang. On a simulator
        // that means the honest refusal; on hardware, listening.
        // How it resolves depends on the hardware, and all of these are fine:
        // on a simulator the recogniser starts and then hears nothing; on a
        // device it listens; with permission refused it says so. What is not
        // fine is a process that is no longer there — which is what the
        // assertion above is really for, and what this test exists to catch.
        let resolutions = [
            "Listening…",                    // hardware, working
            "Didn",                          // "Didn't catch anything…" — simulator
            "No microphone is available",
            "start recording",
            "Vessel needs",                  // permission refused
            "won't use it"                   // on-device recognition unavailable
        ]
        let resolved = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@"
                        + " OR label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        argumentArray: resolutions)
        ).firstMatch
        XCTAssertTrue(resolved.waitForExistence(timeout: 10),
                      "the mic should either listen or say why it can't, not sit silent")

        // Still interactive afterwards — a frozen app passes a liveness check.
        XCTAssertTrue(app.buttons["quickLogMic"].isHittable,
                      "the microphone control should still be usable afterwards")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "70-voice-after-tap"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
