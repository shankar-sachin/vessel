import XCTest

/// Cold launch to first frame, measured by the system.
///
/// Recorded rather than asserted against a fixed number: simulator launch
/// times swing with host load. The result is in the test report; a baseline
/// can be set in Xcode once there's a real device to set it on.
@MainActor
final class LaunchPerformanceUITests: XCTestCase {
    func testLaunchTime() throws {
        measure(metrics: [XCTApplicationLaunchMetric()], options: {
            let options = XCTMeasureOptions()
            options.iterationCount = 3
            return options
        }()) {
            XCUIApplication().launch()
        }
    }
}
