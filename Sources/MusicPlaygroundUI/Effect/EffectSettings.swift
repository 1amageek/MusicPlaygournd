import Foundation

/// Presentation contract; the application validates and adopts DSP settings.
public protocol EffectSettings: Equatable {
    associatedtype Kind: CaseIterable, Hashable, RawRepresentable where Kind.RawValue == String
    var kind: Kind { get set }
    var rate: Double { get set }
    var depth: Double { get set }
    var feedback: Double { get set }
    var mix: Double { get set }
    var showsFeedback: Bool { get }
}
