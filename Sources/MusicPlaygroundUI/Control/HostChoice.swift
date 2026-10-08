import Foundation

public struct HostChoice<ID: Hashable>: Identifiable {
    public let id: ID
    public let name: String
    public init(id: ID, name: String) { self.id = id; self.name = name }
}
