import Foundation

/// Unsaved editor buffers belong to this revision; the package on disk is never rewritten.
public struct ProjectEvaluationRequest: Sendable {
    public let project: SwiftPackageProject
    public let target: SwiftPackageProject.Target
    public let buffers: [URL: String]

    public init(project: SwiftPackageProject, target: SwiftPackageProject.Target, buffers: [URL: String]) throws {
        self.project = project
        self.target = target
        var normalized: [URL: String] = [:]
        for (url, source) in buffers {
            let identity = url.standardizedFileURL.resolvingSymlinksInPath()
            if let previous = normalized[identity], previous != source {
                throw EvaluationError.invalidSource("Conflicting buffers for \(identity.lastPathComponent).")
            }
            normalized[identity] = source
        }
        self.buffers = normalized
    }
}
