import Foundation
import Observation
import SwiftMusic

@MainActor @Observable
final class AudioDeck {
    let engine: AudioLoopEngine
    let cue: TransportCue
    private(set) var documentID: UUID?
    private(set) var acceptedSource = ""
    private(set) var loop: PreparedLoop?
    private(set) var beatPosition = 0.0
    private(set) var isPlaying = false
    private(set) var isPreparing = false
    private(set) var peaks: [Float] = []
    private(set) var samples: [Float] = []
    private(set) var spectrum: [Float] = []
    private(set) var responses: [MasterEqualizerResponse] = []
    private(set) var catalog: LiveControlCatalog?
    private(set) var overrides: [LiveControlAddress: LiveControlValue] = [:]
    private(set) var bpm = 120.0
    private(set) var gain = 1.0
    private(set) var filter = 0.0
    private(set) var reverb = 0.0
    private(set) var delay = 0.0
    private(set) var fxBeats: Double?
    var error: String?
    private var session: LoopRenderSession?
    private var pendingSession: (revision: UInt64, session: LoopRenderSession, id: UUID?, source: String)?
    private var requestedOverrides: [LiveControlAddress: LiveControlValue] = [:]
    private var pendingControls: (generation: UInt64, values: [LiveControlAddress: LiveControlValue])?
    private var preparation: Task<LoopRenderSession, any Error>?
    private var controlRender: Task<PreparedLoop, any Error>?
    private var exportTask: Task<[StemExportManifest], any Error>?
    private var revision: UInt64 = 0
    private var generation: UInt64 = 0
    private var renderGeneration: UInt64 = 0
    private var spectrumSequence: UInt64?
    private let analyzer: SpectrumAnalyzer
    private var taps = TapTempo()

    init(engine: AudioLoopEngine) throws {
        self.engine = engine; cue = TransportCue(engine: engine)
        equalizer = engine.equalizerBands; fx = engine.fxSettings; hosted = engine.audioEffectSnapshot()
        analyzer = try SpectrumAnalyzer()
        cue.onError = { [weak self] in self?.error = $0.localizedDescription }
        cue.onChange = { [weak self] in self?.refresh() }
    }
    private(set) var equalizer: [MasterEqualizerBand] = MasterEqualizerBand.defaults
    private(set) var fx = DeckFXSettings.defaults
    private(set) var hosted = HostedAudioUnitSnapshot.none
    var eventCount: Int { loop?.events.count ?? 0 }

