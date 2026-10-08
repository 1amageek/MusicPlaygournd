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
        let source = app.staticTexts["source-code"]
        XCTAssertTrue(source.exists)
        app.descendants(matching: .any).matching(identifier: "audio-output-item").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["44100 Hz · Stereo · Native AVAudioEngine"].waitForExistence(timeout: 5))
        XCTAssertFalse(source.exists)
        app.descendants(matching: .any).matching(identifier: "bundled-source-file").firstMatch.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        let sidebarRow = app.descendants(matching: .any).matching(identifier: "audio-output-item").firstMatch
        let toggle = app.buttons["sidebar-toggle"]
        toggle.tap()
        expectation(for: NSPredicate { _, _ in !sidebarRow.isHittable }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        toggle.tap()
        expectation(for: NSPredicate { _, _ in sidebarRow.isHittable }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        sidebarRow.tap()
        XCTAssertTrue(app.staticTexts["44100 Hz · Stereo · Native AVAudioEngine"].waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "bundled-source-file").firstMatch.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        play.tap()
        let audible = NSPredicate { _, _ in
            status.label == "Playing on iPad" && evidence.label.contains("14 events") &&
                !evidence.label.contains("0 audio callbacks") && !evidence.label.contains("peak 0.000")
        }
        expectation(for: audible, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let waveform = app.descendants(matching: .any).matching(identifier: "loop-waveform").firstMatch
        XCTAssertEqual(waveform.value as? String, "512 PCM peak bins")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Shared MusicPlaygroundUI playing on physical iPad"
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
    func testUnsupportedCapabilitiesAreExplicit() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Deck B is unavailable in the iPad prototype."].exists)
        app.buttons["ipad-fx-info"].tap()
        XCTAssertTrue(app.staticTexts["FX unavailable"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders.count, 0)
    }
}
