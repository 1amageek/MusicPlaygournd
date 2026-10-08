import AVFoundation
import SwiftMusic
import XCTest
@testable import MusicPlayground

@MainActor
final class NativePlaybackTests: XCTestCase {
    private func demoLoop() throws -> PreparedLoop {
        try LoopRenderer().render(SoundCompiler().compile(DemoMusic()), bpm: 120, beatsPerBar: 4)
    }

    func testScorePCMConversionAndPortableCodec() throws {
        let loop = try demoLoop()
        try loop.validate()
        XCTAssertEqual(loop.events.count, 14)
        XCTAssertEqual(loop.rows.count, 4)
        XCTAssertEqual(loop.events.filter { $0.label == "Melody" }.compactMap(\.midiNote), [60, 64, 67, 71, 67, 64, 62, 67])
        XCTAssertEqual(loop.beatCount, 4)
        XCTAssertEqual(loop.pcm.count, 176_400)
        XCTAssertTrue(loop.pcm.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(loop.pcm.reduce(0) { max($0, abs($1)) }, 0.01)
        let encoded = try PropertyListEncoder().encode(loop)
        let decoded = try PropertyListDecoder().decode(PreparedLoop.self, from: encoded)
        XCTAssertEqual(decoded, loop)
        var workerData = try XCTUnwrap(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
        workerData["pcmRange"] = [0, loop.pcm.count * 4]
        let unsupported = try PropertyListSerialization.data(fromPropertyList: workerData, format: .binary, options: 0)
        XCTAssertThrowsError(try PropertyListDecoder().decode(PreparedLoop.self, from: unsupported))
    }

    func testInvalidScoreAndInvalidPCMFailExplicitly() throws {
        XCTAssertThrowsError(try SoundCompiler().compile(Synthesizer(.sine).rhythm("[")))
        let invalid = PreparedLoop(sampleRate: 44_100, bpm: 120, beatsPerBar: 4, beatCount: 4,
                                   samples: [0, .nan], events: [])
        XCTAssertThrowsError(try invalid.validate())
    }

    func testNativeHardwarePlaybackStopAndRestart() async throws {
        let audio = try AudioWorkspace()
        addTeardownBlock { try await audio.stop() }
        try await audio.prepareDefault(id: UUID())
        for iteration in 0..<2 {
            try await audio.toggle(0)
            let deadline = ContinuousClock.now + .seconds(8)
            while !audio.masterSamples.contains(where: { abs($0) > 0.01 }), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50)); audio.refresh()
            }
            XCTAssertTrue(audio.a.isPlaying)
            XCTAssertTrue(audio.masterSamples.contains { abs($0) > 0.01 })
            XCTAssertFalse(AVAudioSession.sharedInstance().currentRoute.outputs.isEmpty)
            print("IPAD_AUDIO_PROOF restart=\(iteration) route=\(audio.route)")
            try await audio.stop()
            XCTAssertFalse(audio.a.isPlaying); XCTAssertFalse(audio.b.isPlaying)
        }
    }

    func testStopDuringActivationRejectsLatePlayback() async throws {
        let audio = try AudioWorkspace()
        addTeardownBlock { try await audio.stop() }
        try await audio.prepareDefault(id: UUID())
        let start = Task { try await audio.toggle(0) }
        await Task.yield()
        try await audio.stop()
        do { try await start.value } catch is CancellationError { }
        try await Task.sleep(for: .milliseconds(200)); audio.refresh()
        XCTAssertFalse(audio.a.isPlaying); XCTAssertFalse(audio.sessionActive)
    }

    func testModelCancellationAndRestart() async throws {
        let audio = try AudioWorkspace()
        addTeardownBlock { try await audio.stop() }
        let first = Task { try await audio.prepareDefault(id: UUID()) }
        while !audio.a.isPreparing { await Task.yield() }
        try await audio.stop()
        do { try await first.value; XCTFail("Cancelled preparation must not complete.") }
        catch is CancellationError { }
        XCTAssertFalse(audio.a.isPreparing); XCTAssertFalse(audio.a.isPlaying)
        try await audio.prepareDefault(id: UUID())
        XCTAssertEqual(audio.a.peaks.count, 512)
        XCTAssertTrue(audio.a.peaks.allSatisfy { $0.isFinite && $0 >= 0 })
        let overview = audio.a.peaks
        try await audio.toggle(0); try await audio.stop(); try await audio.toggle(0)
        XCTAssertTrue(audio.a.isPlaying); XCTAssertEqual(audio.a.peaks, overview)
    }
}
