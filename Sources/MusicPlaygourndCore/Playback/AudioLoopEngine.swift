import AVFoundation
import Foundation
import Synchronization

@MainActor
public final class AudioLoopEngine: AudioUnitHosting, MasterRecording {
    private let parameterSmoother: MasterParameterSmoother
    private let audioEngine: AVAudioEngine
    private let sourceNode: AVAudioSourceNode
    private let timePitch: AVAudioUnitTimePitch
    private let balanceMixer: AVAudioMixerNode
    public let output: AudioOutput
    private let deckIndex: Int
    private var scratchOutputActive = false
    private var scratchLifecycleTask: Task<Void, Never>?
    private let deckGain = AVAudioMixerNode()
    private let deckMeterStore = OutputMeterStore()
    public var compressorSettings: MasterCompressorSettings { output.compressorSettings }
    private let equalizer: AVAudioUnitEQ
    public private(set) var masterBalance: Float = 0
    public private(set) var equalizerBands = MasterEqualizerBand.defaults
    private let delay: AVAudioUnitDelay
    private let reverb: AVAudioUnitReverb
    private let transport: AudioTransport
    internal var recordingDidPublish: (@Sendable () async -> Void)? {
        get { output.recordingDidPublish }
        set { output.recordingDidPublish = newValue }
    }
    private let meterStore: OutputMeterStore
    private let audioFormat: AVAudioFormat
    private var retainedLoops: [AudioTransport.Identity: PreparedLoop] = [:]
    private var latestRequestedRevision: UInt64?
    private var retainedSwitchLoops: [PreparedLoop] = []

    private var hostedAudioUnit: AVAudioUnit?
    private var hostedAudioDescriptor: HostedAudioUnitDescriptor?
    private var audioUnitSelection = UUID()
    private var audioUnitRequest: AudioUnitInstantiation?
    internal var audioUnitStart: AudioUnitInstantiation.Start = AudioUnitInstantiation.nativeStart
    internal var audioUnitGraphStartCheck: (() throws -> Void)?

    public convenience init() throws {
        try self.init(parameterSmoother: MasterParameterSmoother())
    }

    public convenience init(output: AudioOutput) throws {
        try self.init(parameterSmoother: MasterParameterSmoother(), output: output)
    }

    internal init(parameterSmoother: MasterParameterSmoother, output: AudioOutput? = nil) throws {
        let output = try output ?? AudioOutput(parameterSmoother: parameterSmoother)
        try output.validateAttachment()
        self.output = output
        self.parameterSmoother = parameterSmoother
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: PreparedLoop.requiredSampleRate,
            channels: 2
        ) else {
            throw PlaybackError.audioSetupFailed("Unable to create a 44.1 kHz stereo format.")
        }

        let transport = AudioTransport()
        let timePitch = AVAudioUnitTimePitch()
        let balanceMixer = AVAudioMixerNode()
        let equalizer = AVAudioUnitEQ(numberOfBands: 5)
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        let meterStore = output.meterStore

        let filter = equalizer.bands[0]
        filter.filterType = .lowPass
        filter.frequency = 1_000
        filter.bypass = true
        for (index, value) in MasterEqualizerBand.defaults.enumerated() {
            let band = equalizer.bands[index + 1]
            band.filterType = .parametric
            band.frequency = value.frequency
            band.gain = value.gain
            band.bandwidth = 1
            band.bypass = false
        }
        equalizer.bands[4].filterType = .highPass
        equalizer.bands[4].frequency = 20
        equalizer.bands[4].bypass = true
        timePitch.rate = 1
        delay.delayTime = 0.25
        delay.feedback = 30
        delay.wetDryMix = 0
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 0

