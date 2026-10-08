import AVFoundation
import CoreMIDI
import XCTest
@testable import MusicPlayground

@MainActor
final class NativeHostTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw MIDIError.invalidLoop("Native host observation timed out.") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
    func testNativeLearnNotesClockReceivedTransportAndSettings() async throws {
        let workspace = try AudioWorkspace(), probe = try NativeMIDIProbe()
        let root = FileManager.default.temporaryDirectory.appending(path: "host-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let document = root.appending(path: "Session.swift")
        try DemoMusic.source.write(to: document, atomically: true, encoding: .utf8)
        let service = try CoreMIDIService(clientName: "iPad host test")
        let host = DeckHost(controls: workspace.a, engine: workspace.a.engine, service: service,
            store: .init(directory: root.appending(path: "Settings"))) { try await workspace.activate() }
        do {
            try await workspace.prepareDefault(id: UUID())
            try await host.discover()
            let input = try probe.input, output = try probe.output
            XCTAssertTrue(host.endpoints.contains { $0.id == input && $0.direction == .input })
            let route = MIDISessionRoute(input: input, output: output, sendsLoopNotes: true, channel: 1, clockMode: .send(output: output))
            try await host.configure(route)
            let control = try XCTUnwrap(workspace.a.catalog?.descriptors.first { $0.address.parameter == .trackLevel })
            try host.beginLearn(control.address)
            try probe.inject([0x20B0077F])
            try await wait { host.bindings.count == 1 && workspace.a.controlValue(control) == 2 }
            XCTAssertEqual(workspace.a.acceptedSource, DemoMusic.source)
            try host.save(for: document)
            host.clearLearn(control.address); try await host.configure(.disabled)
            try await host.restore(for: document)
            XCTAssertEqual(host.route, route); XCTAssertEqual(host.bindings.count, 1)
            try await workspace.toggle(0)
            try await wait {
                probe.capture.words.withLock { words in
                    words.contains { ($0 >> 16) & 0xF0 == 0x90 } && words.contains { ($0 >> 16) & 0xFF == 0xF8 }
                }
            }
            XCTAssertNil(host.error)
            var received = route; received.sendsLoopNotes = false; received.clockMode = .receive(input: input)
            try await host.configure(received)
            workspace.a.pause()
            try probe.inject([0x10FA0000] + Array(repeating: 0x10F80000, count: 25),
                spacing: AVAudioTime.hostTime(forSeconds: 60 / (120 * 24)))
            try await wait { workspace.a.isPlaying && host.snapshot?.receivedClock?.pulseOrdinal == 25 }
            try probe.inject([0x10FC0000])
            try await wait { !workspace.a.isPlaying }
            XCTAssertFalse(workspace.b.isPlaying)
            await host.shutdown()
            do { _ = try await service.eventStream(); XCTFail("Closed service cannot reopen a stream.") }
            catch MIDIError.serviceShutDown { }
            try await workspace.stop()
            probe.close(); try FileManager.default.removeItem(at: root)
        } catch {
            await host.shutdown(); probe.close()
            do { try await workspace.stop() } catch { XCTFail("Cleanup: \(error)") }
            throw error
        }
    }
    func testStopCancelsLateNativeAudioUnitSelection() async throws {
        let workspace = try AudioWorkspace(); try await workspace.prepareDefault(id: UUID())
        let engine = workspace.a.engine
        let unit = try XCTUnwrap(engine.discoverAudioEffects().first {
            $0.id.componentManufacturer == kAudioUnitManufacturer_Apple && $0.id.componentSubType == kAudioUnitSubType_HighPassFilter
        })
        engine.audioUnitStart = { description, completion in
            Task { @MainActor in
                try await Task.sleep(for: .milliseconds(100))
                AudioUnitInstantiation.nativeStart(description, completion: completion)
            }
        }
        let selection = Task { try await workspace.hosts[0].selectEffect(unit.id) }
        await Task.yield(); try await workspace.stop()
        do { try await selection.value; XCTFail("Cancelled AU selection cannot succeed.") } catch is CancellationError { }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(workspace.a.hosted, .none)
        XCTAssertFalse(workspace.a.isPlaying); XCTAssertFalse(workspace.sessionActive)
        XCTAssertFalse(workspace.hosts[0].isLoadingEffect)
    }
    func testNativeAudioUnitCatalogRenderingBypassAndMissingUnit() async throws {
        func make() async throws -> AudioWorkspace {
            let workspace = try AudioWorkspace(); try await workspace.prepareDefault(id: UUID())
            try workspace.setCrossfade(0); workspace.output.audioEngine.stop()
            return workspace
        }
        func rms(_ workspace: AudioWorkspace) throws -> Double {
            try workspace.a.engine.prepareOfflineRenderingForTests(); try workspace.a.play()
            for _ in 0..<4 { _ = try workspace.a.engine.renderOfflineForTests(frameCount: 4096) }
            let values = try workspace.a.engine.renderOfflineForTests(frameCount: 4096)
            return sqrt(values.reduce(0.0) { $0 + Double($1 * $1) } / Double(values.count))
        }
        let dryWorkspace = try await make()
        let dry = try rms(dryWorkspace); dryWorkspace.a.pause()
        let workspace = try await make()
        let effects = try workspace.a.engine.discoverAudioEffects()
        XCTAssertFalse(effects.isEmpty)
        let unit = try XCTUnwrap(effects.first { $0.id.componentManufacturer == kAudioUnitManufacturer_Apple && $0.id.componentSubType == kAudioUnitSubType_HighPassFilter })
        try await workspace.hosts[0].selectEffect(unit.id)
        let state = try workspace.a.engine.captureAudioEffectState(); XCTAssertEqual(state.id, unit.id)
        workspace.output.audioEngine.stop()
        let wet = try rms(workspace)
        XCTAssertGreaterThan(dry, 0.001); XCTAssertLessThan(wet, dry * 0.9)
        try workspace.hosts[0].bypassEffect(true)
        let bypass = try rms(workspace); XCTAssertGreaterThan(bypass, wet)
        let accepted = workspace.a.hosted
        let missing = try HostedAudioUnitID(componentType: kAudioUnitType_Effect, componentSubType: 0, componentManufacturer: 0)
        do { try await workspace.a.engine.selectAudioEffect(missing); XCTFail("A missing unit cannot load.") }
        catch HostedAudioUnitError.missingComponent { }
        XCTAssertEqual(workspace.a.hosted, accepted); XCTAssertTrue(workspace.a.isPlaying)
        try await workspace.hosts[0].selectEffect(nil); XCTAssertEqual(workspace.a.hosted, .none)
        workspace.a.pause()
    }
}
