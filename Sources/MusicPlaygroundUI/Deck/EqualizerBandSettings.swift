public protocol EqualizerBandSettings: Equatable {
    var frequency: Float { get set }
    var gain: Float { get set }
    var q: Float { get set }
    static var defaults: [Self] { get }
    init(frequency: Float, gain: Float, q: Float)
}
