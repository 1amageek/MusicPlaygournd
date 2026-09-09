import Foundation

/// Host presentation metadata for one numeric control declaration.
public struct SliderDefinition: Sendable, Equatable, Hashable, Codable {
    public let id: String
    public let fileID: String
    public let line: Int
    public let column: Int
    public let range: ClosedRange<Double>
    public let initialValue: Double
    public let value: Double
}
