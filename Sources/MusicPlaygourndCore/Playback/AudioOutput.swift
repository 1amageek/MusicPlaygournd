import AVFoundation
import Foundation

/// Owns the main graph, optional headphone output, and recording for up to two decks.
@MainActor
public final class AudioOutput: MasterRecording {
    internal let audioEngine = AVAudioEngine()
    internal let meterStore = OutputMeterStore()
    private let input = AVAudioMixerNode()
    private let cueMixer = AVAudioMixerNode()
    private let cueSilentSink = AVAudioMixerNode()
    private let cueMasterSend = AVAudioMixerNode()
    private var cueSends: [AVAudioMixerNode] = []
    internal let cueOutput = CueOutput()
    public private(set) var cueDecks: Set<Int> = []
    public private(set) var cueMix: Float = 0
    public var cueDeviceID: UInt32? { cueOutput.deviceID }
    public var cueLevel: Float { cueOutput.level }

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
        for mixer in [cueMixer, cueSilentSink, cueMasterSend] { audioEngine.attach(mixer) }
        cueSilentSink.outputVolume = 0
        cueMasterSend.outputVolume = 0
        audioEngine.connect(node, to: [AVAudioConnectionPoint(node: audioEngine.mainMixerNode, bus: 0),
                                      AVAudioConnectionPoint(node: cueMasterSend, bus: 0)], fromBus: 0, format: format)
        audioEngine.connect(cueMasterSend, to: cueMixer, fromBus: 0, toBus: 2, format: format)
        audioEngine.connect(cueMixer, to: cueSilentSink, format: format)
        audioEngine.connect(cueSilentSink, to: audioEngine.mainMixerNode, fromBus: 0, toBus: 1, format: format)
        let cueBuffer = cueOutput.buffer
        cueMixer.installTap(onBus: 0, bufferSize: 512, format: format) { @Sendable [cueBuffer] buffer, _ in cueBuffer.capture(buffer) }

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
        let cueSend = AVAudioMixerNode()
        cueSend.outputVolume = 0
        audioEngine.attach(cueSend)
        audioEngine.connect(source, to: [AVAudioConnectionPoint(node: mixer, bus: 0),
                                        AVAudioConnectionPoint(node: cueSend, bus: 0)], fromBus: 0, format: format)
        audioEngine.connect(cueSend, to: cueMixer, fromBus: 0, toBus: AVAudioNodeBus(decks.count), format: format)
        cueSends.append(cueSend)
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
            cueOutput.buffer.reset(enabled: cueDeviceID != nil)
            smoother.finishAll()
            meterStore.clear()
        }
    }

    public func mainOutputDeviceID() throws -> UInt32 { try CueOutput.device(of: audioEngine) }

    public func selectMainOutput(_ id: UInt32) throws {
        let previous = try mainOutputDeviceID()
        guard previous != id else { return }
        guard !isRecording else { throw PlaybackError.audioSetupFailed("Stop recording before changing the main output.") }
        guard id != cueDeviceID, try CueOutputDevice.available().contains(where: { $0.id == id }),
              let unit = audioEngine.outputNode.audioUnit else {
            throw PlaybackError.audioSetupFailed("Choose a connected stereo main output different from the headphone output.")
        }
        let wasRunning = audioEngine.isRunning
        audioEngine.stop()
        func bind(_ device: UInt32) throws {
            var device = device
            try CueOutputDevice.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<UInt32>.size)))
            if wasRunning { try audioEngine.start() }
            guard try mainOutputDeviceID() == device else { throw PlaybackError.audioSetupFailed("Main output changed during setup.") }
        }
        do { try bind(id) }
        catch {
            let failure = error
            audioEngine.stop()
            do { try bind(previous) }
            catch { throw PlaybackError.audioSetupFailed("Main output change failed: \(failure.localizedDescription) Restoration failed: \(error.localizedDescription)") }
            throw failure
        }
    }

    public func availableCueDevices() throws -> [CueOutputDevice] {
        let main = try CueOutput.device(of: audioEngine)
        return try CueOutputDevice.available().filter { $0.id != main }
    }

    public func selectCueDevice(_ id: UInt32?) throws {
        guard id != nil else { cueOutput.stop(); return }
        try cueOutput.select(id, main: CueOutput.device(of: audioEngine))
    }

    public func validateCueDevice() throws {
        do { try cueOutput.validate(main: CueOutput.device(of: audioEngine)) }
        catch { cueOutput.stop(); throw error }
    }

    public func setCue(_ enabled: Bool, deck: Int) throws {
        guard cueSends.indices.contains(deck) else { throw PlaybackError.audioSetupFailed("Unknown cue deck.") }
        if enabled { cueDecks.insert(deck) } else { cueDecks.remove(deck) }
        updateCueMix()
    }

    public func setCueMix(_ value: Float) throws {
        guard value.isFinite, (0...1).contains(value) else { throw PlaybackError.audioSetupFailed("Cue mix must be between 0 and 1.") }
        cueMix = value
        updateCueMix()
    }

    public func setCueLevel(_ value: Float) throws {
        guard value.isFinite, (0...1).contains(value) else { throw PlaybackError.invalidMasterVolume(value) }
        cueOutput.level = value
    }

    private func updateCueMix() {
        for (index, send) in cueSends.enumerated() { send.outputVolume = cueDecks.contains(index) ? 1 - cueMix : 0 }
        cueMasterSend.outputVolume = cueMix
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
        cueOutput.stop()
        cueMixer.removeTap(onBus: 0)
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
}
