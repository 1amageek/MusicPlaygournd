import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class AudioWorkspace {
    let output: AudioOutput
    let a: AudioDeck
    let b: AudioDeck
    private(set) var isStopping = false
    private(set) var sessionActive = false
    private(set) var masterSamples: [Float] = []
    private(set) var isRecording = false
    private(set) var compressorSettings = MasterCompressorSettings.defaults
    private(set) var compressorMeter = MasterCompressorSnapshot.empty
    private(set) var cueDeviceID: UInt32?
    private(set) var cueDecks: Set<Int> = []
    private(set) var crossfade = 0.5
    private(set) var volume = 1.0
    private(set) var balance: Float = 0
    private(set) var space = 0.0
    var error: String?
    @ObservationIgnored lazy var hosts: [DeckHost] = [a, b].map { deck in
        DeckHost(controls: deck, engine: deck.engine) { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.activate()
        }
    }
    private var activation: Task<Void, any Error>?
    private var cleanup: Task<Void, any Error>?
    private var generation: UInt64 = 0
    private(set) var route = ""

    init() throws {
        output = try AudioOutput()
        a = try AudioDeck(engine: AudioLoopEngine(output: output))
        b = try AudioDeck(engine: AudioLoopEngine(output: output))
        try output.setCrossfade(0.5)
    }
    func deck(_ index: Int) -> AudioDeck { index == 0 ? a : b }
    func prepareDefault(id: UUID?) async throws {
        let token = generation
        try await a.prepare(id: id, source: DemoMusic.source)
        guard token == generation, !isStopping else { throw CancellationError() }
        try await b.prepare(id: id, source: DemoMusic.source)
        guard token == generation, !isStopping else { throw CancellationError() }
    }
    func activate() async throws {
        guard !isStopping else { throw PlaybackError.audioSetupFailed("Wait for audio-session cleanup.") }
        if sessionActive { return }
        if let activation { try await activation.value; return }
        let token = generation
        let session = AVAudioSession.sharedInstance()
        let task = Task {
            try await Self.configureSession()
            guard try await session.activate(options: []) else { throw PlaybackError.audioSetupFailed("Audio-session activation was rejected.") }
            sessionActive = true
        }
        activation = task
        do {
            try await task.value
            guard token == generation, !isStopping else { throw CancellationError() }
            activation = nil
            try Task.checkCancellation()
            guard !session.currentRoute.outputs.isEmpty else { throw PlaybackError.audioSetupFailed("Audio output is unavailable.") }
        } catch {
            if token == generation { activation = nil }
            throw error
        }
    }
    @concurrent private static func configureSession() async throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .multiRoute { try session.setCategory(.multiRoute, mode: .default) }
    }
    func toggle(_ index: Int) async throws {
        let deck = deck(index)
        if deck.isPlaying { deck.pause(); return }
        let token = generation
        try await activate()
        guard token == generation, !isStopping else { throw CancellationError() }
        for host in hosts {
            try await host.resume()
            guard token == generation, !isStopping else { await host.suspend(); throw CancellationError() }
        }
        try deck.play(); refresh()
    }
    func stop() async throws {
        if let cleanup { try await cleanup.value; return }
        isStopping = true; generation &+= 1
        a.endScratch(); b.endScratch(); a.pause(); b.pause()
        let pendingActivation = activation
        let task = Task {
            var failures: [String] = []
            for host in hosts { await host.suspend() }
            for deck in [a, b] {
                do { try await deck.cancelWork() } catch { failures.append("Deck: \(error.localizedDescription)") }
            }
            if let pendingActivation {
                do { try await pendingActivation.value }
                catch { failures.append("Activation: \(error.localizedDescription)") }
            }
            activation = nil
            if output.isRecording {
                do { try await output.cancelRecording() }
                catch { failures.append("Recording: \(error.localizedDescription)") }
            }
            do { try output.selectCueDevice(nil) }
            catch { failures.append("Cue: \(error.localizedDescription)") }
            if sessionActive {
                do {
                    guard try await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) else {
                        throw PlaybackError.audioSetupFailed("Audio-session deactivation was rejected.")
                    }
                    sessionActive = false
                } catch { failures.append("Deactivation: \(error.localizedDescription)") }
            }
            if !failures.isEmpty { throw PlaybackError.audioSetupFailed(failures.joined(separator: "\n")) }
        }
        cleanup = task
        defer { cleanup = nil; isStopping = false; refresh() }
        try await task.value
    }
    func setCue(_ value: Bool, deck: Int) throws { try output.setCue(value, deck: deck); refresh() }
    func setCrossfade(_ value: Double) throws { try output.setCrossfade(Float(value)); crossfade = value }
    func setVolume(_ value: Double) throws { try output.setMasterVolume(Float(value)); volume = value }
    func setBalance(_ value: Float) throws { try output.setBalance(value); balance = value }
    func setSpace(_ value: Double) throws { try output.setReverb(mix: Float(value)); space = value }
    func setCompressor(_ value: MasterCompressorSettings) throws { try output.setCompressor(value); compressorSettings = output.compressorSettings }
    func refresh() {
        a.refresh(); b.refresh()
        cueDeviceID = output.cueDeviceID; cueDecks = output.cueDecks
        isRecording = output.isRecording; compressorSettings = output.compressorSettings
        let capture = output.outputMeter()
        masterSamples = capture.interleavedSamples; compressorMeter = output.compressorSnapshot()
        route = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", ")
    }
}
