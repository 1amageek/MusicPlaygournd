import AVFoundation
import XCTest
import Observation
import Synchronization
@testable import MusicPlayground

@MainActor
final class TwoDeckAudioTests: XCTestCase {
    private func audible(_ workspace: AudioWorkspace) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        repeat {
            try await Task.sleep(for: .milliseconds(50)); workspace.refresh()
            if workspace.masterSamples.contains(where: { abs($0) > 0.001 }) { return }
        } while ContinuousClock.now < deadline
        XCTFail("The actual shared output produced no nonzero samples.")
    }
    func testIndependentNativeDecksPauseResumeCueTempoSyncAndScratch() async throws {
        let workspace = try AudioWorkspace()
        do {
            try await workspace.prepareDefault(id: UUID())
            XCTAssertEqual(workspace.a.eventCount, 14); XCTAssertEqual(workspace.b.eventCount, 14)
            try await workspace.toggle(0); try await audible(workspace)
            let first = workspace.a.beatPosition
            try await workspace.toggle(1)
            try await Task.sleep(for: .milliseconds(250)); workspace.refresh()
            XCTAssertTrue(workspace.a.isPlaying); XCTAssertTrue(workspace.b.isPlaying)
            XCTAssertGreaterThan(workspace.a.beatPosition, first)
            workspace.a.pause()
            let paused = workspace.a.beatPosition, peer = workspace.b.beatPosition
            try await Task.sleep(for: .milliseconds(200)); workspace.refresh()
            XCTAssertEqual(workspace.a.beatPosition, paused, accuracy: 0.01)
            XCTAssertGreaterThan(workspace.b.beatPosition, peer)
            try workspace.b.setBPM(150)
            try await Task.sleep(for: .milliseconds(120))
            try workspace.a.play(); try await Task.sleep(for: .milliseconds(200)); workspace.refresh()
            try workspace.a.synchronize(to: workspace.b)
            XCTAssertEqual(workspace.a.bpm, 150)
            try await Task.sleep(for: .milliseconds(250))
            let anchorA = try workspace.a.engine.playbackClockAnchor()
            let anchorB = try workspace.b.engine.playbackClockAnchor()
            XCTAssertEqual(try anchorA.beat(atHostTime: anchorB.presentationHostTime), anchorB.accumulatedBeatPosition, accuracy: 0.04)
            workspace.a.cue.press()
            try await Task.sleep(for: .milliseconds(250)); workspace.refresh()
            XCTAssertTrue(workspace.a.cue.isPreviewing)
            workspace.a.cue.release(); workspace.refresh()
            XCTAssertFalse(workspace.a.isPlaying); XCTAssertTrue(workspace.b.isPlaying)
            let beforeScratch = workspace.a.beatPosition
            try workspace.a.scratch(seconds: -0.1, duration: 0.05)
            try await Task.sleep(for: .milliseconds(80)); workspace.refresh()
            XCTAssertNotEqual(workspace.a.beatPosition, beforeScratch)
            workspace.a.releaseScratch()
            try workspace.a.setBPM(120)
            do { try workspace.a.setBPM(.nan); XCTFail("Nonfinite tempo must fail.") } catch { }
            XCTAssertEqual(workspace.a.bpm, 120)
            try await workspace.stop()
            XCTAssertFalse(workspace.a.isPlaying); XCTAssertFalse(workspace.b.isPlaying)
        } catch {
            do { try await workspace.stop() } catch { XCTFail("Cleanup failed: \(error)") }
            throw error
        }
    }
    func testSharedNativeFXEqualizerFilterAndMasterAdmission() async throws {
        let workspace = try AudioWorkspace()
        try await workspace.prepareDefault(id: UUID())
        try workspace.setCrossfade(0)
        let deck = workspace.a
        workspace.output.audioEngine.stop()
        try deck.engine.prepareOfflineRenderingForTests()
        func render() throws -> [Float] {
            try deck.engine.restartFromBeginning()
            return try deck.engine.renderOfflineForTests(frameCount: OutputMeterStore.captureFrameCapacity * 2)
        }
        let dry = try render()
        XCTAssertTrue(dry.contains { abs($0) > 0.001 })
        for kind in DeckFXSettings.Kind.allCases {
            try deck.setFX(.init(kind: kind, rate: 2, depth: 0.8, feedback: 0.7, mix: 1))
            let wet = try render()
            XCTAssertTrue(wet.allSatisfy(\.isFinite))
            XCTAssertNotEqual(dry, wet)
            XCTAssertEqual(workspace.b.fx.mix, 0)
        }
        try deck.resetFX(); XCTAssertEqual(deck.fx.mix, 0)
        try deck.setFilter(-0.9)
        let filtered = try render(); XCTAssertNotEqual(filtered, dry)
        try deck.setFilter(0)
        try deck.setEqualizer(0, .init(frequency: 100, gain: -12, q: 1))
        let equalized = try render(); XCTAssertNotEqual(equalized, dry)
        let band = deck.equalizer[0]
        do { try deck.setEqualizer(0, .init(frequency: .nan, gain: 0, q: 1)); XCTFail("Invalid EQ must fail.") } catch { }
        XCTAssertEqual(deck.equalizer[0], band)
        try workspace.setCrossfade(0.5)
        do { try workspace.setCrossfade(2); XCTFail("Invalid crossfade must fail.") } catch { }
        XCTAssertEqual(workspace.crossfade, 0.5)
        let nativeRevision = deck.engine.snapshot().revision
        try deck.setGain(0.5); try deck.setReverb(0.2); try deck.setDelay(0.1)
        XCTAssertEqual(deck.engine.snapshot().revision, nativeRevision)
        XCTAssertEqual(workspace.b.gain, 1)
        deck.pause()
    }
    func testExactSamePCMNativeFXDifferential() async throws {
        let source = try AudioWorkspace(); try await source.prepareDefault(id: UUID())
        let loop = try XCTUnwrap(source.a.loop)
        func render(_ settings: DeckFXSettings) throws -> [Float] {
            let output = try AudioOutput(), a = try AudioLoopEngine(output: output), b = try AudioLoopEngine(output: output)
            defer { a.stop(); b.stop() }
            try output.setCrossfade(0)
            a.beginUpdate(revision: 1); try a.submit(loop: loop, revision: 1)
            try a.setFX(settings)
            output.audioEngine.stop(); try a.prepareOfflineRenderingForTests(); try a.play()
            var values: [Float] = []
            for _ in 0..<8 { values += try a.renderOfflineForTests(frameCount: 4096) }
            XCTAssertEqual(b.fxSettings, .defaults)
            return values
        }
        let dry = try render(.defaults)
        XCTAssertTrue(dry.contains { abs($0) > 0.001 })
        for kind in DeckFXSettings.Kind.allCases {
            let wet = try render(.init(kind: kind, rate: 2, depth: 0.8, feedback: 0.7, mix: 1))
            XCTAssertTrue(wet.allSatisfy(\.isFinite))
            let difference = zip(dry, wet).reduce(0.0) { $0 + Double(abs($1.0 - $1.1)) } / Double(dry.count)
            XCTAssertGreaterThan(difference, 0.001, "The exact same PCM must change through \(kind).")
        }
    }
    func testAcceptedControlsMuteStemsAndEditedLoadPreservePeer() async throws {
        let workspace = try AudioWorkspace()
        try await workspace.prepareDefault(id: UUID())
        let deck = workspace.a
        let baseline = try XCTUnwrap(deck.loop)
        let descriptor = try XCTUnwrap(deck.catalog?.descriptors.first { $0.address.parameter == .trackMute })
        try await deck.setControl(descriptor.address, value: .number(1))
        XCTAssertEqual(deck.controlValue(descriptor), 1)
        XCTAssertNotEqual(deck.loop?.pcm, baseline.pcm)
        let accepted = deck.acceptedSource, peer = workspace.b.loop
        do { try await deck.prepare(id: UUID(), source: accepted + "\n// edit"); XCTFail("Edited source requires compiler capability.") }
        catch DocumentFailure.compilerRequired { }
        XCTAssertEqual(deck.acceptedSource, accepted); XCTAssertEqual(workspace.b.loop, peer)
        let destination = FileManager.default.temporaryDirectory.appending(path: "stems-\(UUID())")
        let manifests = try await deck.export(to: destination)
        XCTAssertEqual(manifests.count, 4)
        for manifest in manifests {
            let file = try AVAudioFile(forReading: destination.appending(path: manifest.fileName))
            XCTAssertGreaterThan(file.length, 0)
            XCTAssertEqual(file.processingFormat.channelCount, 2)
        }
        try FileManager.default.removeItem(at: destination)
        let cancelledURL = destination.appending(path: "Cancelled")
        let cancelled = Task { try await deck.export(to: cancelledURL) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled export cannot succeed.") } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledURL.path))
    }
    func testNativeAcceptedControlSnapshotsNotifyObservationAndRejectInvalidChanges() throws {
        let workspace = try AudioWorkspace(), changed = Mutex(false)
        withObservationTracking { _ = workspace.a.fx } onChange: { changed.withLock { $0 = true } }
        let fx = DeckFXSettings(kind: .flanger, rate: 2, depth: 0.7, mix: 0.5)
        try workspace.a.setFX(fx)
        XCTAssertTrue(changed.withLock { $0 }); XCTAssertEqual(workspace.a.fx, fx)
        XCTAssertEqual(workspace.a.engine.fxSettings, fx); XCTAssertEqual(workspace.b.fx, .defaults)
        do { try workspace.a.setFX(.init(rate: -1)); XCTFail("Invalid native settings cannot publish.") } catch PlaybackError.invalidDeckFXSettings { }
        XCTAssertEqual(workspace.a.fx, fx)
        try workspace.a.setFXBeats(1); try workspace.a.setBPM(180)
        XCTAssertEqual(workspace.a.fx.rate, 3); XCTAssertEqual(workspace.a.engine.fxSettings.rate, 3)
        let compressor = MasterCompressorSettings(enabled: true, threshold: -24)
        try workspace.setCompressor(compressor)
        XCTAssertEqual(workspace.compressorSettings, compressor)
        XCTAssertEqual(workspace.output.compressorSettings, compressor)
        try workspace.a.setEqualizer(0, .init(frequency: 300, gain: -6))
        XCTAssertEqual(workspace.a.equalizer, workspace.a.engine.equalizerBands)
        XCTAssertEqual(workspace.b.equalizer, MasterEqualizerBand.defaults)
    }
    func testRapidIndependentControlRequestsRetainBothValues() async throws {
        let workspace = try AudioWorkspace(); try await workspace.prepareDefault(id: UUID())
        let controls = try XCTUnwrap(workspace.a.catalog).descriptors.filter { $0.address.parameter == .trackLevel }
        XCTAssertGreaterThanOrEqual(controls.count, 2)
        let first = Task { try await workspace.a.setControl(controls[0].address, value: .number(0.5)) }
        let second = Task { try await workspace.a.setControl(controls[1].address, value: .number(0.7)) }
        do { try await first.value } catch is CancellationError { }
        try await second.value
        XCTAssertEqual(workspace.a.controlValue(controls[0]), 0.5)
        XCTAssertEqual(workspace.a.controlValue(controls[1]), 0.7)
        XCTAssertEqual(workspace.a.acceptedSource, DemoMusic.source)
        XCTAssertEqual(workspace.b.controlValue(controls[0]), 1)
    }
    func testActualMasterCompressionCrossfadeVolumeAndPendingLifecycle() async throws {
        func render(crossfade: Double, volume: Double, compressor: MasterCompressorSettings, both: Bool) async throws -> ([Float], MasterCompressorSnapshot) {
            let workspace = try AudioWorkspace()
            try await workspace.prepareDefault(id: UUID())
            try workspace.setCrossfade(crossfade); try workspace.setVolume(volume)
            try workspace.output.setCompressor(compressor)
            workspace.output.audioEngine.stop()
            try workspace.a.engine.prepareOfflineRenderingForTests()
            defer { workspace.a.pause(); workspace.b.pause() }
            try workspace.a.play(); if both { try workspace.b.play() }
            var values: [Float] = []
            for _ in 0..<8 { values += try workspace.a.engine.renderOfflineForTests(frameCount: 4096) }
            return (values, workspace.output.compressorSnapshot())
        }
        func energy(_ samples: [Float]) -> Double { samples.reduce(0.0) { $0 + Double($1 * $1) } }
        let dry = try await render(crossfade: 0, volume: 1, compressor: .defaults, both: false)
        let silent = try await render(crossfade: 1, volume: 1, compressor: .defaults, both: false)
        let center = try await render(crossfade: 0.5, volume: 1, compressor: .defaults, both: true)
        let volume = try await render(crossfade: 0, volume: 0, compressor: .defaults, both: false)
        let compressed = try await render(crossfade: 0, volume: 1, compressor: .init(enabled: true, threshold: -40, ratio: 20, attackMilliseconds: 0.1), both: false)
        XCTAssertGreaterThan(energy(dry.0), 1)
        XCTAssertLessThan(energy(silent.0), 0.0001); XCTAssertLessThan(energy(volume.0), 0.0001)
        XCTAssertEqual(energy(center.0) / energy(dry.0), 2, accuracy: 0.1)
        XCTAssertLessThan(energy(compressed.0), energy(dry.0) * 0.4)
        XCTAssertGreaterThan(compressed.1.gainReduction, 1)
        XCTAssertEqual(compressed.1.inputEnvelope.count, compressed.1.outputEnvelope.count)
        XCTAssertFalse(compressed.1.inputEnvelope.isEmpty)
        let workspace = try AudioWorkspace()
        let preparation = Task { try await workspace.prepareDefault(id: UUID()) }
        await Task.yield(); try await workspace.stop()
        do { try await preparation.value; XCTFail("Cancelled preparation cannot succeed.") } catch is CancellationError { }
        XCTAssertFalse(workspace.a.isPlaying); XCTAssertFalse(workspace.b.isPlaying)
        try await workspace.prepareDefault(id: UUID())
        let start = Task { try await workspace.toggle(0) }
        await Task.yield(); try await workspace.stop()
        do { try await start.value; XCTFail("Late activation cannot start audio.") } catch is CancellationError { }
        XCTAssertFalse(workspace.a.isPlaying); XCTAssertFalse(workspace.b.isPlaying); XCTAssertFalse(workspace.sessionActive)
    }
    func testActualOutputMasterRecordingAndHardwareCueAdmission() async throws {
        let workspace = try AudioWorkspace()
        let destination = FileManager.default.temporaryDirectory.appending(path: "mix-\(UUID()).wav")
        do {
            try await workspace.prepareDefault(id: UUID())
            try await workspace.toggle(0); try await audible(workspace)
            let routes = try CueOutputDevice.available()
            XCTAssertFalse(routes.isEmpty)
            let main = try workspace.output.mainOutputDeviceID()
            XCTAssertTrue(routes.contains { $0.id == main })
            if try workspace.output.availableCueDevices().isEmpty {
                do { try workspace.output.selectCueDevice(main); XCTFail("Cue cannot use the main stereo pair.") } catch { }
                XCTAssertNil(workspace.output.cueDeviceID)
            }
            try workspace.output.startRecording(.init(destination: destination, maximumDuration: .seconds(3)))
            try await Task.sleep(for: .milliseconds(500))
            let result = try await workspace.output.stopRecording()
            XCTAssertGreaterThan(result.frameCount, 0)
            let file = try AVAudioFile(forReading: destination)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData)
            XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(samples[0][$0]) > 0.001 })
            try FileManager.default.removeItem(at: destination)
            try workspace.output.startRecording(.init(destination: destination, maximumDuration: .seconds(3)))
            try await Task.sleep(for: .milliseconds(100))
            try await workspace.output.cancelRecording()
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertFalse(workspace.output.isRecording)
            try await workspace.stop(); XCTAssertFalse(workspace.sessionActive)
        } catch {
            do { try await workspace.stop() } catch { XCTFail("Cleanup failed: \(error)") }
            throw error
        }
    }
}