        let sourceNode = AVAudioSourceNode(format: format) { @Sendable [transport, meterStore] isSilence, timestamp, frameCount, audioBufferList in
            let began = mach_absolute_time()
            let hostTime = timestamp.pointee.mFlags.contains(.hostTimeValid)
                ? timestamp.pointee.mHostTime : nil
            let status = transport.render(frameCount: Int(frameCount), audioBufferList: audioBufferList,
                                          hostTime: hostTime)
            isSilence.pointee = ObjCBool(status != noErr)
            let elapsed = AVAudioTime.seconds(forHostTime: mach_absolute_time() - began)
            meterStore.recordCallback(elapsed: elapsed,
                duration: Double(frameCount) / PreparedLoop.requiredSampleRate, failed: status != noErr)
            return status
        }
        let audioEngine = output.audioEngine
        audioEngine.attach(sourceNode)
        audioEngine.attach(timePitch)
        audioEngine.attach(balanceMixer)
        audioEngine.attach(deckGain)
        audioEngine.attach(equalizer)
        audioEngine.attach(delay)
        audioEngine.attach(reverb)
        audioEngine.connect(sourceNode, to: timePitch, format: format)
        audioEngine.connect(timePitch, to: equalizer, format: format)
        audioEngine.connect(equalizer, to: delay, format: format)
        audioEngine.connect(delay, to: reverb, format: format)
        audioEngine.connect(reverb, to: balanceMixer, format: format)
        audioEngine.connect(balanceMixer, to: deckGain, format: format)
        deckIndex = try output.attach(deckGain, format: format)
        let deckMeter = deckMeterStore
        deckGain.installTap(onBus: 0, bufferSize: 512, format: format) { @Sendable [deckMeter] buffer, time in
            deckMeter.capture(buffer, at: time)
        }
        self.transport = transport
        self.sourceNode = sourceNode
        self.timePitch = timePitch
        self.balanceMixer = balanceMixer
        self.equalizer = equalizer
        self.delay = delay
        self.reverb = reverb
        self.meterStore = meterStore
        self.audioFormat = format
        self.audioEngine = audioEngine
    }

    public var isRecording: Bool { output.isRecording }
    internal var recordingCancellationRequested: Bool { output.recordingCancellationRequested }
    public func startRecording(_ request: MasterRecordingRequest) throws { try output.startRecording(request) }
    public func stopRecording() async throws -> MasterRecordingResult { try await output.stopRecording() }
    public func cancelRecording() async throws { try await output.cancelRecording() }

    public func deckMeter() -> OutputMeterSnapshot {
        if !transport.snapshot().isPlaying && !transport.isScratching { deckMeterStore.clear() }
        return deckMeterStore.snapshot()
    }

    public func setDeckGain(_ value: Float) throws {
        guard value.isFinite, (0...1).contains(value) else { throw PlaybackError.invalidMasterVolume(value) }
        let mixer = deckGain
        parameterSmoother.set(.volume, from: mixer.outputVolume, to: value,
                              immediate: !transport.snapshot().isPlaying) { value, _ in mixer.outputVolume = value }
    }

    public func beginUpdate(revision: UInt64) {
        guard latestRequestedRevision.map({ revision > $0 }) ?? true else { return }
        latestRequestedRevision = revision
        transport.beginUpdate(revision: revision)
        pruneRetainedLoops()
    }

    public func submit(loop: PreparedLoop, revision: UInt64, timing: SourceUpdateTiming = .nextBar) throws {
        do {
            try loop.validate()
        } catch let error as PreparedLoopValidationError {
            throw PlaybackError.invalidLoop(error)
        }
        try transport.submit(loop: loop, revision: revision, timing: timing)
        retainedLoops[.init(revision: revision, generation: 0)] = loop
        pruneRetainedLoops()
    }

    /// Replaces adopted PCM without evaluating Swift or changing the musical clock.
    public func replace(loop: PreparedLoop, revision: UInt64, generation: UInt64) throws {
        do { try loop.validate() }
        catch let error as PreparedLoopValidationError { throw PlaybackError.invalidLoop(error) }
        pruneRetainedLoops()
        try transport.replace(loop: loop, revision: revision, generation: generation)
        let snapshot = transport.snapshot()
        if let index = snapshot.switchVariantIndex, retainedSwitchLoops.indices.contains(index) {
            retainedSwitchLoops[index] = loop
        }
        retainedLoops[.init(revision: revision, generation: generation,
            performanceGeneration: snapshot.performanceGeneration)] = loop
        pruneRetainedLoops()
    }

    /// Prepares all switch choices before exposing the buttons.
    public func installSwitchLoops(_ loops: [PreparedLoop], initialIndex: Int, revision: UInt64) throws {
        guard !loops.isEmpty, loops.count <= 16, loops.indices.contains(initialIndex) else {
            throw PlaybackError.incompatibleReplacement
        }
        var bytes = 0
        for loop in loops {
            do { try loop.validate() }
            catch let error as PreparedLoopValidationError { throw PlaybackError.invalidLoop(error) }
            bytes += loop.pcm.count * MemoryLayout<Float>.stride
            guard bytes <= 128 * 1024 * 1024, loop.bpm == loops[0].bpm,
                  loop.beatsPerBar == loops[0].beatsPerBar else { throw PlaybackError.incompatibleReplacement }
        }
        let current = transport.snapshot()
        guard current.loop == loops[initialIndex] else { throw PlaybackError.incompatibleReplacement }
        try transport.installSwitchLoops(loops, initialIndex: initialIndex, revision: revision,
                                         expectedGeneration: current.overrideGeneration)
        retainedSwitchLoops = loops
    }

    /// Switches already validated PCM at the current musical position.
    public func selectSwitchLoop(index: Int, revision: UInt64, generation: UInt64) throws {
        try transport.selectSwitchLoop(index: index, revision: revision, generation: generation)
    }

    /// Reserves validated PCM without changing audible state.
    public func preparePerformanceReplacement(loop: PreparedLoop, revision: UInt64,
                                               generation: UInt64) throws -> PerformanceReplacementToken {
        pruneRetainedLoops()
        let token = try transport.preparePerformanceReplacement(loop: loop, revision: revision, generation: generation)
        retainedLoops[.init(revision: revision, generation: transport.snapshot().overrideGeneration,
            performanceGeneration: generation)] = loop
        return token
    }

    /// A live reservation commits without a fallible operation or suspension.
    @discardableResult
    public func commitPerformanceReplacement(_ token: PerformanceReplacementToken) -> Bool {
        let committed = transport.commitPerformanceReplacement(token)
        pruneRetainedLoops()
        return committed
    }

    @discardableResult
    public func discardPerformanceReplacement(_ token: PerformanceReplacementToken) -> Bool {
        let discarded = transport.discardPerformanceReplacement(token)
        pruneRetainedLoops()
        return discarded
    }

    public func play() throws {
        try transport.startPlayback()
        restoreScratchRouting()
        deckMeterStore.activate()
        do {
            try output.start(deckIndex)
        } catch {
            transport.stopPlayback()
            deckMeterStore.clear()
            output.stop(deckIndex)
            throw PlaybackError.audioStartFailed(String(describing: error))
        }
    }

    public func restartFromBeginning() throws {
        try transport.restartFromBeginning()
        try play()
    }

    /// Aligns this deck's next source buffer to a running reference's audible beat clock.
    public func synchronize(to reference: AudioLoopEngine) throws {
        let anchor = try reference.playbackClockAnchor()
        guard anchor.isPlaying, let current = transport.snapshot().loop else { throw PlaybackClockError.unavailable }
        let rate = Float(anchor.beatsPerMinute / current.bpm)
        try Self.validateMasterControl(.playbackRate, value: rate)
        try transport.synchronize(to: anchor, presentationLatency: sourceNode.outputPresentationLatency)
        let unit = timePitch
        let transport = transport
        parameterSmoother.set(.rate, from: unit.rate, to: rate, immediate: true) { value, _ in
            unit.rate = value
            transport.setClockRate(unit.bypass ? 1 : Double(value))
        }
    }

    /// Auditions signed PCM motion without changing the play/pause intent.
    public func scratch(bySeconds seconds: Double, over duration: Double) throws {
        let starting = !transport.isScratching
        try transport.scratch(bySeconds: seconds, over: duration)
        guard starting else { return }
        timePitch.bypass = true
        transport.setClockRate(1)
        scratchOutputActive = true
        scratchLifecycleTask?.cancel()
        scratchLifecycleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(5)) }
                catch { return }
                guard let self else { return }
                if !self.transport.isScratching {
                    self.endScratch()
                    return
                }
            }
        }
        deckMeterStore.activate()
        do { try output.start(deckIndex) }
        catch {
            // A failed native start has no callback to finish a cancellation fade.
            transport.endScratch(immediate: true)
            endScratch()
            throw PlaybackError.audioStartFailed(String(describing: error))
        }
    }

    public func releaseScratch() { transport.releaseScratch() }

    public func endScratch() {
        transport.endScratch(immediate: !output.audioEngine.isRunning)
        guard !transport.isScratching else { return }
        restoreScratchRouting()
        if !transport.snapshot().isPlaying {
            deckMeterStore.clear()
            output.stop(deckIndex)
        }
    }

    private func restoreScratchRouting() {
        scratchLifecycleTask?.cancel()
        scratchLifecycleTask = nil
        scratchOutputActive = false
        timePitch.bypass = false
        transport.setClockRate(Double(timePitch.rate))
    }

    public func seek(bySeconds seconds: Double) throws {
        try transport.seek(bySeconds: seconds)
    }

    public func stop() {
        transport.stopPlayback()
        restoreScratchRouting()
        deckMeterStore.clear()
        output.stop(deckIndex)
        parameterSmoother.finishAll()
        pruneRetainedLoops()
    }

    public func snapshot() -> PlaybackSnapshot {
        if scratchOutputActive && !transport.isScratching { endScratch() }
        let position = transport.positionSnapshot()
        let rawSnapshot = position.playback
        pruneRetainedLoops()
        guard rawSnapshot.isPlaying, !transport.isScratching,
              let loop = rawSnapshot.loop else {
            return rawSnapshot
        }

        // The source node reports the complete downstream presentation latency.
        // Do not add individual effect latencies a second time. Unknown or invalid
        // metadata is excluded explicitly and leaves the transport position intact.
        let latency = sourceNode.outputPresentationLatency
        guard latency.isFinite, latency > 0 else { return rawSnapshot }
        let correction = latency * loop.bpm / 60 * Double(timePitch.rate)
        guard correction.isFinite, correction >= 0 else { return rawSnapshot }
        return PlaybackSnapshot(
            loop: rawSnapshot.loop,
            revision: rawSnapshot.revision,
            beatPosition: AudioTransport.correctedLocalBeatPosition(
                accumulatedBeatPosition: position.accumulatedBeatPosition,
                loopBeatCount: loop.beatCount,
                correction: correction
            ),
            isPlaying: rawSnapshot.isPlaying,
            overrideGeneration: rawSnapshot.overrideGeneration,
            performanceGeneration: rawSnapshot.performanceGeneration,
            switchVariantIndex: rawSnapshot.switchVariantIndex
        )
    }

    public func playbackClockAnchor() throws -> PlaybackClockAnchor {
        try transport.clockAnchor(presentationLatency: sourceNode.outputPresentationLatency)
    }

    /// Checks native master admission without changing the audio graph or parameter targets.
    public static func validateMasterControl(_ parameter: LiveControlParameter, value: Float) throws {
        switch parameter {
        case .playbackRate:
            guard value.isFinite, (1.0 / 32.0...32.0).contains(value) else { throw PlaybackError.invalidPlaybackRate(value) }
        case .lowPassCutoff:
            guard value.isFinite, (20...20_000).contains(value) else { throw PlaybackError.invalidLowPassCutoff(value) }
        case .delayMix:
            guard value.isFinite, (0...1).contains(value) else { throw PlaybackError.invalidDelayMix(value) }
        case .reverbMix:
            guard value.isFinite, (0...1).contains(value) else { throw PlaybackError.invalidReverbMix(value) }
        default: throw LiveControlError.invalidCatalog("Unsupported native master parameter")
        }
    }

    public func setPlaybackRate(_ rate: Float) throws {
        try Self.validateMasterControl(.playbackRate, value: rate)
        let unit = timePitch
        let transport = transport
        parameterSmoother.set(.rate, from: unit.rate, to: rate,
                              immediate: !transport.snapshot().isPlaying) { value, _ in
            unit.rate = value
            transport.setClockRate(unit.bypass ? 1 : Double(value))
        }
    }

    public func setLowPass(cutoff: Float?) throws {
        if let cutoff { try Self.validateMasterControl(.lowPassCutoff, value: cutoff) }
        let filter = equalizer.bands[0]
        let disabling = cutoff == nil
        let immediate = !transport.snapshot().isPlaying || (disabling && filter.bypass)
        if !disabling, filter.bypass {
            filter.frequency = 20_000
            filter.bypass = false
        }
        parameterSmoother.set(.lowPass, from: filter.frequency, to: cutoff ?? 20_000,
                              immediate: immediate) { value, final in
            filter.frequency = value
            filter.bypass = disabling && final
        }
    }

    public func setDJFilter(_ value: Float) throws {
        guard value.isFinite, (-1...1).contains(value) else { throw PlaybackError.invalidDJFilter(value) }
        try setLowPass(cutoff: value < 0 ? 20_000 * pow(1_000, value) : nil)
        let filter = equalizer.bands[4]
        let disabling = value <= 0
        if !disabling, filter.bypass { filter.frequency = 20; filter.bypass = false }
        parameterSmoother.set(.highPass, from: filter.frequency, to: disabling ? 20 : 20 * pow(1_000, value),
                              immediate: !transport.snapshot().isPlaying) { frequency, final in
            filter.frequency = frequency
            filter.bypass = disabling && final
        }
    }

    public func setDelayTime(seconds: Double) throws {
        guard seconds.isFinite, (0.01...2).contains(seconds) else { throw PlaybackError.invalidDelayTime(seconds) }
        delay.delayTime = seconds
    }

    internal var delayTimeForTests: Double { delay.delayTime }

    public func setEqualizerBand(_ index: Int, value: MasterEqualizerBand) throws {
        guard equalizerBands.indices.contains(index), value.frequency.isFinite,
              (20...20_000).contains(value.frequency), value.gain.isFinite,
              (-12...12).contains(value.gain), value.q.isFinite, (0.2...20).contains(value.q) else { throw PlaybackError.invalidEqualizerBand }
        let band = equalizer.bands[index + 1]
        let frequencyKeys: [MasterParameterSmoother.Parameter] = [.eqLowFrequency, .eqMidFrequency, .eqHighFrequency]
        let bandwidthKeys: [MasterParameterSmoother.Parameter] = [.eqLowBandwidth, .eqMidBandwidth, .eqHighBandwidth]
        let gainKeys: [MasterParameterSmoother.Parameter] = [.eqLowGain, .eqMidGain, .eqHighGain]
        let immediate = !transport.snapshot().isPlaying
        equalizerBands[index] = value
        parameterSmoother.set(frequencyKeys[index], from: band.frequency, to: value.frequency,
                              immediate: immediate) { value, _ in band.frequency = value }
        parameterSmoother.set(gainKeys[index], from: band.gain, to: value.gain,
                              immediate: immediate) { value, _ in band.gain = value }
        let bandwidth = Float(2 * asinh(1 / (2 * Double(value.q))) / log(2))
        parameterSmoother.set(bandwidthKeys[index], from: band.bandwidth, to: bandwidth,
                              immediate: immediate) { value, _ in band.bandwidth = value }
    }

    public func equalizerResponses() throws -> [MasterEqualizerResponse] {
        if !equalizer.auAudioUnit.renderResourcesAllocated { audioEngine.prepare() }
        var coefficients = [Double](repeating: 0, count: 25)
        var size = UInt32(coefficients.count * MemoryLayout<Double>.stride)
        // The native call borrows this owned, contiguous buffer synchronously and does not retain it.
        let status = coefficients.withUnsafeMutableBytes { bytes in
            AudioUnitGetProperty(equalizer.audioUnit, kAUNBandEQProperty_BiquadCoefficients,
                                 kAudioUnitScope_Global, 0, bytes.baseAddress!, &size)
        }
        guard status == noErr else { throw PlaybackError.equalizerResponseFailed(status) }
        guard size == 25 * MemoryLayout<Double>.stride, coefficients.allSatisfy({ $0.isFinite }) else {
            throw PlaybackError.equalizerResponseFailed(kAudioUnitErr_InvalidPropertyValue)
        }
        return (1...3).map { index in
            let offset = index * 5
            // AUNBandEQ returns a1, a2, b0, b1, b2 for each band.
            return MasterEqualizerResponse(b0: coefficients[offset + 2], b1: coefficients[offset + 3],
                b2: coefficients[offset + 4], a1: coefficients[offset], a2: coefficients[offset + 1])
        }
    }

    public func setDelay(mix: Float) throws {
        try Self.validateMasterControl(.delayMix, value: mix)
        let unit = delay
        parameterSmoother.set(.delay, from: unit.wetDryMix / 100, to: mix,
                              immediate: !transport.snapshot().isPlaying) { value, _ in
            unit.wetDryMix = value * 100
        }
    }

    public func setMasterBalance(_ balance: Float) throws {
        guard balance.isFinite, (-1...1).contains(balance) else {
            throw PlaybackError.invalidMasterBalance(balance)
        }
        masterBalance = balance
        let mixer = balanceMixer
        parameterSmoother.set(.balance, from: mixer.pan, to: balance,
                              immediate: !transport.snapshot().isPlaying) { value, _ in
            mixer.pan = value
        }
    }

    public func setMasterVolume(_ volume: Float) throws { try output.setMasterVolume(volume) }

    public func setReverb(mix: Float) throws {
        try Self.validateMasterControl(.reverbMix, value: mix)
        let unit = reverb
        parameterSmoother.set(.reverb, from: unit.wetDryMix / 100, to: mix,
                              immediate: !transport.snapshot().isPlaying) { value, _ in
            unit.wetDryMix = value * 100
        }
    }

    internal var masterParametersForTests: (rate: Float, lowPass: Float?, delay: Float, reverb: Float) {
        let filter = equalizer.bands[0]
        return (timePitch.rate, filter.bypass ? nil : filter.frequency,
                delay.wetDryMix / 100, reverb.wetDryMix / 100)
    }

    public func setCompressor(_ value: MasterCompressorSettings) throws { try output.setCompressor(value) }
    public func compressorSnapshot() -> MasterCompressorSnapshot { output.compressorSnapshot() }
    public func resetDiagnostics() { output.resetDiagnostics() }
    public func outputMeter() -> OutputMeterSnapshot { output.outputMeter() }

    /// Enables native offline rendering for focused Core tests without changing the public app API.
    internal func prepareOfflineRenderingForTests() throws {
        guard !audioEngine.isInManualRenderingMode else { return }
        guard !audioEngine.isRunning else {
            throw PlaybackError.offlineRenderingFailed("The engine must be stopped before manual rendering setup.")
        }
        do {
            try audioEngine.enableManualRenderingMode(
                .offline,
                format: audioFormat,
                maximumFrameCount: AVAudioFrameCount(OutputMeterStore.captureFrameCapacity * 2)
            )
        } catch {
            throw PlaybackError.offlineRenderingFailed(String(describing: error))
        }
    }

    /// Renders the native effect graph into a test-owned interleaved buffer.
    internal func renderOfflineForTests(frameCount: Int) throws -> [Float] {
        guard (1...(OutputMeterStore.captureFrameCapacity * 2)).contains(frameCount) else {
            throw PlaybackError.offlineRenderingFailed("Offline frame count is outside the bounded test range.")
        }
        try prepareOfflineRenderingForTests()
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                throw PlaybackError.offlineRenderingFailed(String(describing: error))
            }
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw PlaybackError.offlineRenderingFailed("Unable to allocate the offline render buffer.")
        }
        do {
            let status = try audioEngine.renderOffline(AVAudioFrameCount(frameCount), to: buffer)
            guard status == .success else {
                throw PlaybackError.offlineRenderingFailed("Native renderer returned \(status).")
            }
        } catch let error as PlaybackError {
            throw error
        } catch {
            throw PlaybackError.offlineRenderingFailed(String(describing: error))
        }

        // AVAudioEngine does not invoke mixer taps for every offline configuration. The
        // returned buffer is the post-mixer render output, so use it to keep the test-only
        // monitor path tied to the same native effect graph when the tap is silent offline.
        meterStore.capture(buffer)

        let renderedFrames = min(Int(buffer.frameLength), frameCount)
        var output = [Float](repeating: 0, count: renderedFrames * 2)
        if audioFormat.isInterleaved {
            if let data = buffer.audioBufferList.pointee.mBuffers.mData {
                let samples = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<renderedFrames {
                    output[frame * 2] = samples[frame * 2]
                    output[frame * 2 + 1] = samples[frame * 2 + 1]
                }
            }
        } else if let channels = buffer.floatChannelData {
            for frame in 0..<renderedFrames {
                output[frame * 2] = channels[0][frame]
                output[frame * 2 + 1] = channels[1][frame]
            }
        }
        return output
    }

    public func discoverAudioEffects() throws -> [HostedAudioUnitDescriptor] {
        try AudioUnitCatalog.discover()
    }

    public func selectAudioEffect(_ id: HostedAudioUnitID, restoring state: HostedAudioUnitState? = nil) async throws {
        if let state, state.id != id { throw HostedAudioUnitError.stateIdentityMismatch }
        guard let descriptor = try discoverAudioEffects().first(where: { $0.id == id }) else {
            throw HostedAudioUnitError.missingComponent
        }
        audioUnitRequest?.cancel()
        let selection = UUID()
        audioUnitSelection = selection
        let request = AudioUnitInstantiation()
        audioUnitRequest = request
        defer { if audioUnitSelection == selection { audioUnitRequest = nil } }
        let candidate = try await request.value(for: id.componentDescription, start: audioUnitStart)
        try Task.checkCancellation()
        guard audioUnitSelection == selection else { throw HostedAudioUnitError.superseded }
        let nativeID = candidate.audioComponentDescription
        guard nativeID.componentType == id.componentType,
              nativeID.componentSubType == id.componentSubType,
              nativeID.componentManufacturer == id.componentManufacturer else {
            throw HostedAudioUnitError.instantiationFailed("The native component identity did not match the selection.")
        }
        let unit = candidate.auAudioUnit
        if let state { unit.fullStateForDocument = try state.propertyList() }
        guard unit.inputBusses.count > 0, unit.outputBusses.count > 0 else {
            throw HostedAudioUnitError.incompatibleFormat("An input and an output bus are required.")
        }
        guard unit.latency.isFinite, unit.latency >= 0, unit.tailTime.isFinite, unit.tailTime >= 0 else {
            throw HostedAudioUnitError.invalidLatency
        }
        do {
            try unit.inputBusses[0].setFormat(audioFormat)
            try unit.outputBusses[0].setFormat(audioFormat)
        } catch { throw HostedAudioUnitError.incompatibleFormat(error.localizedDescription) }
        try swapAudioEffect(candidate)
        hostedAudioDescriptor = descriptor
    }

    public func clearAudioEffect() throws {
        audioUnitSelection = UUID()
        audioUnitRequest?.cancel()
        audioUnitRequest = nil
        guard hostedAudioUnit != nil else { return }
        try swapAudioEffect(nil)
        hostedAudioDescriptor = nil
    }

    public func setAudioEffectBypassed(_ bypassed: Bool) throws {
        guard let unit = hostedAudioUnit else { throw HostedAudioUnitError.notLoaded }
        unit.auAudioUnit.shouldBypassEffect = bypassed
        transport.invalidateClock()
    }

    public func captureAudioEffectState() throws -> HostedAudioUnitState {
        guard let unit = hostedAudioUnit, let descriptor = hostedAudioDescriptor else {
            throw HostedAudioUnitError.notLoaded
        }
        return try HostedAudioUnitState(id: descriptor.id, documentState: unit.auAudioUnit.fullStateForDocument)
    }

    public func audioEffectSnapshot() -> HostedAudioUnitSnapshot {
        guard let unit = hostedAudioUnit, let descriptor = hostedAudioDescriptor else { return .none }
        return .loaded(descriptor: descriptor, bypassed: unit.auAudioUnit.shouldBypassEffect)
    }

    private func swapAudioEffect(_ candidate: AVAudioUnit?) throws {
        let previous = hostedAudioUnit
        let wasRunning = audioEngine.isRunning
        audioEngine.stop()
        transport.invalidateClock()
        audioEngine.disconnectNodeOutput(reverb)
        if let previous { audioEngine.disconnectNodeOutput(previous) }
        if let candidate { audioEngine.attach(candidate) }
        connectAudioEffect(candidate)
        do {
            if wasRunning {
                try audioUnitGraphStartCheck?()
                if !audioEngine.isInManualRenderingMode { audioEngine.prepare() }
                try audioEngine.start()
            }
        } catch {
            audioEngine.stop()
            audioEngine.disconnectNodeOutput(reverb)
            if let candidate { audioEngine.detach(candidate) }
            connectAudioEffect(previous)
            do {
                if wasRunning {
                    try audioUnitGraphStartCheck?()
                    if !audioEngine.isInManualRenderingMode { audioEngine.prepare() }
                    try audioEngine.start()
                }
            } catch let rollback {
                transport.stopPlayback()
                meterStore.clear()
                throw HostedAudioUnitError.rollbackFailed(error.localizedDescription, rollback.localizedDescription)
            }
            throw HostedAudioUnitError.graphFailed(error.localizedDescription)
        }
        if let previous { audioEngine.detach(previous) }
        hostedAudioUnit = candidate
    }

    private func connectAudioEffect(_ unit: AVAudioUnit?) {
        // Bus formats and node ownership are admitted before these native precondition operations.
        if let unit {
            audioEngine.connect(reverb, to: unit, format: audioFormat)
            audioEngine.connect(unit, to: balanceMixer, format: audioFormat)
        } else {
            audioEngine.connect(reverb, to: balanceMixer, format: audioFormat)
        }
    }

    private func pruneRetainedLoops() {
        let retained = Set(transport.drainRetiredAndRetainedIdentities())
        retainedLoops = retainedLoops.filter { retained.contains($0.key) }
        if transport.snapshot().switchVariantIndex == nil { retainedSwitchLoops.removeAll() }
    }

    isolated deinit {
        scratchLifecycleTask?.cancel()
        audioUnitRequest?.cancel()
        parameterSmoother.cancelAll()
        transport.stopPlayback()
        output.stop(deckIndex)
    }
}

