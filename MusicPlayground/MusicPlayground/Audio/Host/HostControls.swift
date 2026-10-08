import Foundation

@MainActor
protocol HostControls: AnyObject {
    var bpm: Double { get }
    var acceptedSource: String { get }
    var catalog: LiveControlCatalog? { get }
    var loop: PreparedLoop? { get }
    func setControl(_ address: LiveControlAddress, value: LiveControlValue?) async throws
    func setBPM(_ value: Double) throws
    func pause()
    func refresh()
}

extension AudioDeck: HostControls {}