    func prepare(id: UUID?, source: String) async throws {
        guard source == DemoMusic.source else {
            throw DocumentFailure.compilerRequired("Loading an edited Swift entry")
        }
        generation &+= 1
        let token = generation
        preparation?.cancel(); controlRender?.cancel()
        isPreparing = true
        defer { if token == generation { isPreparing = false; preparation = nil } }
        let sound = try SoundCompiler().compile(DemoMusic())
        let nextRevision = revision + 1
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try LoopRenderSession(sound: sound, bpm: 120, beatsPerBar: 4, revision: nextRevision)
        }
        preparation = task
        let candidate = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        engine.beginUpdate(revision: nextRevision)
        try engine.submit(loop: candidate.baseline, revision: nextRevision, timing: .immediate)
        revision = nextRevision
        pendingSession = (nextRevision, candidate, id, source)
        pendingControls = nil
        error = nil; refresh()
        try await waitForAdoption(revision: nextRevision, override: nil, identity: token)
    }
    func play() throws { try engine.play(); refresh() }
    func pause() { cue.release(); engine.stop(); refresh() }
    func cancelPreparation() { generation &+= 1; preparation?.cancel(); preparation = nil; controlRender?.cancel(); controlRender = nil; isPreparing = false }
    func cancelWork() async throws {
        let pendingPreparation = preparation, pendingControl = controlRender, pendingExport = exportTask
        cancelPreparation(); pendingExport?.cancel()
        var failures: [String] = []
        if let pendingPreparation { do { _ = try await pendingPreparation.value } catch is CancellationError { } catch { failures.append(error.localizedDescription) } }
        if let pendingControl { do { _ = try await pendingControl.value } catch is CancellationError { } catch { failures.append(error.localizedDescription) } }
        if let pendingExport { do { _ = try await pendingExport.value } catch is CancellationError { } catch { failures.append(error.localizedDescription) } }
        if !failures.isEmpty { throw PlaybackError.audioSetupFailed(failures.joined(separator: "\n")) }
    }
    func setBPM(_ value: Double) throws {
        guard value.isFinite, (40...240).contains(value) else { throw PlaybackError.invalidPlaybackRate(Float(value / 120)) }
        let base = loop?.bpm ?? 120
        try engine.setPlaybackRate(Float(value / base))
        if let beats = fxBeats { var next = fx; next.rate = value / 60 / beats; try setFX(next) }
        try engine.setDelayTime(seconds: 60 / value)
        bpm = value
    }
    func tap(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        if let value = taps.tap(at: time) { try setBPM(value) }
    }
    func synchronize(to peer: AudioDeck) throws {
        try engine.synchronize(to: peer.engine)
        try setBPM(peer.bpm); refresh()
    }
    func setGain(_ value: Double) throws { try engine.setDeckGain(Float(value)); gain = value }
    func setFilter(_ value: Double) throws { try engine.setDJFilter(Float(value)); filter = value }
    func setReverb(_ value: Double) throws { try engine.setReverb(mix: Float(value)); reverb = value }
    func setDelay(_ value: Double) throws { try engine.setDelay(mix: Float(value)); delay = value }
    func setEqualizer(_ index: Int, _ value: MasterEqualizerBand) throws {
        try engine.setEqualizerBand(index, value: value); equalizer = engine.equalizerBands; responses = try engine.equalizerResponses()
    }
    func setFX(_ value: DeckFXSettings) throws { try engine.setFX(value); fx = engine.fxSettings }
    func setFXBeats(_ value: Double?) throws {
        var next = fx
        if let value {
            guard value.isFinite, (0.25...4).contains(value) else { throw PlaybackError.audioSetupFailed("FX beats must be 0.25–4.") }
            next.rate = bpm / 60 / value
        }
        try setFX(next); fxBeats = value
    }
    func resetFX() throws { try setFX(.defaults); fxBeats = nil }
    func scratch(seconds: Double, duration: Double) throws { try engine.scratch(bySeconds: seconds, over: duration); refresh() }
    func releaseScratch() { engine.releaseScratch() }
    func endScratch() { engine.endScratch() }
    func controlValue(_ descriptor: LiveControlDescriptor) -> Double? {
        if case .number(let value) = overrides[descriptor.address] { return value }
        if case .scalar(let value) = descriptor.baseline { return value }
        return nil
    }
    func setControl(_ address: LiveControlAddress, value: LiveControlValue?) async throws {
        guard pendingSession == nil, let session, address.revision == revision else { throw LiveControlError.staleRevision(expected: revision, actual: address.revision) }
        guard catalog?.descriptor(for: address) != nil else { throw LiveControlError.unknownAddress(address) }
        if let value { try catalog?.validate(value: value, for: address) }
        var next = requestedOverrides; next[address] = value
        requestedOverrides = next
        renderGeneration &+= 1
        let token = renderGeneration, identity = generation
        let values = next.map { LiveControlOverride(address: $0.key, value: $0.value) }
        controlRender?.cancel()
        let task = Task.detached(priority: .userInitiated) { try session.render(overrides: values) }
        controlRender = task
        do {
            let candidate = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard identity == generation, token == renderGeneration else { throw CancellationError() }
            try engine.replace(loop: candidate, revision: revision, generation: token)
            pendingControls = (token, next); controlRender = nil; refresh()
            try await waitForAdoption(revision: revision, override: token, identity: identity)
        } catch {
            if token == renderGeneration {
                requestedOverrides = pendingControls?.values ?? overrides
                controlRender = nil
            }
            throw error
        }
    }
    func toggleMute(_ track: Int) async throws {
        guard let descriptor = catalog?.descriptors.first(where: { $0.address.target == .track(track) && $0.address.parameter == .trackMute }) else {
            throw LiveControlError.invalidCatalog("The accepted score has no matching track.")
        }
        try await setControl(descriptor.address, value: .number(controlValue(descriptor) == 1 ? 0 : 1))
    }
    func export(to url: URL) async throws -> [StemExportManifest] {
        try Task.checkCancellation()
        guard exportTask == nil else { throw PlaybackError.audioSetupFailed("A stem export is already running.") }
        guard let session else { throw PlaybackError.noCurrentLoop }
        let values = overrides.map { LiveControlOverride(address: $0.key, value: $0.value) }
        let task = Task.detached(priority: .userInitiated) {
            let stems = try session.renderStems(overrides: values)
            return try StemExporter.export(stems, to: url)
        }
        exportTask = task
        defer { exportTask = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func waitForAdoption(revision: UInt64, override: UInt64?, identity: UInt64) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            try Task.checkCancellation()
            guard identity == generation else { throw CancellationError() }
            refresh()
            let snapshot = engine.snapshot()
            if snapshot.revision == revision, override == nil || snapshot.overrideGeneration == override { return }
            guard ContinuousClock.now < deadline else {
                throw PlaybackError.audioSetupFailed("The audio callback did not adopt the submitted score in time.")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    func refresh() {
        let snapshot = engine.snapshot()
        equalizer = engine.equalizerBands; fx = engine.fxSettings; hosted = engine.audioEffectSnapshot()
        if let pending = pendingSession, snapshot.revision == pending.revision {
            session = pending.session; catalog = pending.session.catalog
            documentID = pending.id; acceptedSource = pending.source
            overrides = [:]; requestedOverrides = [:]; renderGeneration = 0; pendingSession = nil
            cue.reset()
        }
        if let pending = pendingControls, snapshot.overrideGeneration == pending.generation {
            overrides = pending.values; pendingControls = nil
        }
        beatPosition = snapshot.beatPosition; isPlaying = snapshot.isPlaying
        if let accepted = snapshot.loop, accepted != loop {
            loop = accepted
            let frames = accepted.pcm.count / 2, count = min(512, frames)
            peaks = (0..<count).map { bin in
                var peak: Float = 0
                for frame in (bin * frames / count)..<((bin + 1) * frames / count) {
                    peak = max(peak, abs(accepted.pcm[frame * 2]), abs(accepted.pcm[frame * 2 + 1]))
                }
                return peak
            }
        }
        let capture = engine.deckMeter()
        samples = capture.interleavedSamples
        if capture.sequence != spectrumSequence {
            spectrumSequence = capture.sequence
            spectrum = analyzer.analyze(interleavedSamples: samples, sampleRate: capture.sampleRate, isPlaying: isPlaying)
        }
        do { responses = try engine.equalizerResponses() }
        catch { self.error = error.localizedDescription }
    }
}
