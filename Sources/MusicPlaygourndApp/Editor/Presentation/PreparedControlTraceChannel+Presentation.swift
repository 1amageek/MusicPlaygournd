#if os(macOS)
import MusicPlaygourndCore
#endif
import MusicPlaygroundUI

extension PreparedControlTrace.Channel: TrajectoryChannel { public var kindName: String { kind.rawValue } }
