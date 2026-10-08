import XCTest

@MainActor
final class PlaybackUITests: XCTestCase {
    func testPlayStopRestartAndBackgroundLifecycle() {
        let app = XCUIApplication()
        app.launch()
        let play = app.buttons["play"]
        let stop = app.buttons["stop"]
        let status = app.staticTexts["playbackStatus"]
        let evidence = app.staticTexts["outputEvidence"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Ready")
        play.tap()
        let audible = NSPredicate { _, _ in
            status.label == "Playing on iPad" && evidence.label.contains("14 events") &&
                !evidence.label.contains("0 audio callbacks") && !evidence.label.contains("peak 0.000")
        }
        expectation(for: audible, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "SwiftMusic playing on physical iPad"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        stop.tap()
        expectation(for: NSPredicate(format: "label == 'Ready'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        play.tap()
        expectation(for: NSPredicate(format: "label == 'Playing on iPad'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCUIDevice.shared.press(.home)
        app.activate()
        expectation(for: NSPredicate(format: "label == 'Ready'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
    }
}
