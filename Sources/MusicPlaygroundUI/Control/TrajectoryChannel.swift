public protocol TrajectoryChannel { associatedtype Point: TrajectoryPoint; var kindName: String { get }; var points: [Point] { get } }
