import AVFoundation
import CoreAudio

/// Owns only the explicitly selected headphone device, never the default route.
@MainActor
final class CueOutput {
    let buffer = CueAudioBuffer()
    private(set) var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var routingFailure: String?
    private var selectionRevision = UUID()
    private(set) var deviceID: AudioDeviceID?
    var level: Float = 0.5 { didSet { engine?.mainMixerNode.outputVolume = level } }

    static func device(of engine: AVAudioEngine) throws -> AudioDeviceID {
        guard let unit = engine.outputNode.audioUnit else { throw PlaybackError.audioSetupFailed("Audio output unit is unavailable.") }
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try CueOutputDevice.check(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size))
        return id
    }

    func select(_ id: AudioDeviceID?, main: AudioDeviceID) throws {
        guard let id else { stop(); return }
        guard id != main, try CueOutputDevice.available().contains(where: { $0.id == id }) else {
            throw PlaybackError.audioSetupFailed("Choose a connected stereo headphone output different from the main output.")
        }
        stop()
        routingFailure = nil
        let candidate = AVAudioEngine()
        do {
            guard let unit = candidate.outputNode.audioUnit,
                  let format = AVAudioFormat(standardFormatWithSampleRate: PreparedLoop.requiredSampleRate, channels: 2) else {
                throw PlaybackError.audioSetupFailed("Cannot create the headphone output.")
            }
            var selected = id
            try CueOutputDevice.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &selected, UInt32(MemoryLayout<AudioDeviceID>.size)))
            let buffer = buffer
            let source = AVAudioSourceNode(format: format) { @Sendable [buffer] _, _, frames, data in
                buffer.render(frames: Int(frames), into: UnsafeMutableAudioBufferListPointer(data))
            }
            candidate.attach(source)
            candidate.connect(source, to: candidate.mainMixerNode, format: format)
            candidate.mainMixerNode.outputVolume = level
            buffer.reset(enabled: true)
            try candidate.start()
            guard try Self.device(of: candidate) == id else { throw PlaybackError.audioSetupFailed("Headphone output changed during setup.") }
            engine = candidate
            deviceID = id
            let revision = selectionRevision
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: candidate, queue: nil
            ) { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.selectionRevision == revision else { return }
                    self.stop()
                    self.routingFailure = "Headphone output configuration changed. Select the output again."
                }
            }
        } catch {
            candidate.stop()
            buffer.reset(enabled: false)
            throw error
        }
    }

    func validate(main: AudioDeviceID) throws {
        if let routingFailure {
            self.routingFailure = nil
            throw PlaybackError.audioSetupFailed(routingFailure)
        }
        guard let deviceID, let engine else { return }
        do {
            guard deviceID != main, try Self.device(of: engine) == deviceID,
                  try CueOutputDevice.available().contains(where: { $0.id == deviceID }) else {
                throw PlaybackError.audioSetupFailed("Headphone output disconnected or became the main output. Select another output.")
            }
        } catch { stop(); throw error }
    }

    func stop() {
        selectionRevision = UUID()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        buffer.reset(enabled: false)
        engine?.stop()
        engine = nil
        deviceID = nil
    }

    isolated deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine?.stop()
        buffer.reset(enabled: false)
    }
}
