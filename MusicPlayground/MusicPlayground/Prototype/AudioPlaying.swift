import Foundation

@MainActor
protocol AudioPlaying: AnyObject {
    var isPlaying: Bool { get }
    var meter: OutputMeter { get }
    var outputDescription: String { get }
    func start(_ loop: PreparedLoop) async throws
    func stop() async throws
}