// The callback crosses AVFAudio's render thread. Its only mutable field is Mutex-protected,
// and callback-local buffer borrows never escape this method.
final class AudioTransport: Sendable {
    struct Identity: Sendable, Hashable {
        let revision: UInt64
        let generation: UInt64
        var performanceGeneration: UInt64 = 0
    }

    static let crossfadeFrames = 1_323

    struct PositionSnapshot {
        let playback: PlaybackSnapshot
        let accumulatedBeatPosition: Double
    }

    private struct Candidate: Sendable {
        let loop: PreparedLoop
        let revision: UInt64
        var generation: UInt64 = 0
        var performanceGeneration: UInt64 = 0
        var switchIndex: Int? = nil
        var identity: Identity { Identity(revision: revision, generation: generation, performanceGeneration: performanceGeneration) }
    }

    private struct Fade: Sendable {
        let old: Candidate
        var elapsed = 0
        // Source fades retain an independent old clock, including across tempo/length edits.
        var oldBeatPosition: Double?
    }

    private struct ClockSample: Sendable {
        let hostTime: UInt64
        let beat: Double
    }

    private struct Scratch: Sendable {
        var step: Double
        var targetStep: Double
        var position: Double
        var targetPosition: Double
        var remaining: Int?
        var decay: Double
        var gain: Float
        var entryFrame: Int?
        var entryElapsed = 0
        var handStep: Double
        var motionAgeFrames = 0
        var launchFrames = 0
        let transitionFrames: Int
        let gainDecay: Float
    }

