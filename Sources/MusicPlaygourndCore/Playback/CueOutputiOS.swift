#if os(iOS)
import AVFoundation

/// Uses explicit native channel mapping; unselected hardware channels stay silent.
@MainActor
final class CueOutput {
    let buffer = CueAudioBuffer()
    private(set) var engine: AVAudioEngine?
    private(set) var deviceID: UInt32?
    var level: Float = 0.5 { didSet { engine?.mainMixerNode.outputVolume = level } }

    static func device(of engine: AVAudioEngine) throws -> UInt32 {
        let devices = try CueOutputDevice.available()
        guard let first = devices.first else { throw PlaybackError.audioSetupFailed("A stereo output route is unavailable.") }
        guard let map = engine.outputNode.auAudioUnit.channelMap else { return first.id }
        return try matching(map, devices: devices)
    }
    private static func matching(_ map: [NSNumber], devices: [CueOutputDevice]) throws -> UInt32 {
        guard let match = devices.first(where: { device in
            device.channels.enumerated().allSatisfy { channel, destination in
                map.indices.contains(destination) && map[destination].intValue == channel
            } && map.enumerated().allSatisfy { device.channels.contains($0.offset) || $0.element.intValue == -1 }
        }) else { throw PlaybackError.audioSetupFailed("The native output map no longer selects one stereo route.") }
        return match.id
    }
    static func bind(_ id: UInt32, to engine: AVAudioEngine) throws {
        guard let selected = try CueOutputDevice.available().first(where: { $0.id == id }) else {
            throw PlaybackError.audioSetupFailed("The selected stereo route is disconnected.")
        }
        let unit = engine.outputNode.auAudioUnit
        guard unit.channelMap != nil else { throw PlaybackError.audioSetupFailed("This output does not expose independent channel mapping.") }
        let count = Int(engine.outputNode.outputFormat(forBus: 0).channelCount)
        guard (2...8).contains(count), selected.channels.allSatisfy({ (0..<count).contains($0) }) else {
            throw PlaybackError.audioSetupFailed("The selected channels are unavailable in the active output format.")
        }
        let previous = unit.channelMap
        var map = [NSNumber](repeating: -1, count: count)
        for (source, destination) in selected.channels.enumerated() { map[destination] = NSNumber(value: source) }
        unit.channelMap = map
        guard unit.channelMap == map else {
            unit.channelMap = previous
            throw PlaybackError.audioSetupFailed("The output rejected explicit channel routing.")
        }
    }
    func select(_ id: UInt32?, main: UInt32) throws {
        guard let id else { stop(); return }
        let devices = try CueOutputDevice.available()
        guard id != main,
              let selected = devices.first(where: { $0.id == id }),
              let mainPair = devices.first(where: { $0.id == main }),
              Set(selected.channels).isDisjoint(with: mainPair.channels) else {
            throw PlaybackError.audioSetupFailed("Headphone cue needs a distinct stereo pair on a routable output.")
        }
        let candidate = AVAudioEngine()
        do {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: PreparedLoop.requiredSampleRate, channels: 2) else {
                throw PlaybackError.audioSetupFailed("Cannot create headphone output format.")
            }
            let buffer = buffer
            let source = AVAudioSourceNode(format: format) { @Sendable [buffer] _, _, frames, data in
                buffer.render(frames: Int(frames), into: UnsafeMutableAudioBufferListPointer(data))
            }
            candidate.attach(source)
            candidate.connect(source, to: candidate.mainMixerNode, format: format)
            try Self.bind(id, to: candidate)
            candidate.mainMixerNode.outputVolume = level
            stop()
            buffer.reset(enabled: true)
            try candidate.start()
            guard try Self.device(of: candidate) == id else { throw PlaybackError.audioSetupFailed("Headphone routing changed during setup.") }
            engine = candidate; deviceID = id
        } catch {
            candidate.stop(); buffer.reset(enabled: false)
            throw error
        }
    }
    func validate(main: UInt32) throws {
        guard let id = deviceID, let engine else { return }
        guard id != main, try Self.device(of: engine) == id, try CueOutputDevice.available().contains(where: { $0.id == id }) else {
            stop(); throw PlaybackError.audioSetupFailed("Headphone output disconnected. Select its route again.")
        }
    }
    func stop() {
        engine?.stop(); engine = nil; deviceID = nil
        buffer.reset(enabled: false)
    }
}
#endif
