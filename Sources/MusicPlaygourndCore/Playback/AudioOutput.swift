import AVFoundation
import Foundation

/// Owns the single hardware graph and post-mix recording path for up to two decks.
@MainActor
public final class AudioOutput: MasterRecording {
    internal let audioEngine = AVAudioEngine()
    internal let meterStore = OutputMeterStore()
    private let input = AVAudioMixerNode()
    private let space = AVAudioUnitReverb()
    private let balance = AVAudioMixerNode()
    public private(set) var masterBalance: Float = 0
    public private(set) var reverbMix: Float = 0
    private let compressor: AVAudioUnitEffect
    private let kernel: MasterCompressorKernel
    private let recordingCapture = MasterRecordingCapture()
    private let smoother: MasterParameterSmoother
    private var decks: [AVAudioMixerNode] = []
    private var active: Set<Int> = []
    public private(set) var masterVolume: Float = 1
    public private(set) var crossfade: Float = 0.5
    public private(set) var compressorSettings = MasterCompressorSettings.defaults
    private final class RecordingTake {
        let task: Task<MasterRecordingResult, Error>
        var cancelled = false
        var cleaned = false
        init(task: Task<MasterRecordingResult, Error>) { self.task = task }
    }
    private var recordingTake: RecordingTake?
    internal var recordingDidPublish: (@Sendable () async -> Void)?

    public convenience init() throws { try self.init(parameterSmoother: MasterParameterSmoother()) }

    internal init(parameterSmoother: MasterParameterSmoother) throws {
        smoother = parameterSmoother
        let node = MasterCompressorAudioUnit.makeNode()
        guard let unit = node.auAudioUnit as? MasterCompressorAudioUnit,
              let format = AVAudioFormat(standardFormatWithSampleRate: PreparedLoop.requiredSampleRate, channels: 2) else {
            throw PlaybackError.audioSetupFailed("Cannot create the shared audio output.")
        }
        compressor = node
        kernel = unit.kernel
        audioEngine.attach(input)
        audioEngine.attach(node)
        audioEngine.attach(space)
        audioEngine.attach(balance)
        space.loadFactoryPreset(.mediumRoom)
        space.wetDryMix = 0
        audioEngine.connect(input, to: space, format: format)
        audioEngine.connect(space, to: balance, format: format)
        audioEngine.connect(balance, to: node, format: format)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        let meter = meterStore
        let capture = recordingCapture
        audioEngine.mainMixerNode.installTap(onBus: 0,
            bufferSize: AVAudioFrameCount(OutputMeterStore.captureFrameCapacity), format: nil) { @Sendable [capture, meter] buffer, time in
            capture.capture(buffer, at: time)
            meter.capture(buffer, at: time)
        }
    }

    internal func validateAttachment() throws {
        guard decks.count < 2, !audioEngine.isRunning else {
            throw PlaybackError.audioSetupFailed("Create both decks before starting playback.")
        }
    }

    internal func attach(_ source: AVAudioNode, format: AVAudioFormat) throws -> Int {
        guard decks.count < 2, !audioEngine.isRunning else {
            throw PlaybackError.audioSetupFailed("Create both decks before starting playback.")
        }
        let mixer = AVAudioMixerNode()
        audioEngine.attach(mixer)
        audioEngine.connect(source, to: mixer, format: format)
        audioEngine.connect(mixer, to: input, fromBus: 0, toBus: AVAudioNodeBus(decks.count), format: format)
        decks.append(mixer)
        return decks.count - 1
    }

    internal func start(_ deck: Int) throws {
        if !audioEngine.isRunning {
            if !audioEngine.isInManualRenderingMode { audioEngine.prepare() }
            try audioEngine.start()
        }
        active.insert(deck)
        meterStore.activate()
    }

    internal func stop(_ deck: Int) {
        active.remove(deck)
        if active.isEmpty {
            audioEngine.stop()
            smoother.finishAll()
            meterStore.clear()
        }
    }

