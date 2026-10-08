public protocol KnobPresentation {
    associatedtype Unit: RawRepresentable where Unit.RawValue == String
    associatedtype Scale: RawRepresentable where Scale.RawValue == String
    var unit: Unit { get }
    var scale: Scale { get }
    var minimum: Double { get }
    var maximum: Double { get }
    func value(at fraction: Double) throws -> Double
}
