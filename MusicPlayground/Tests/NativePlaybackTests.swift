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
        let buffer = try NativeAudioPlayer.makeBuffer(loop)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(Int(buffer.frameLength) * 2, loop.pcm.count)
        for frame in 0..<Int(buffer.frameLength) {
            XCTAssertEqual(channels[0][frame], loop.pcm[frame * 2])
            XCTAssertEqual(channels[1][frame], loop.pcm[frame * 2 + 1])
        }
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
        XCTAssertThrowsError(try NativeAudioPlayer.makeBuffer(invalid))
    }

    func testNativeHardwarePlaybackStopAndRestart() async throws {
        let audio = NativeAudioPlayer()
        addTeardownBlock { try await audio.stop() }
        let loop = try demoLoop()
        try await audio.start(loop)
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(audio.isPlaying)
        XCTAssertGreaterThan(audio.meter.callbackCount, 0)
        XCTAssertGreaterThan(audio.meter.peak, 0.01)
        XCTAssertFalse(AVAudioSession.sharedInstance().currentRoute.outputs.isEmpty)
        print("IPAD_AUDIO_PROOF first callbacks=\(audio.meter.callbackCount) peak=\(audio.meter.peak) route=\(audio.outputDescription)")
        try await audio.stop()
        XCTAssertFalse(audio.isPlaying)
        try await Task.sleep(for: .milliseconds(100))
        let stoppedCount = audio.meter.callbackCount
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(audio.meter.callbackCount, stoppedCount)
        try await audio.start(loop)
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(audio.isPlaying)
        XCTAssertGreaterThan(audio.meter.peak, 0.01)
        print("IPAD_AUDIO_PROOF restart callbacks=\(audio.meter.callbackCount) peak=\(audio.meter.peak) route=\(audio.outputDescription)")
    }

    func testStopDuringActivationRejectsLatePlayback() async throws {
        let audio = NativeAudioPlayer()
        addTeardownBlock { try await audio.stop() }
        let loop = try demoLoop()
        let start = Task { try await audio.start(loop) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !audio.isActivating && !audio.isPlaying && ContinuousClock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(audio.isActivating, "Stop must exercise an actual pending activation.")
        try await audio.stop()
        do {
            try await start.value
            XCTFail("An invalidated activation must not start playback.")
        } catch is CancellationError {
            XCTAssertFalse(audio.isPlaying)
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(audio.isPlaying)
        XCTAssertEqual(audio.meter.callbackCount, 0)
    }

    func testModelCancellationAndRestart() async throws {
        let audio = NativeAudioPlayer()
        addTeardownBlock { try await audio.stop() }
        let model = PlaybackModel(audio: audio)
        let first = Task { await model.play() }
        // Yield so Play owns a real in-flight render before Stop invalidates it.
        while model.state == .idle { await Task.yield() }
        await model.stop()
        await first.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertFalse(audio.isPlaying)
        await model.play()
        XCTAssertEqual(model.state, .playing)
        XCTAssertEqual(model.loopPeaks.count, 512)
        XCTAssertTrue(model.loopPeaks.allSatisfy { $0.isFinite && $0 >= 0 })
        XCTAssertGreaterThan(model.loopPeaks.max() ?? 0, 0.01)
        let overview = model.loopPeaks
        try await Task.sleep(for: .milliseconds(500))
        model.refreshOutput()
        XCTAssertGreaterThan(model.peak, 0.01)
        await model.stop()
        XCTAssertEqual(model.state, .idle)
        XCTAssertFalse(audio.isPlaying)
        await model.play()
        XCTAssertEqual(model.state, .playing)
        XCTAssertEqual(model.loopPeaks, overview)
        await model.stop()
    }
}
