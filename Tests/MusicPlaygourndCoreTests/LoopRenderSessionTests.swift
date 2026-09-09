import Foundation
import SwiftMusic
import Synchronization
import Testing
@testable import MusicPlaygourndCore

struct LoopRenderSessionTests {
    @Test(.timeLimit(.minutes(1)))
    func mutePreparationMatchesFullGraphAcrossControlsAndConcurrentRenders() async throws {
        struct Mix: Sound {
            var body: some Sound {
                Track("Group") {
                    Track("Lead") {
                        Synthesizer(.bandLimitedSaw).notes("C4 E4").gain(0.2)
                            .effect(.chorus(rateHz: 0.5, depth: 0.4, wet: 0.3))
                    }.send(to: "shared", level: 0.5, placement: .preFader)
                    Track("Bass") { Synthesizer(.sine).notes("C2").gain(0.3) }
                        .send(to: "shared", level: 0.5, placement: .postFader)
                }
                BusReturn("shared").effect(.distortion(drive: 0.5))
            }
        }
        let sound = try SoundCompiler().compile(Mix())
        let session = try LoopRenderSession(sound: sound, bpm: 240, beatsPerBar: 4, revision: 1)
        let loader = AVAudioFileSampleLoader()
        let samples = try SamplePreparation(sound: sound, loader: loader, secondsPerBeat: 0.25)
        let oscillators = try OscillatorPreparation.prepare(sound)
        let mutes = session.catalog.descriptors.filter { $0.address.parameter == .trackMute }
        #expect(mutes.count == 3)
        let gain = try #require(session.catalog.descriptors.first {
            $0.address.target == .source(0) && $0.address.parameter == .gain
        })
        var cases: [([LiveControlOverride], PreparedLoop)] = []
        for value in [0.2, 0.4] {
            for mask in 0..<8 {
                var overrides = [LiveControlOverride(address: gain.address, value: .number(value))]
                for (index, control) in mutes.enumerated() {
                    overrides.append(.init(address: control.address, value: .number(mask & (1 << index) == 0 ? 0 : 1)))
                }
                let reference = try LoopRenderer().renderPrepared(sound, bpm: 240, beatsPerBar: 4,
                    preparedSamples: samples, preparedOscillators: oscillators,
                    overlay: RenderControlOverlay.make(overrides: overrides, catalog: session.catalog, revision: 1))
                #expect(try session.render(overrides: overrides) == reference)
                cases.append((overrides, reference))
            }
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (overrides, reference) in cases {
                group.addTask {
                    let rendered = try session.render(overrides: overrides)
                    #expect(rendered == reference)
                }
            }
            try await group.waitForAll()
        }
        #expect(try session.render() == session.baseline)
    }

    private func makeSession(revision: UInt64 = 7) throws -> LoopRenderSession {
        let sound = try SoundCompiler().compile(Synthesizer(.sine).notes("C4"))
        return try LoopRenderSession(sound: sound, bpm: 240, beatsPerBar: 4, revision: revision)
    }

    @Test(.timeLimit(.minutes(3)))
    func catalogUsesStableRevisionAndDeclarationOrder() throws {
        let session = try makeSession()
        #expect(session.catalog.descriptors.allSatisfy { $0.address.revision == 7 })
        #expect(session.catalog.descriptors.first?.address.target == .source(0))
        #expect(session.catalog.descriptors.allSatisfy { $0.address.target != .master })
        #expect(Set(session.catalog.descriptors.map(\.address)).count == session.catalog.descriptors.count)
        #expect(session.baseline.sampleRate == PreparedLoop.requiredSampleRate)
    }

    @Test(.timeLimit(.minutes(3)))
    func sourceGainOverrideChangesPCMAndReleaseRestoresBaseline() throws {
        let session = try makeSession()
        let address = try #require(session.catalog.descriptors.first {
            if case .source(0) = $0.address.target { return $0.address.parameter == .gain }
            return false
        }?.address)
        let changed = try session.render(overrides: [
            LiveControlOverride(address: address, value: .number(0.25))
        ])
        #expect(changed.events == session.baseline.events)
        #expect(changed.rows.map(\.sourceID) == session.baseline.rows.map(\.sourceID))
        #expect(changed.samples != session.baseline.samples)
        let released = try session.render(overrides: [])
        #expect(released == session.baseline)
    }

    @Test(.timeLimit(.minutes(3)))
    func duplicateAndStaleAddressesFailBeforeRendering() throws {
        let session = try makeSession()
        let address = try #require(session.catalog.descriptors.first?.address)
        let override = LiveControlOverride(address: address, value: .number(0.5))
        #expect(throws: LiveControlError.duplicateAddress(address)) {
            try session.render(overrides: [override, override])
        }
        let stale = LiveControlAddress(revision: address.revision + 1,
                                       target: address.target, parameter: address.parameter)
        #expect(throws: LiveControlError.staleRevision(expected: session.revision, actual: stale.revision)) {
            try session.render(overrides: [LiveControlOverride(address: stale, value: .number(0.5))])
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func decodedSamplesAreRetainedAcrossRenders() throws {
        let loader = CountingLoader()
        let sample = try Sample(file: URL(fileURLWithPath: "/session-fixture.wav"), rootPitch: Pitch(midiNote: 69))
        let sound = try SoundCompiler().compile(sample.notes("A4"))
        let session = try LoopRenderSession(sound: sound, bpm: 240, beatsPerBar: 4, sampleLoader: loader)
        let address = try #require(session.catalog.descriptors.first {
            if case .source(0) = $0.address.target { return $0.address.parameter == .gain }
            return false
        }?.address)
        _ = try session.render(overrides: [LiveControlOverride(address: address, value: .number(0.5))])
        _ = try session.render(overrides: [])
        #expect(loader.requests.withLock { $0.count } == 1)
    }

    @Test(.timeLimit(.minutes(3)))
    func decodedCatalogValidatesDuplicatesAndReleaseObservesCancellation() async throws {
        let session = try makeSession()
        let descriptor = try #require(session.catalog.descriptors.first)
        let wire = try PropertyListEncoder().encode(["descriptors": [descriptor, descriptor]])
        #expect(throws: LiveControlError.duplicateAddress(descriptor.address)) {
            try PropertyListDecoder().decode(LiveControlCatalog.self, from: wire)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try session.render()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private final class CountingLoader: SampleLoading {
        let requests = Mutex<[SampleLoadRequest]>([])

        func load(_ request: SampleLoadRequest) throws -> LoadedSample {
            requests.withLock { $0.append(request) }
            return try LoadedSample(samples: Array(repeating: Float(0.25), count: 4_410),
                                    channelCount: 1, sampleRate: 44_100)
        }
    }
}
