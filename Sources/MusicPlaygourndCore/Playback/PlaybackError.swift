import Foundation

public enum PlaybackError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public var errorDescription: String? { description }

    case audioSetupFailed(String)
    case audioStartFailed(String)
    case invalidScratchMotion
    case invalidSeekOffset
    case noCurrentLoop
    case staleRevision(UInt64)
    case duplicateRevision(UInt64)
    case staleOverrideGeneration(UInt64)
    case replacementInProgress
    case incompatibleReplacement
    case updateNotStarted(UInt64)
    case invalidLoop(PreparedLoopValidationError)
    case invalidMasterVolume(Float)
    case invalidPlaybackRate(Float)
    case invalidLowPassCutoff(Float)
    case invalidMasterBalance(Float)
    case equalizerResponseFailed(Int32)
    case invalidCompressorSettings
    case invalidDJFilter(Float)
    case invalidDelayTime(Double)
    case invalidEqualizerBand
    case invalidDelayMix(Float)
    case invalidReverbMix(Float)
    case offlineRenderingFailed(String)

    public var description: String {
        switch self {
        case .audioSetupFailed(let message): "Audio setup failed: \(message)"
        case .audioStartFailed(let message): "Audio start failed: \(message)"
        case .invalidScratchMotion: "Scratch requires a finite displacement and velocity, a representable target position, and an interval in (0, 0.25] seconds"
        case .invalidSeekOffset: "Seek offset must be finite"
        case .noCurrentLoop: "No prepared loop is available"
        case .staleRevision(let revision): "Revision \(revision) is stale"
        case .duplicateRevision(let revision): "Revision \(revision) was already submitted"
        case .staleOverrideGeneration(let generation): "Override generation \(generation) is stale"
        case .replacementInProgress: "Another code or performance replacement is pending"
        case .incompatibleReplacement: "Replacement changes the adopted loop timing or identity"
        case .updateNotStarted(let revision): "Revision \(revision) was not started"
        case .invalidLoop(let error): "Invalid prepared loop: \(error)"
        case .invalidMasterVolume(let value): "Master volume \(value) is outside 0...1"
        case .invalidPlaybackRate(let rate): "Playback rate \(rate) is outside 1/32...32"
        case .invalidLowPassCutoff(let cutoff): "Low-pass cutoff \(cutoff) is outside 20...20000 Hz"
        case .invalidMasterBalance(let value): "Master balance \(value) is outside -1...1"
        case .equalizerResponseFailed(let status): "Cannot read native EQ response: \(status)"
        case .invalidCompressorSettings: "Compressor requires threshold -60...0 dB, ratio 1...20, attack 0.1...200 ms and release 10...2000 ms"
        case .invalidDJFilter(let value): "DJ filter \(value) is outside -1...1"
        case .invalidDelayTime(let value): "Delay time \(value) is outside 0.01...2 seconds"
        case .invalidEqualizerBand: "EQ requires band 0...2, frequency 20...20000 Hz and gain -12...12 dB and Q 0.2...20"
        case .invalidDelayMix(let mix): "Delay mix \(mix) is outside 0...1"
        case .invalidReverbMix(let mix): "Reverb mix \(mix) is outside 0...1"
        case .offlineRenderingFailed(let message): "Offline rendering failed: \(message)"
        }
    }
}
