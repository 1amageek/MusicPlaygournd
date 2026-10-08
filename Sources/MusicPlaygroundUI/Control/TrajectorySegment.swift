public protocol TrajectorySegment { associatedtype Channel: TrajectoryChannel; var sourceID: Int? { get }; var channels: [Channel] { get } }
