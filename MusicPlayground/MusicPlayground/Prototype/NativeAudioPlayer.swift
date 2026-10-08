import AVFoundation

@MainActor
final class NativeAudioPlayer: AudioPlaying {
    enum Failure: Error {
        case bufferAllocation
        case outputUnavailable
        case sessionActivationRejected
        case sessionDeactivationRejected
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var retainedBuffer: AVAudioPCMBuffer?
    private var sessionActive = false
    private var tapInstalled = false
    private var generation: UInt64 = 0
    private var activation: Task<Void, any Error>?
    let meter = OutputMeter()
    var isActivating: Bool { activation != nil }
    var isPlaying: Bool { engine.isRunning && player.isPlaying }
    var outputDescription: String {
        let session = AVAudioSession.sharedInstance()
        let ports = session.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        return "\(ports) · volume \(Int(session.outputVolume * 100))%"
    }

    init() {
        engine.attach(player)
    }

    static func makeBuffer(_ loop: PreparedLoop) throws -> AVAudioPCMBuffer {
        try loop.validate()
        let frames = loop.pcm.count / 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: loop.sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { throw Failure.bufferAllocation }
        buffer.frameLength = AVAudioFrameCount(frames)
        // AVAudioPlayerNode owns planar PCM; perform one layout copy within scoped pointer lifetime.
        for frame in 0..<frames {
            channels[0][frame] = loop.pcm[frame * 2]
            channels[1][frame] = loop.pcm[frame * 2 + 1]
        }
        return buffer
    }

    func start(_ loop: PreparedLoop) async throws {
        try await stop()
        let token = generation
        let buffer = try Self.makeBuffer(loop)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            let activating = Task {
                guard try await session.activate(options: []) else { throw Failure.sessionActivationRejected }
                sessionActive = true
            }
            activation = activating
            try await activating.value
            guard token == generation else { throw CancellationError() }
            activation = nil
            try Task.checkCancellation()
            guard !session.currentRoute.outputs.isEmpty else { throw Failure.outputUnavailable }
            try engine.connectNode(player, to: engine.mainMixerNode, format: buffer.format)
            meter.reset()
            try engine.mainMixerNode.installAudioTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable [meter] buffer, _ in
                meter.observe(buffer)
            }
            tapInstalled = true
            retainedBuffer = buffer
            player.scheduleBuffer(buffer, atTime: nil, options: .loops,
                                  completionCallbackType: .dataConsumed, completionHandler: nil)
            engine.prepare()
            try engine.start()
            try player.playAudio(at: nil)
        } catch {
            let original = error
            // An overlapping Stop owns cleanup of the invalidated activation.
            if token == generation {
                do { try await stop() }
                catch { throw CleanupFailure(original: original, cleanup: error) }
            }
            throw original
        }
    }

    func stop() async throws {
        generation &+= 1
        player.stop()
        engine.stop()
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        retainedBuffer = nil
        if let activation {
            do { try await activation.value }
            catch { self.activation = nil; throw error }
            self.activation = nil
        }
        if sessionActive {
            guard try await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) else {
                throw Failure.sessionDeactivationRejected
            }
            sessionActive = false
        }
    }
}
