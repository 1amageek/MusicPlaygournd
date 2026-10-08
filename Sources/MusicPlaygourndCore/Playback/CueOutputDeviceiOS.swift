#if os(iOS)
import AVFoundation
import Foundation

/// A stereo pair exposed by the current native output route.
public struct CueOutputDevice: Identifiable, Sendable, Equatable {
    public let id: UInt32
    public let name: String
    internal let channels: [Int]

    @MainActor public static func available() throws -> [Self] {
        let route = AVAudioSession.sharedInstance().currentRoute
        var result: [Self] = []
        var identities: Set<UInt32> = []
        for port in route.outputs {
            let channels = (port.channels ?? []).map { Int($0.channelNumber) - 1 }.sorted()
            guard channels.allSatisfy({ (0..<8).contains($0) }) else {
                throw PlaybackError.audioSetupFailed("Output routing supports at most eight channels.")
            }
            for pair in stride(from: 0, to: channels.count - channels.count % 2, by: 2) {
                let selected = Array(channels[pair..<(pair + 2)])
                var identity: UInt32 = 2_166_136_261
                for byte in "\(port.uid):\(selected[0]):\(selected[1])".utf8 { identity = (identity ^ UInt32(byte)) &* 16_777_619 }
                guard identities.insert(identity).inserted else { throw PlaybackError.audioSetupFailed("Output route identities collide.") }
                result.append(Self(id: identity, name: "\(port.portName) · \(selected[0] + 1)–\(selected[1] + 1)", channels: selected))
            }
        }
        return result
    }
}
#endif
