import XCTest

/// Drives logging from a photo.
///
/// Uses the photo library rather than the camera because a simulator has no
/// camera — and because logging a picture you already took is a real workflow,
/// not just a testing convenience.
final class CaptureUITests: XCTestCase {

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

    func testCaptureSheetOpensAndOffersBothRoutes() throws {
        let button = app.buttons["capturePrompt"]
        XCTAssertTrue(button.waitForExistence(timeout: 6), "Today should offer photo logging")
        button.tap()

        XCTAssertTrue(app.navigationBars["From a photo"].waitForExistence(timeout: 5))

        // Both routes are offered, and the footer is explicit about which one
        // can be trusted — that honesty is the point of the screen.
        XCTAssertTrue(app.buttons["capturePickPhoto"].exists, "photo route should be offered")
        XCTAssertTrue(app.textFields["captureBarcodeField"].exists, "barcode route should be offered")
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'exact figures'")
            ).firstMatch.exists,
            "the screen should say which route is exact"
        )
        capture("50-capture-sheet")

        // Nothing chosen yet, so there's nothing to add.
        XCTAssertFalse(app.buttons["Add"].isEnabled, "Add should be disabled with no source")
    }

    func testPickingAPhotoProducesCandidates() throws {
        app.buttons["capturePrompt"].tap()
        XCTAssertTrue(app.navigationBars["From a photo"].waitForExistence(timeout: 5))

        app.buttons["capturePickPhoto"].tap()

        // The system photo picker runs out of process, and its view hierarchy
        // differs between iOS releases. Try the shapes it's known to take, and
        // skip rather than fail if none match — the recogniser itself is
        // covered directly by VesselVisionTests against real photographs, so a
        // picker that moved isn't a reason to call the feature broken.
        let candidates: [XCUIElement] = [
            app.collectionViews.cells.firstMatch,
            app.scrollViews.otherElements.images.firstMatch,
            app.collectionViews.images.firstMatch
        ]

        var picked = false
        for element in candidates where element.waitForExistence(timeout: 4) {
            guard element.isHittable else { continue }
            element.tap()
            picked = true
            break
        }
        guard picked else {
            throw XCTSkip("The system photo picker didn't expose a tappable photo")
        }

        // Recognition runs on device and takes a moment.
        let sawSomething = app.staticTexts["What Vessel saw"]
        let noMatch = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Nothing recognisable'")
        ).firstMatch

        let appeared = sawSomething.waitForExistence(timeout: 20) || noMatch.exists
        XCTAssertTrue(appeared, "the sheet should report what it made of the photo either way")
        capture("51-capture-result")
    }
}
