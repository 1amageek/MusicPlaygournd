import XCTest
import UIKit

@MainActor
final class PlaybackUITests: XCTestCase {
    private func evidence(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(identifier: "master-output").firstMatch.value as? String ?? ""
    }
    func testCompactSidebarKeepsNamesReadableAndTreeSelectionNative() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textViews["source-editor"].waitForExistence(timeout: 15))
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let row = app.descendants(matching: .any).matching(identifier: "source-file-Session.swift").firstMatch
            if !row.exists { app.buttons["sidebar-toggle"].tap() }
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let sidebar = app.descendants(matching: .any).matching(identifier: "project-sidebar").firstMatch
            let name = sidebar.staticTexts["Session.swift"].firstMatch
            XCTAssertTrue(name.exists)
            let fullNameWidth = ("Session.swift" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12)]).width
            XCTAssertGreaterThanOrEqual(name.frame.width, fullNameWidth - 2)
            let nameInset = name.frame.minX - sidebar.frame.minX
            // Content margin + row inset + three tree levels + icon + spacing, with pixel rounding.
            XCTAssertLessThanOrEqual(nameInset, CGFloat(52))
            let manifest = sidebar.staticTexts["Package.swift"].firstMatch
            XCTAssertTrue(manifest.exists)
            let manifestWidth = ("Package.swift" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12)]).width
            XCTAssertGreaterThanOrEqual(manifest.frame.width, manifestWidth - 2)
            let sources = sidebar.buttons["sidebar-disclosure-Sources"]
            XCTAssertEqual(sources.value as? String, "Expanded")
            sources.tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: row)
            waitForExpectations(timeout: 5)
            XCTAssertEqual(sources.value as? String, "Collapsed")
            XCTAssertTrue(manifest.exists)
            sources.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.buttons["Select Session.swift"].exists)
            manifest.tap()
            expectation(for: NSPredicate { _, _ in (app.textViews["source-editor"].value as? String)?.contains("import PackageDescription") == true }, evaluatedWith: app)
            waitForExpectations(timeout: 5)
            row.tap()
            expectation(for: NSPredicate { _, _ in (app.textViews["source-editor"].value as? String)?.contains("struct Session: Music") == true }, evaluatedWith: app)
            waitForExpectations(timeout: 5)
            print("SIDEBAR_NAME_WIDTH Session=\(name.frame.width) Package=\(manifest.frame.width)")
            attach("Compact sidebar with readable names, \(orientation)")
        }
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
        app.buttons["play-A"].tap()
        expectation(for: NSPredicate { _, _ in self.evidence(app).contains("A playing") }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(source.value as? String, edited)
        XCTAssertTrue(evidence(app).contains("A playing"))
        app.buttons["play-A"].tap()
    }
    func testPlayStopRestartAndBackgroundLifecycle() {
        let app = XCUIApplication(); app.launch()
        let play = app.buttons["play-A"], stop = app.buttons["play-A"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertEqual(play.value as? String, "Paused")
        XCTAssertTrue(app.textViews["source-editor"].exists)
        XCTAssertTrue(app.buttons["create-file-A"].exists)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 10)
        play.tap()
        expectation(for: NSPredicate { _, _ in
            let value = self.evidence(app)
            return value.contains("A playing")
        }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let waveform = app.buttons["deck-A-wave"]
        XCTAssertEqual(waveform.value as? String, "512 PCM peak bins")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Real project files and editor with accepted audio on physical iPad"
        screenshot.lifetime = .keepAlways; add(screenshot)
        stop.tap()
        expectation(for: NSPredicate(format: "value == 'Paused'"), evaluatedWith: play)
        waitForExpectations(timeout: 5)
        play.tap()
        expectation(for: NSPredicate(format: "value == 'Playing'"), evaluatedWith: play)
        waitForExpectations(timeout: 10)
        XCUIApplication(bundleIdentifier: "com.apple.Preferences").activate()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        expectation(for: NSPredicate(format: "value == 'Paused'"), evaluatedWith: play)
        waitForExpectations(timeout: 5)
    }
    func testCompleteProductionDecksEffectsAndAdaptiveWorkspace() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textViews["source-editor"].waitForExistence(timeout: 15))
        attach("Landscape with project sidebar")
        let toggle = app.buttons["sidebar-toggle"]
        XCTAssertTrue(toggle.exists); toggle.tap()
        let playA = app.buttons["play-A"], playB = app.buttons["play-B"]
        XCTAssertTrue(playA.waitForExistence(timeout: 10)); XCTAssertTrue(playB.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: playA)
        waitForExpectations(timeout: 10)
        playA.tap(); playB.tap()
        expectation(for: NSPredicate { _, _ in self.evidence(app).contains("A playing; B playing") }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        attach("Shared complete A master B with accepted audio")
        print("NATIVE_PARITY_TREE\n" + app.debugDescription)
        app.buttons["Deck A FX"].tap()
        XCTAssertTrue(app.buttons["Chorus"].waitForExistence(timeout: 5))
        app.buttons["Chorus"].tap()
        let mix = app.sliders["Deck A FX Mix"]
        XCTAssertTrue(mix.exists); mix.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: mix.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
        XCTAssertNotEqual(mix.value as? String, "0%")
        attach("Shared Chorus controls while both decks play")
        app.buttons["master-output"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: mix)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(playA.value as? String, "Playing"); XCTAssertEqual(playB.value as? String, "Playing")
        app.descendants(matching: .any).matching(identifier: "Rhythm display layout").firstMatch.tap()
        XCTAssertTrue(app.buttons["Side Timeline"].waitForExistence(timeout: 5)); app.buttons["Side Timeline"].tap()
        attach("Actual source aligned side timeline")
        app.descendants(matching: .any).matching(identifier: "Rhythm display layout").firstMatch.tap(); app.buttons["Bottom Overview"].tap()
        attach("Actual accepted bottom overview")
        app.scrollViews["bottom-overview"].swipeUp()
        XCTAssertTrue(app.buttons["Mute Hat"].isHittable)
        app.descendants(matching: .any).matching(identifier: "Rhythm display layout").firstMatch.tap(); app.buttons["Inline Results"].tap()
        attach("Actual accepted inline results")
        XCUIDevice.shared.orientation = .portrait
        toggle.tap(); toggle.tap()
        XCTAssertTrue(app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height)
        XCTAssertTrue(playA.isHittable); XCTAssertTrue(playB.isHittable)
        attach("Landscape-only workspace after attempted portrait rotation")
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(playA.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height)
        attach("Opposite landscape orientation")
        XCUIApplication(bundleIdentifier: "com.apple.Preferences").activate()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        expectation(for: NSPredicate(format: "value == 'Paused'"), evaluatedWith: playA)
        waitForExpectations(timeout: 5)
        XCUIDevice.shared.orientation = .landscapeLeft
    }
    func testAcceptedControlsMasterRecordingAndHostOptionsFromRealScreen() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["play-A"].waitForExistence(timeout: 15))
        if app.buttons["sidebar-toggle"].label == "Hide Sidebar" { app.buttons["sidebar-toggle"].tap() }
        for name in ["A", "B"] {
            let play = app.buttons["play-" + name]
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play); waitForExpectations(timeout: 10)
            play.tap()
            expectation(for: NSPredicate(format: "value == 'Playing'"), evaluatedWith: play); waitForExpectations(timeout: 10)
            let pad = app.sliders["Deck " + name + " filter"]
            XCTAssertTrue(pad.exists)
            pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
                thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3)))
            XCTAssertNotEqual(pad.value as? String, "50%")
            app.buttons["Reset Deck " + name + " filter and space"].tap()
            XCTAssertEqual(pad.value as? String, "50%")
            let band = app.buttons.matching(identifier: "deck-" + name + "-equalizer").matching(NSPredicate(format: "label == 'EQ band 2'")).firstMatch
            XCTAssertTrue(band.exists)
            let previous = band.value as? String
            band.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
                thenDragTo: band.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.2)))
            XCTAssertNotEqual(band.value as? String, previous)
            app.buttons.matching(identifier: "deck-" + name + "-equalizer").matching(NSPredicate(format: "label == 'Reset all EQ bands'")).firstMatch.tap()
        }
        app.buttons["Mute Melody"].tap()
        expectation(for: NSPredicate(format: "value == 'Muted'"), evaluatedWith: app.buttons["Unmute Melody"]); waitForExpectations(timeout: 10)
        app.buttons["Unmute Melody"].tap()
        let volume = app.sliders["Master volume"]
        volume.adjust(toNormalizedSliderPosition: 0.65)
        XCTAssertNotEqual(volume.value as? String, "100%")
        app.buttons["Record master"].tap()
        XCTAssertTrue(app.buttons["stop.circle.fill"].waitForExistence(timeout: 5))
        app.buttons["Record master"].tap()
        XCTAssertTrue(app.staticTexts["Recording saved"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Save or Share WAV"].exists)
        attach("Actual master recording save workflow")
        app.buttons["Done"].tap()
        app.buttons["Deck A controls"].tap()
        XCTAssertTrue(app.buttons["Save Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "midi-input").firstMatch.exists)
        attach("Accepted controls and initially collapsed MIDI")
        app.buttons["Save Settings"].tap()
        let midi = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'MIDI Options'")).firstMatch
        XCTAssertTrue(midi.exists); midi.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "midi-input").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Input"].exists); XCTAssertTrue(app.staticTexts["Output"].exists)
        XCTAssertFalse(app.buttons["MIDI clock Send"].isEnabled); XCTAssertFalse(app.buttons["MIDI clock Receive"].isEnabled)
        XCTAssertEqual(app.buttons["MIDI clock Off"].value as? String, "Selected")
        XCTAssertFalse(app.buttons["midi-learn"].isEnabled)
        attach("Redesigned MIDI routing notes clock and selected Learn target")
        app.buttons["Record"].tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 5)); app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))
        app.buttons["master-output"].tap()
        for name in ["A", "B"] {
            let play = app.buttons["play-" + name]
            for _ in 0..<2 where play.value as? String == "Playing" { play.tap() }
            expectation(for: NSPredicate(format: "value == 'Paused'"), evaluatedWith: play); waitForExpectations(timeout: 5)
        }
        app.buttons["Deck A controls"].tap()
        let unit = app.descendants(matching: .any).matching(identifier: "audio-unit-picker").firstMatch
        XCTAssertTrue(unit.exists); unit.tap()
        print("ACTUAL_NATIVE_AUDIO_UNIT_CHOICES\n" + app.debugDescription)
        attach("Actual native Audio Unit catalog and MIDI routes")
        let highPass = app.buttons["AUHighPassFilter"]
        XCTAssertTrue(highPass.exists)
        highPass.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let bypass = app.switches["Bypass AUHighPassFilter"]
        XCTAssertTrue(bypass.waitForExistence(timeout: 10)); bypass.tap()
        XCTAssertEqual(bypass.value as? String, "1")
        unit.tap()
        app.buttons["No Audio Unit"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["master-output"].tap()
        XCTAssertEqual(app.buttons["play-A"].value as? String, "Paused")
        XCTAssertEqual(app.buttons["play-B"].value as? String, "Paused")
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
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