    private struct State: Sendable {
        var switchLoops: [PreparedLoop] = []
        var switchRevision: UInt64?
        var currentSwitchIndex: Int?
        var publishedSwitchIndex: Int?
        var current: PreparedLoop?
        var currentRevision: UInt64?
        var currentPerformanceGeneration: UInt64 = 0
        var publishedPerformanceGeneration: UInt64 = 0
        var latestPerformanceGeneration: UInt64 = 0
        var reservation: (token: PerformanceReplacementToken, candidate: Candidate)?
        var currentGeneration: UInt64 = 0
        var latestGeneration: UInt64 = 0
        var replacement: Candidate?
        var fade: Fade?
        var retired: Candidate?
        var pending: Candidate?
        var latestRevision: UInt64?
        var submittedRevision: UInt64?
        var beatPosition = 0.0
        var framePosition = 0
        var pendingBoundary: Double?
        var pendingTiming: SourceUpdateTiming = .nextBar
        var scratch: Scratch?
        var isPlaying = false
        var clockSample: ClockSample?
        var lastHostTime: UInt64?
        var clockDiscontinuous = false
        var clockRate = 1.0
        var synchronization: (anchor: PlaybackClockAnchor, latency: UInt64)?
    }

    private let state = Mutex(State())
    private let scratchResampler = ScratchResampler()

