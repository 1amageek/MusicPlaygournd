import AVFoundation

/// In-place native graph adapter for the live deck modulation effects.
final class DeckFXAudioUnit: AUAudioUnit {
    let kernel: DeckFXKernel
    private let input: AUAudioUnitBus
    private let output: AUAudioUnitBus
    private lazy var inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [input])
    private lazy var outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [output])

    @MainActor private static let registered: AudioComponentDescription = {
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
            componentSubType: 0x6d706678, componentManufacturer: 0x3161676b,
            componentFlags: AudioComponentFlags.unsearchable.rawValue, componentFlagsMask: 0)
        AUAudioUnit.registerSubclass(DeckFXAudioUnit.self, as: description,
            name: "MusicPlayground: Deck FX", version: 1)
        return description
    }()

    @MainActor static func makeNode() -> AVAudioUnitEffect {
        AVAudioUnitEffect(audioComponentDescription: registered)
    }

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: PreparedLoop.requiredSampleRate, channels: 2) else {
            throw PlaybackError.audioSetupFailed("Cannot create deck FX format.")
        }
        input = try AUAudioUnitBus(format: format)
        output = try AUAudioUnitBus(format: format)
        kernel = DeckFXKernel()
        try super.init(componentDescription: componentDescription, options: options)
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }

    override func allocateRenderResources() throws {
        for bus in [input, output] {
            guard bus.format.sampleRate == PreparedLoop.requiredSampleRate,
                  bus.format.channelCount == 2, bus.format.commonFormat == .pcmFormatFloat32,
                  !bus.format.isInterleaved else {
                throw PlaybackError.audioSetupFailed("Compressor requires 44.1 kHz planar stereo Float32.")
            }
        }
        try super.allocateRenderResources()
        kernel.resetHistory()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = kernel
        return { flags, timestamp, frames, bus, data, _, pull in
            guard bus == 0, let pull else { return kAudioUnitErr_NoConnection }
            guard frames <= 4096 else { return kAudioUnitErr_TooManyFramesToProcess }
            // Pull supplies host-owned in-place buffers; it never runs under our Mutex.
            let status = pull(flags, timestamp, frames, 0, data)
            guard status == noErr else { return status }
            return kernel.process(data, frames: Int(frames))
        }
    }
}
