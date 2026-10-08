import Foundation

public enum SourceResultError: Error, LocalizedError, Sendable {
    case invalidAnchors
    public var errorDescription: String? { "Accepted results contain duplicate identities, invalid source anchors, or more than 32 rows." }
}