    /// Called only off callback. The engine keeps every returned immutable buffer alive.
    func drainRetiredAndRetainedIdentities() -> [Identity] {
        state.withLock { state in
            state.retired = nil
            if state.switchRevision != state.currentRevision {
                state.switchLoops.removeAll()
                state.switchRevision = nil
            }
            var identities: [Identity] = []
            if let revision = state.currentRevision {
                identities.append(Identity(revision: revision, generation: state.currentGeneration, performanceGeneration: state.currentPerformanceGeneration))
            }
            if let reservation = state.reservation { identities.append(reservation.candidate.identity) }
            if let pending = state.pending { identities.append(pending.identity) }
            if let replacement = state.replacement { identities.append(replacement.identity) }
            if let fade = state.fade { identities.append(fade.old.identity) }
            return identities
        }
    }

    func installSwitchLoops(_ loops: [PreparedLoop], initialIndex: Int, revision: UInt64, expectedGeneration: UInt64 = 0) throws {
        try state.withLock { state in
            guard state.currentRevision == revision else { throw PlaybackError.staleRevision(revision) }
            guard loops.indices.contains(initialIndex), state.currentPerformanceGeneration == 0 else { throw PlaybackError.incompatibleReplacement }
            guard state.scratch == nil, state.currentGeneration == expectedGeneration, state.fade == nil,
                  state.replacement == nil, state.pending == nil, state.reservation == nil else {
                throw PlaybackError.replacementInProgress
            }
            state.switchLoops = loops
            state.switchRevision = revision
            state.currentSwitchIndex = initialIndex
            state.publishedSwitchIndex = initialIndex
        }
    }

    func selectSwitchLoop(index: Int, revision: UInt64, generation: UInt64) throws {
        try state.withLock { state in
            guard state.currentRevision == revision, state.switchRevision == revision else {
                throw PlaybackError.staleRevision(revision)
            }
            guard state.switchLoops.indices.contains(index), state.currentPerformanceGeneration == 0 else { throw PlaybackError.incompatibleReplacement }
            guard generation > state.latestGeneration else { throw PlaybackError.staleOverrideGeneration(generation) }
            guard state.scratch == nil, state.reservation == nil, state.pending == nil,
                  state.currentPerformanceGeneration == state.publishedPerformanceGeneration else {
                throw PlaybackError.replacementInProgress
            }
            state.latestGeneration = generation
            let candidate = Candidate(loop: state.switchLoops[index], revision: revision,
                                      generation: generation, switchIndex: index)
            if !state.isPlaying {
                state.synchronization = nil
        state.current = candidate.loop
                state.currentGeneration = generation
                state.currentSwitchIndex = index
                state.publishedSwitchIndex = index
                state.framePosition = frame(for: state.beatPosition, in: candidate.loop)
                state.clockSample = nil
            } else {
                state.replacement = candidate
            }
        }
    }

    func preparePerformanceReplacement(loop: PreparedLoop, revision: UInt64,
                                       generation: UInt64) throws -> PerformanceReplacementToken {
        do { try loop.validate() }
        catch let error as PreparedLoopValidationError { throw PlaybackError.invalidLoop(error) }
        return try state.withLock { state in
            guard state.currentRevision == revision else { throw PlaybackError.staleRevision(revision) }
            guard generation > state.latestPerformanceGeneration else {
                throw PlaybackError.staleOverrideGeneration(generation)
            }
            guard state.scratch == nil, state.reservation == nil, state.fade == nil, state.pending == nil,
                  state.replacement == nil, state.retired == nil else {
                throw PlaybackError.replacementInProgress
            }
            let token = PerformanceReplacementToken()
            let candidate = Candidate(loop: loop, revision: revision,
                generation: state.currentGeneration, performanceGeneration: generation)
            state.reservation = (token, candidate)
            state.latestPerformanceGeneration = generation
            return token
        }
    }

    @discardableResult
    func commitPerformanceReplacement(_ token: PerformanceReplacementToken) -> Bool {
        state.withLock { state in
            guard let reservation = state.reservation, reservation.token == token else { return false }
            state.reservation = nil
            if state.isPlaying {
                beginFade(reservation.candidate, into: &state)
            } else {
                state.current = reservation.candidate.loop
                state.currentPerformanceGeneration = reservation.candidate.performanceGeneration
                state.publishedPerformanceGeneration = state.currentPerformanceGeneration
                state.framePosition = frame(for: state.beatPosition, in: reservation.candidate.loop)
                state.clockSample = nil
            }
            return true
        }
    }

    @discardableResult
    func discardPerformanceReplacement(_ token: PerformanceReplacementToken) -> Bool {
        state.withLock { state in
            guard state.reservation?.token == token else { return false }
            state.reservation = nil
            return true
        }
    }

    func replace(loop: PreparedLoop, revision: UInt64, generation: UInt64) throws {
        try state.withLock { state in
            guard state.currentRevision == revision, let current = state.current else {
                throw PlaybackError.staleRevision(revision)
            }
            guard generation > state.latestGeneration else {
                throw PlaybackError.staleOverrideGeneration(generation)
            }
            guard state.scratch == nil, state.reservation == nil,
                  state.currentPerformanceGeneration == state.publishedPerformanceGeneration else {
                throw PlaybackError.replacementInProgress
            }
            guard Self.sameShape(current, loop) else { throw PlaybackError.incompatibleReplacement }
            state.latestGeneration = generation
            let candidate = Candidate(loop: loop, revision: revision, generation: generation,
                performanceGeneration: state.currentPerformanceGeneration, switchIndex: state.currentSwitchIndex)
            if let index = state.currentSwitchIndex, state.switchRevision == revision {
                state.switchLoops[index] = loop
            }
            if !state.isPlaying {
                state.current = loop
                state.currentGeneration = generation
                state.clockSample = nil
                state.fade = nil
                state.retired = nil
                state.replacement = nil
            } else if state.fade == nil, state.retired == nil {
                beginFade(candidate, into: &state)
            } else {
                state.replacement = candidate
            }
        }
    }

    private static func sameShape(_ lhs: PreparedLoop, _ rhs: PreparedLoop) -> Bool {
        guard lhs.sampleRate == rhs.sampleRate, lhs.bpm == rhs.bpm,
              lhs.beatsPerBar == rhs.beatsPerBar, lhs.beatCount == rhs.beatCount,
              lhs.pcm.count == rhs.pcm.count,
              lhs.events.count == rhs.events.count, lhs.rows.count == rhs.rows.count else { return false }
        for (a, b) in zip(lhs.events, rhs.events) {
            guard a.sourceID == b.sourceID, a.label == b.label, a.startBeat == b.startBeat,
                  a.velocity == b.velocity, a.patternStepIndex == b.patternStepIndex else { return false }
        }
        for (a, b) in zip(lhs.rows, rhs.rows) {
            guard a.sourceID == b.sourceID, a.label == b.label, a.anchor == b.anchor,
                  a.patternText == b.patternText, a.resultLine == b.resultLine else { return false }
        }
        return true
    }

