public protocol ControlTrajectory { associatedtype Trace: TrajectorySegment; var beatCount: Double { get }; var traces: [Trace] { get } }