    public func setCrossfade(_ value: Float) throws {
        guard value.isFinite, (0...1).contains(value), decks.count == 2 else {
            throw PlaybackError.audioSetupFailed("Crossfade requires two decks and a value between 0 and 1.")
        }
        crossfade = value
        let a: Float = value == 1 ? 0 : cos(value * .pi / 2)
        let b: Float = value == 0 ? 0 : sin(value * .pi / 2)
        for (index, target) in [a, b].enumerated() {
            let mixer = decks[index]
            smoother.set(index == 0 ? .crossfadeA : .crossfadeB, from: mixer.outputVolume, to: target,
                         immediate: active.isEmpty) { value, _ in mixer.outputVolume = value }
        }
    }

    public func setMasterVolume(_ value: Float) throws {
        guard value.isFinite, (0...1).contains(value) else { throw PlaybackError.invalidMasterVolume(value) }
        masterVolume = value
        let mixer = audioEngine.mainMixerNode
        smoother.set(.volume, from: mixer.outputVolume, to: value, immediate: active.isEmpty) { value, _ in
            mixer.outputVolume = value
        }
    }

    public func setBalance(_ value: Float) throws {
        guard value.isFinite, (-1...1).contains(value) else { throw PlaybackError.invalidMasterBalance(value) }
        masterBalance = value
        let mixer = balance
        smoother.set(.balance, from: mixer.pan, to: value, immediate: active.isEmpty) { value, _ in mixer.pan = value }
    }

    public func setReverb(mix value: Float) throws {
        guard value.isFinite, (0...1).contains(value) else { throw PlaybackError.audioSetupFailed("Reverb must be between 0 and 1.") }
        reverbMix = value
        let unit = space
        smoother.set(.reverb, from: unit.wetDryMix / 100, to: value, immediate: active.isEmpty) { value, _ in unit.wetDryMix = value * 100 }
    }

    public func setCompressor(_ value: MasterCompressorSettings) throws {
        try kernel.configure(value)
        compressorSettings = value
    }
    public func compressorSnapshot() -> MasterCompressorSnapshot { active.isEmpty ? .empty : kernel.snapshot() }
    public func outputMeter() -> OutputMeterSnapshot { meterStore.snapshot() }
    public func resetDiagnostics() { meterStore.resetDiagnostics() }

    public var isRecording: Bool { recordingTake != nil }
    internal var recordingCancellationRequested: Bool { recordingTake?.cancelled ?? false }

    public func startRecording(_ request: MasterRecordingRequest) throws {
        guard recordingTake == nil else { throw MasterRecordingError.alreadyRecording }
        guard !FileManager.default.fileExists(atPath: request.destination.path) else { throw MasterRecordingError.destinationExists }
        let format = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        try recordingCapture.begin(format: format, maximumFrames: request.maximumFrames)
        do {
            let writer = try MasterRecordingWriter(request: request, capture: recordingCapture, format: format, didPublish: recordingDidPublish)
            recordingTake = RecordingTake(task: Task { try await writer.run() })
        } catch {
            recordingCapture.finish()
            throw error
        }
    }

    public func stopRecording() async throws -> MasterRecordingResult {
        guard let take = recordingTake else { throw MasterRecordingError.notRecording }
        recordingCapture.finish()
        defer { if recordingTake === take { recordingTake = nil } }
        let task = take.task
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        if take.cancelled || Task.isCancelled {
            try removeCancelledRecording(result, take: take)
            throw CancellationError()
        }
        return result
    }

    public func cancelRecording() async throws {
        guard let take = recordingTake else { return }
        take.cancelled = true
        recordingCapture.finish()
        take.task.cancel()
        defer { if recordingTake === take { recordingTake = nil } }
        do { try removeCancelledRecording(try await take.task.value, take: take) }
        catch is CancellationError { return }
    }

    private func removeCancelledRecording(_ result: MasterRecordingResult, take: RecordingTake) throws {
        guard !take.cleaned else { return }
        do {
            if FileManager.default.fileExists(atPath: result.destination.path) { try FileManager.default.removeItem(at: result.destination) }
            take.cleaned = true
        }
        catch { throw MasterRecordingError.fileFailure(error.localizedDescription) }
    }


    isolated deinit {
        recordingCapture.finish()
        recordingTake?.task.cancel()
        smoother.cancelAll()
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
}