    private func beginFade(_ candidate: Candidate, into state: inout State) {
        guard let current = state.current, let revision = state.currentRevision else { return }
        state.fade = Fade(old: Candidate(loop: current, revision: revision, generation: state.currentGeneration,
            performanceGeneration: state.currentPerformanceGeneration, switchIndex: state.currentSwitchIndex))
        state.synchronization = nil
        state.current = candidate.loop
        state.currentGeneration = candidate.generation
        state.currentPerformanceGeneration = candidate.performanceGeneration
        state.currentSwitchIndex = candidate.switchIndex
        state.clockSample = nil
        state.replacement = nil
    }

    func beginUpdate(revision: UInt64) {
        state.withLock { state in
            guard state.latestRevision.map({ revision > $0 }) ?? true else { return }
            state.latestRevision = revision
            state.submittedRevision = nil
            state.pending = nil
            state.pendingBoundary = nil
        }
    }

    func submit(loop: PreparedLoop, revision: UInt64, timing: SourceUpdateTiming = .nextBar) throws {
        try state.withLock { state in
            guard state.latestRevision == revision else {
                throw state.latestRevision.map { _ in PlaybackError.staleRevision(revision) }
                    ?? PlaybackError.updateNotStarted(revision)
            }
            guard state.submittedRevision != revision else {
                throw PlaybackError.duplicateRevision(revision)
            }

            guard state.scratch == nil, state.reservation == nil,
                  state.currentPerformanceGeneration == state.publishedPerformanceGeneration else {
                throw PlaybackError.replacementInProgress
            }
            state.submittedRevision = revision
            let candidate = Candidate(loop: loop, revision: revision)
            if state.current == nil {
                state.current = loop
                state.currentRevision = revision
                state.pending = nil
                state.framePosition = 0
            } else {
                state.pending = candidate
                state.pendingTiming = timing
                if state.isPlaying, let current = state.current {
                    state.pendingBoundary = timing.boundary(after: state.beatPosition, beatsPerBar: current.beatsPerBar)
                }
            }
        }
    }

    func startPlayback() throws {
        try state.withLock { state in
            guard state.current != nil || state.pending != nil else {
                throw PlaybackError.noCurrentLoop
            }
            if let pending = state.pending, !state.isPlaying, state.reservation == nil {
                adopt(pending, into: &state)
            }
            if !state.isPlaying {
                state.clockSample = nil
                state.lastHostTime = nil
                state.clockDiscontinuous = false
            }
            state.scratch = nil
            state.isPlaying = true
        }
    }

    func restartFromBeginning() throws {
        try state.withLock { state in
            guard let current = state.current else { throw PlaybackError.noCurrentLoop }
            state.synchronization = nil
            state.framePosition = 0
            state.beatPosition = 0
            state.clockSample = nil
            state.lastHostTime = nil
            state.clockDiscontinuous = false
            state.pendingBoundary = state.pending == nil ? nil : state.pendingTiming.boundary(after: 0, beatsPerBar: current.beatsPerBar)
            state.scratch = nil
            state.isPlaying = true
        }
    }

    var isScratching: Bool { state.withLock { $0.scratch != nil } }

    func scratch(bySeconds seconds: Double, over duration: Double) throws {
        guard seconds.isFinite, duration.isFinite, duration > 0, duration <= 0.25 else {
            throw PlaybackError.invalidScratchMotion
        }
        try state.withLock { state in
            guard let current = state.current else { throw PlaybackError.noCurrentLoop }
            guard state.reservation == nil, state.replacement == nil, state.fade == nil,
                  state.pending == nil else { throw PlaybackError.replacementInProgress }
            let sourceRate = current.sampleRate
            let baseStep = deltaBeatFor(current)
            let requestedStep = seconds / duration * baseStep
            let readSpeed = requestedStep * Double(current.pcm.count / 2) / current.beatCount
            let previous = state.scratch
            let anchor = previous.map { $0.remaining == nil ? $0.targetPosition : $0.position } ?? state.beatPosition
            let target = anchor + seconds * current.bpm / 60
            guard readSpeed.isFinite, target.isFinite else { throw PlaybackError.invalidScratchMotion }
            // Hand displacement is authoritative; only audible speed is bounded for DSP work.
            let limit = ScratchResampler.maximumSpeed * current.beatCount / Double(current.pcm.count / 2)
            let step = min(limit, max(-limit, requestedStep))
            let transitionFrames = max(2, Int(0.005 * sourceRate))
            let decay = exp(-1 / (0.005 * sourceRate))
            if var scratch = previous {
                if step != 0 || scratch.remaining != nil {
                    scratch.handStep = step
                    scratch.motionAgeFrames = 0
                }
                scratch.launchFrames = 0
                scratch.targetStep = step
                scratch.targetPosition = target
                scratch.remaining = nil
                scratch.decay = decay
                state.scratch = scratch
            } else {
                state.scratch = Scratch(step: state.isPlaying ? baseStep : 0,
                    targetStep: step, position: state.beatPosition, targetPosition: target, decay: decay,
                    gain: state.isPlaying ? 1 : 0, entryFrame: state.isPlaying ? state.framePosition : nil,
                    handStep: step, transitionFrames: transitionFrames, gainDecay: Float(1 - decay))
            }
            state.synchronization = nil
            state.clockSample = nil
            state.lastHostTime = nil
            state.clockDiscontinuous = false
        }
    }

    func releaseScratch() {
        state.withLock { state in
            guard var scratch = state.scratch, scratch.remaining == nil,
                  let current = state.current else { return }
            // Servo settlement must not erase a recent flick, but old motion cannot restart it.
            if scratch.motionAgeFrames >= Int(0.12 * current.sampleRate) { scratch.handStep = 0 }
            scratch.launchFrames = scratch.transitionFrames
            let remaining = max(1, Int(1.2 * current.sampleRate))
            scratch.remaining = remaining
            scratch.targetStep = state.isPlaying ? deltaBeatFor(current) : 0
            scratch.decay = exp(log(0.001) / Double(remaining))
            state.scratch = scratch
        }
    }

    func endScratch(immediate: Bool = false) {
        state.withLock { state in
            if immediate {
                state.scratch = nil
                state.clockSample = nil
                state.lastHostTime = nil
                return
            }
            guard var scratch = state.scratch, let current = state.current else { return }
            if scratch.remaining.map({ $0 > scratch.transitionFrames }) ?? true {
                scratch.remaining = scratch.transitionFrames
                scratch.targetStep = state.isPlaying ? deltaBeatFor(current) : 0
                state.scratch = scratch
            }
            state.clockSample = nil
            state.lastHostTime = nil
        }
    }

    func seek(bySeconds seconds: Double) throws {
        guard seconds.isFinite else { throw PlaybackError.invalidSeekOffset }
        try state.withLock { state in
            guard let current = state.current else { throw PlaybackError.noCurrentLoop }
            guard state.scratch == nil, state.reservation == nil, state.replacement == nil, state.fade == nil else {
                throw PlaybackError.replacementInProgress
            }
            let duration = current.beatCount * 60 / current.bpm
            let offset = seconds.truncatingRemainder(dividingBy: duration) / duration * current.beatCount
            let local = state.beatPosition.truncatingRemainder(dividingBy: current.beatCount)
            let target = (local + offset).truncatingRemainder(dividingBy: current.beatCount)
            state.beatPosition = target < 0 ? target + current.beatCount : target
            state.framePosition = frame(for: state.beatPosition, in: current)
            state.synchronization = nil
            state.clockSample = nil
            state.lastHostTime = nil
            state.clockDiscontinuous = false
            state.pendingBoundary = state.pending == nil ? nil : state.pendingTiming.boundary(after: state.beatPosition, beatsPerBar: current.beatsPerBar)
        }
    }

    func stopPlayback() {
        state.withLock { state in
            state.scratch = nil
            state.isPlaying = false
            state.synchronization = nil
            state.clockSample = nil
            if let replacement = state.replacement {
                state.current = replacement.loop
                state.currentGeneration = replacement.generation
                state.currentSwitchIndex = replacement.switchIndex
            }
            state.publishedPerformanceGeneration = state.currentPerformanceGeneration
            state.publishedSwitchIndex = state.currentSwitchIndex
            if state.currentPerformanceGeneration > 0 || state.currentSwitchIndex != nil, let current = state.current {
                state.framePosition = frame(for: state.beatPosition, in: current)
            }
            state.replacement = nil
            state.fade = nil
            state.retired = nil
        }
    }

