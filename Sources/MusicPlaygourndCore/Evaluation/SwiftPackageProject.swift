import Foundation

/// A compiler-discovered package and its playable Swift targets.
public struct SwiftPackageProject: Sendable, Equatable {
    public struct Target: Sendable, Equatable, Identifiable {
        public let name: String
        public let moduleName: String
        public let path: String
        public let sources: [String]
        public let entry: String
        public var id: String { name }
    }

    public let root: URL
    public let name: String
    public let targets: [Target]

    static func decode(_ data: Data, root: URL) throws -> Self {
        struct Description: Decodable {
            struct Target: Decodable {
                let name: String
                let c99name: String?
                let path: String?
                let sources: [String]?
                let type: String
                let module_type: String?
            }
            let name: String
            let targets: [Target]
        }
        let description = try JSONDecoder().decode(Description.self, from: data)
        let targets = try description.targets.filter { $0.type == "library" && $0.module_type == "SwiftTarget" }.compactMap { target -> Target? in
            guard let sources = target.sources, let path = target.path, let module = target.c99name else {
                throw EvaluationError.invalidResult("SwiftPM returned incomplete source metadata for \(target.name).")
            }
            let entries = sources.filter { URL(fileURLWithPath: $0).lastPathComponent == "Session.swift" }
            guard !entries.isEmpty else { return nil }
            guard entries.count == 1, let entry = entries.first else {
                throw EvaluationError.invalidSource("Target \(target.name) must have exactly one Session.swift entry.")
            }
            return Target(name: target.name, moduleName: module, path: path, sources: sources, entry: entry)
        }.sorted { $0.name < $1.name }
        guard !targets.isEmpty else {
            throw EvaluationError.invalidSource("The package needs a Swift library target containing Session.swift with Session: Music.")
        }
        return Self(root: root.standardizedFileURL.resolvingSymlinksInPath(), name: description.name, targets: targets)
    }

    public func entryURL(for target: Target) -> URL {
        root.appending(path: target.path).appending(path: target.entry)
    }
}
