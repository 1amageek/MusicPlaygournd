import XCTest

@MainActor
final class PlaybackUITests: XCTestCase {
    private func evidence(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(identifier: "outputEvidence").firstMatch.value as? String ?? ""
    }
    func testNativeEditingAndSidebarChangesKeepActualTextAndAcceptedAudio() {
        let app = XCUIApplication(); app.launch()
        let source = app.textViews["source-editor"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.tap(); source.typeText("\n// edited on iPad\n")
        let edited = source.value as? String
        XCTAssertTrue(edited?.contains("// edited on iPad") == true)
        let toggle = app.buttons["sidebar-toggle"]
        toggle.tap(); XCTAssertEqual(source.value as? String, edited)
        toggle.tap(); XCTAssertEqual(source.value as? String, edited)
        app.buttons["play"].tap()
        expectation(for: NSPredicate { _, _ in self.evidence(app).contains("Playing on iPad") }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(source.value as? String, edited)
        XCTAssertTrue(evidence(app).contains("14 events"))
        app.buttons["stop"].tap()
    }
    func testPlayStopRestartAndBackgroundLifecycle() {
        let app = XCUIApplication(); app.launch()
        let play = app.buttons["play"], stop = app.buttons["stop"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertEqual(play.value as? String, "Ready")
        XCTAssertTrue(app.textViews["source-editor"].exists)
        XCTAssertTrue(app.buttons["create-file-A"].exists)
        play.tap()
        expectation(for: NSPredicate { _, _ in
            let value = self.evidence(app)
            return value.contains("Playing on iPad") && value.contains("14 events") &&
                !value.contains("0 audio callbacks") && !value.contains("peak 0.000")
        }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let waveform = app.descendants(matching: .any).matching(identifier: "loop-waveform").firstMatch
        XCTAssertEqual(waveform.value as? String, "512 PCM peak bins")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Real project files and editor with accepted audio on physical iPad"
        screenshot.lifetime = .keepAlways; add(screenshot)
        stop.tap()
        expectation(for: NSPredicate(format: "value == 'Ready'"), evaluatedWith: play)
        waitForExpectations(timeout: 5)
        play.tap()
        expectation(for: NSPredicate(format: "value == 'Playing on iPad'"), evaluatedWith: play)
        waitForExpectations(timeout: 10)
        XCUIDevice.shared.press(.home); app.activate()
        expectation(for: NSPredicate(format: "value == 'Ready'"), evaluatedWith: play)
        waitForExpectations(timeout: 5)
    }
    func testNumberedCreationDirtyCloseCancelSaveAndActualReopen() {
        let app = XCUIApplication(); app.launch()
        let create = app.buttons["create-file-A"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let source = app.textViews["source-editor"]
        expectation(for: NSPredicate(format: "value == %@", "import SwiftMusic\n"), evaluatedWith: source)
        waitForExpectations(timeout: 5)
        let tab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Select Sound'")).firstMatch
        XCTAssertTrue(tab.exists)
        let name = String(tab.label.dropFirst("Select ".count))
        source.tap(); source.typeText("// persisted iPad document\n")
        let edited = source.value as? String
        app.buttons["Close " + name].tap()
        XCTAssertTrue(app.alerts["Save Changes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(source.value as? String, edited)
        app.buttons["Close " + name].tap(); app.alerts.buttons["Save"].tap()
        expectation(for: NSPredicate { _, _ in !app.buttons["Select " + name].exists }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        let row = app.descendants(matching: .any).matching(identifier: "source-file-" + name).firstMatch
        XCTAssertTrue(row.exists); row.tap()
        expectation(for: NSPredicate { _, _ in source.value as? String == edited }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        create.tap()
        expectation(for: NSPredicate(format: "value == %@", "import SwiftMusic\n"), evaluatedWith: source)
        waitForExpectations(timeout: 5)
        let names = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Select Sound'")).allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Set(names).count, 2)
    }
}