    func snapshot() -> PlaybackSnapshot {
        positionSnapshot().playback
    }

    func positionSnapshot() -> PositionSnapshot {
        state.withLock { state in
            let sourceFade = state.fade.flatMap { $0.oldBeatPosition == nil ? nil : $0 }
            let switching = state.currentSwitchIndex != state.publishedSwitchIndex
            let visibleLoop = sourceFade != nil || state.currentPerformanceGeneration != state.publishedPerformanceGeneration || switching
                ? state.fade?.old.loop : state.current
            let beatPosition: Double
            if let sourceFade, let oldBeat = sourceFade.oldBeatPosition {
                beatPosition = oldBeat.truncatingRemainder(dividingBy: sourceFade.old.loop.beatCount)
            } else if state.currentPerformanceGeneration != state.publishedPerformanceGeneration || switching, let visibleLoop {
                beatPosition = state.beatPosition.truncatingRemainder(dividingBy: visibleLoop.beatCount)
            } else if let current = state.current {
                let frames = max(1, current.pcm.count / 2)
                beatPosition = Double(state.framePosition) / Double(frames) * current.beatCount
            } else {
                beatPosition = 0
            }
            return PositionSnapshot(
                playback: PlaybackSnapshot(
                    loop: visibleLoop,
                    revision: sourceFade?.old.revision ?? state.currentRevision,
                    beatPosition: beatPosition,
                    isPlaying: state.isPlaying,
                    overrideGeneration: sourceFade?.old.generation ?? (switching ? (state.fade?.old.generation ?? state.currentGeneration) : state.currentGeneration),
                    performanceGeneration: sourceFade?.old.performanceGeneration ?? state.publishedPerformanceGeneration,
                    switchVariantIndex: sourceFade == nil ? state.publishedSwitchIndex : sourceFade?.old.switchIndex
                ),
                accumulatedBeatPosition: sourceFade?.oldBeatPosition ?? state.beatPosition
            )
        }
    }

    static func correctedLocalBeatPosition(
        accumulatedBeatPosition: Double,
        loopBeatCount: Double,
        correction: Double
    ) -> Double {
        guard accumulatedBeatPosition.isFinite,
              loopBeatCount.isFinite, loopBeatCount > 0,
              correction.isFinite, correction >= 0 else {
            return 0
        }
        let corrected = accumulatedBeatPosition - correction
        guard corrected > 0 else { return 0 }
        let local = corrected.truncatingRemainder(dividingBy: loopBeatCount)
        return local >= 0 ? local : local + loopBeatCount
    }

    func synchronize(to anchor: PlaybackClockAnchor, presentationLatency: Double) throws {
        guard anchor.isPlaying else { throw PlaybackClockError.unavailable }
        let latency = try PlaybackClockAnchor.hostTicks(forSeconds: presentationLatency)
        try state.withLock { state in
            guard state.current != nil, state.isPlaying, state.scratch == nil else { throw PlaybackClockError.unavailable }
            guard state.pending == nil, state.reservation == nil, state.replacement == nil,
                  state.fade == nil else { throw PlaybackError.replacementInProgress }
            state.synchronization = (anchor, latency)
        }
    }

    func invalidateClock() {
        state.withLock { $0.clockSample = nil }
    }

    func setClockRate(_ rate: Double) {
        state.withLock { state in
            if state.clockRate != rate {
                state.clockRate = rate
                state.clockSample = nil
            }
        }
    }

    func clockAnchor(presentationLatency: Double, now: UInt64 = mach_absolute_time()) throws -> PlaybackClockAnchor {
        let values = try state.withLock { state in
            guard state.scratch == nil, state.fade?.oldBeatPosition == nil else { throw PlaybackClockError.unavailable }
            return (state.current?.bpm, state.current?.beatCount, state.currentRevision,
             state.currentGeneration, state.isPlaying, state.beatPosition, state.clockRate,
             state.clockSample, state.clockDiscontinuous)
        }
        guard let bpm = values.0, let count = values.1, let revision = values.2 else {
            throw PlaybackClockError.unavailable
        }
        if !values.4 {
            return try PlaybackClockAnchor(presentationHostTime: now, accumulatedBeatPosition: values.5,
                beatsPerMinute: bpm * values.6, loopBeatCount: count, revision: revision,
                overrideGeneration: values.3, isPlaying: false)
        }
        guard !values.8 else { throw PlaybackClockError.discontinuous }
        guard let sample = values.7 else { throw PlaybackClockError.unavailable }
        let latency = try PlaybackClockAnchor.hostTicks(forSeconds: presentationLatency)
        let (host, overflow) = sample.hostTime.addingReportingOverflow(latency)
        guard !overflow else { throw PlaybackClockError.outOfRange }
        return try PlaybackClockAnchor(presentationHostTime: host, accumulatedBeatPosition: sample.beat,
            beatsPerMinute: bpm * values.6, loopBeatCount: count, revision: revision,
            overrideGeneration: values.3, isPlaying: true)
    }

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>,
                hostTime: UInt64? = nil) -> OSStatus {
        guard frameCount > 0 else { return noErr }
        return state.withLock { state in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // AVFAudio owns aligned non-interleaved Float32 stereo storage. Capacity is checked
            // before binding; pointers and offsets stay within this callback and never escape.
            guard buffers.count == 2, buffers.allSatisfy({
                $0.mNumberChannels == 1 && $0.mData != nil &&
                Int($0.mDataByteSize) / MemoryLayout<Float>.stride >= frameCount
            }) else { return kAudio_ParamError }
            guard state.isPlaying || state.scratch != nil, state.current != nil else {
                for buffer in buffers {
                    if let data = buffer.mData { memset(data, 0, frameCount * MemoryLayout<Float>.stride) }
                }
                return noErr
            }

            if var scratch = state.scratch, let current = state.current {
                let frames = current.pcm.count / 2
                let baseStep = deltaBeatFor(current)
                current.pcm.withLittleEndianBytes { pcm in
                    for offset in 0..<frameCount {
                        // A completed gesture joins normal playback inside the same callback.
                        if scratch.remaining == 0 {
                            let value = state.isPlaying ? ScratchResampler.frame(pcm: pcm, index: state.framePosition) : (0, 0)
                            write(buffers: buffers, frame: offset, left: value.0, right: value.1)
                            if state.isPlaying {
                                state.beatPosition += baseStep
                                state.framePosition = (state.framePosition + 1) % frames
                            }
                            continue
                        }
                        if scratch.remaining == nil {
                            scratch.motionAgeFrames = min(Int(0.12 * current.sampleRate), scratch.motionAgeFrames + 1)
                            // A critically damped position servo follows hand displacement, not
                            // an indefinitely held velocity. Its output is continuous at reversals.
                            let error = scratch.targetPosition - scratch.position
                            let omega = 1 / (0.005 * current.sampleRate)
                            scratch.step += omega * omega * error - 2 * omega * scratch.step
                            let limit = ScratchResampler.maximumSpeed * current.beatCount / Double(frames)
                            scratch.step = min(limit, max(-limit, scratch.step))
                            if abs(error) < baseStep * 0.000001 && abs(scratch.step) < baseStep * 0.000001 {
                                scratch.step = error
                            }
                        } else if let remaining = scratch.remaining, remaining <= scratch.transitionFrames {
                            scratch.step += (scratch.targetStep - scratch.step) / Double(remaining)
                        } else if scratch.launchFrames > 0 {
                            scratch.step += (scratch.handStep - scratch.step) / Double(scratch.launchFrames)
                            scratch.launchFrames -= 1
                        } else {
                            scratch.step = scratch.targetStep + (scratch.step - scratch.targetStep) * scratch.decay
                        }
                        let desiredGain = Float(min(1, abs(scratch.step / baseStep)))
                        scratch.gain += (desiredGain - scratch.gain) * scratch.gainDecay
                        let position = state.beatPosition.truncatingRemainder(dividingBy: current.beatCount) / current.beatCount * Double(frames)
                        let speed = scratch.step / current.beatCount * Double(frames)
                        var value: (Float, Float) = (0, 0)
                        if scratch.gain > 0.000001 {
                            let filtered = scratchResampler.sample(pcm: pcm, position: position, speed: speed)
                            value = (filtered.0 * scratch.gain, filtered.1 * scratch.gain)
                        }
                        if let entryFrame = scratch.entryFrame {
                            let old = ScratchResampler.frame(pcm: pcm, index: entryFrame)
                            let mix = Float(scratch.entryElapsed) / Float(scratch.transitionFrames - 1)
                            value = (old.0 * (1 - mix) + value.0 * mix, old.1 * (1 - mix) + value.1 * mix)
                            scratch.entryElapsed += 1
                            scratch.entryFrame = scratch.entryElapsed == scratch.transitionFrames ? nil : (entryFrame + 1) % frames
                        }
                        if let remaining = scratch.remaining, remaining <= scratch.transitionFrames {
                            let mix = Float(scratch.transitionFrames - remaining) / Float(scratch.transitionFrames - 1)
                            let target = state.isPlaying ? ScratchResampler.frame(pcm: pcm, index: state.framePosition) : (0, 0)
                            value = (value.0 * (1 - mix) + target.0 * mix, value.1 * (1 - mix) + target.1 * mix)
                        }
                        write(buffers: buffers, frame: offset, left: value.0, right: value.1)
                        scratch.position += scratch.step
                        let beat = scratch.position.truncatingRemainder(dividingBy: current.beatCount)
                        state.beatPosition = beat < 0 ? beat + current.beatCount : beat
                        state.framePosition = frame(for: state.beatPosition, in: current)
                        if let remaining = scratch.remaining { scratch.remaining = remaining - 1 }
                    }
                }
                state.scratch = scratch.remaining == 0 ? nil : scratch
                return noErr
            }

            if let sync = state.synchronization, let hostTime, let current = state.current {
                let (presentation, overflow) = hostTime.addingReportingOverflow(sync.latency)
                guard !overflow else { return kAudio_ParamError }
                do {
                    let beat = try sync.anchor.beat(atHostTime: presentation)
                    state.beatPosition = beat
                    state.framePosition = frame(for: beat, in: current)
                    state.clockSample = nil
                    state.lastHostTime = nil
                    state.synchronization = nil
                } catch {
                    state.synchronization = nil
                    return kAudio_ParamError
                }
            }
            if let hostTime, hostTime > 0 {
                state.clockDiscontinuous = state.lastHostTime.map { hostTime <= $0 } ?? false
                state.clockSample = state.clockDiscontinuous ? nil
                    : ClockSample(hostTime: hostTime, beat: state.beatPosition)
                state.lastHostTime = hostTime
            } else {
                state.clockSample = nil
            }
            for offset in 0..<frameCount {
                if let pending = state.pending,
                   let boundary = state.pendingBoundary,
                   state.beatPosition >= boundary, state.reservation == nil, state.fade == nil, state.retired == nil,
                   state.currentPerformanceGeneration == state.publishedPerformanceGeneration {
                    let old: Candidate?
                    if let loop = state.current, let revision = state.currentRevision {
                        old = Candidate(loop: loop, revision: revision, generation: state.currentGeneration,
                            performanceGeneration: state.currentPerformanceGeneration, switchIndex: state.currentSwitchIndex)
                    } else { old = nil }
                    adopt(pending, into: &state)
                    if let old { state.fade = Fade(old: old, oldBeatPosition: state.beatPosition) }
                }

                if state.fade == nil, state.retired == nil, let replacement = state.replacement {
                    beginFade(replacement, into: &state)
                }

                guard let active = state.current else {
                    write(buffers: buffers, frame: offset, left: 0, right: 0)
                    continue
                }
                let frame = state.framePosition % max(1, active.pcm.count / 2)
                let performanceFade = state.currentPerformanceGeneration != state.publishedPerformanceGeneration
                let phase = state.currentPerformanceGeneration > 0 || state.currentSwitchIndex != nil
                    ? sample(at: state.beatPosition, in: active)
                    : (active.pcm[frame * 2], active.pcm[frame * 2 + 1])
                var left = phase.0
                var right = phase.1
                if let fade = state.fade {
                    let mix = Float(fade.elapsed) / Float(Self.crossfadeFrames - 1)
                    let old: (Float, Float)
                    if let oldBeat = fade.oldBeatPosition {
                        old = sample(at: oldBeat, in: fade.old.loop)
                        state.fade?.oldBeatPosition = oldBeat + deltaBeatFor(fade.old.loop)
                    } else {
                        old = performanceFade || state.currentPerformanceGeneration > 0 || state.currentSwitchIndex != nil || fade.old.switchIndex != nil
                            ? sample(at: state.beatPosition, in: fade.old.loop)
                            : (fade.old.loop.pcm[frame * 2], fade.old.loop.pcm[frame * 2 + 1])
                    }
                    left = old.0 * (1 - mix) + left * mix
                    right = old.1 * (1 - mix) + right * mix
                    if fade.elapsed + 1 == Self.crossfadeFrames {
                        state.retired = fade.old
                        state.publishedPerformanceGeneration = state.currentPerformanceGeneration
                        state.publishedSwitchIndex = state.currentSwitchIndex
                        state.fade = nil
                    } else {
                        state.fade?.elapsed += 1
                    }
                }
                write(buffers: buffers, frame: offset, left: left, right: right)
                state.beatPosition += deltaBeatFor(active)
                state.framePosition = state.currentPerformanceGeneration > 0 || state.currentSwitchIndex != nil
                    ? self.frame(for: state.beatPosition, in: active)
                    : (frame + 1) % loopFrameCountFor(active)
            }
            return noErr
        }
    }

    private func adopt(_ candidate: Candidate, into state: inout State) {
        state.synchronization = nil
        state.current = candidate.loop
        state.currentRevision = candidate.revision
        state.currentSwitchIndex = nil
        state.publishedSwitchIndex = nil
        state.clockSample = nil
        state.currentGeneration = 0
        state.currentPerformanceGeneration = 0
        state.publishedPerformanceGeneration = 0
        state.latestPerformanceGeneration = 0
        state.latestGeneration = 0
        state.replacement = nil
        if let fade = state.fade { state.retired = fade.old }
        state.fade = nil
        state.pending = nil
        state.pendingBoundary = nil
        state.framePosition = frame(for: state.beatPosition, in: candidate.loop)
    }

    private func sample(at beat: Double, in loop: PreparedLoop) -> (Float, Float) {
        let count = loop.pcm.count / 2
        let localBeat = beat.truncatingRemainder(dividingBy: loop.beatCount)
        let position = max(0, localBeat / loop.beatCount * Double(count))
        let first = Int(position) % count
        let second = (first + 1) % count
        let fraction = Float(position - floor(position))
        return (loop.pcm[first * 2] * (1 - fraction) + loop.pcm[second * 2] * fraction,
                loop.pcm[first * 2 + 1] * (1 - fraction) + loop.pcm[second * 2 + 1] * fraction)
    }

    private func frame(for beat: Double, in loop: PreparedLoop) -> Int {
        let localBeat = beat.truncatingRemainder(dividingBy: loop.beatCount)
        let ratio = max(0, min(1, localBeat / loop.beatCount))
        return Int((ratio * Double(loop.pcm.count / 2)).rounded(.down)) % max(1, loop.pcm.count / 2)
    }

    private func loopFrameCountFor(_ loop: PreparedLoop) -> Int {
        max(1, loop.pcm.count / 2)
    }

    private func deltaBeatFor(_ loop: PreparedLoop) -> Double {
        loop.bpm / 60 / loop.sampleRate
    }

    private func write(buffers: UnsafeMutableAudioBufferListPointer, frame: Int, left: Float, right: Float) {
        for (index, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else { continue }
            data.assumingMemoryBound(to: Float.self)[frame] = index == 0 ? left : right
        }
    }
}
