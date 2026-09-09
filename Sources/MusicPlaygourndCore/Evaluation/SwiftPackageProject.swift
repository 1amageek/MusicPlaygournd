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

    public struct Dependency: Sendable, Equatable, Decodable, Identifiable {
        public struct Requirement: Sendable, Equatable, Decodable {
            public struct VersionRange: Sendable, Equatable, Decodable {
                public let lowerBound: String
                public let upperBound: String
            }
            public let exact: [String]?
            public let range: [VersionRange]?
            public let branch: [String]?
            public let revision: [String]?
        }
        public let identity: String
        public let url: String?
        public let path: String?
        public let requirement: Requirement?
        public var checkoutPath: String? = nil
        public var resolvedVersion: String? = nil
        public var id: String { identity }
        public var name: String {
            guard let url, let location = URL(string: url) else { return identity }
            return location.deletingPathExtension().lastPathComponent
        }
        public var versionDescription: String {
            if let resolvedVersion, resolvedVersion != "unspecified" { return resolvedVersion }
            if let version = requirement?.exact?.first { return version }
            if let range = requirement?.range?.first { return "\(range.lowerBound)..<\(range.upperBound)" }
            if let branch = requirement?.branch?.first { return branch }
            if let revision = requirement?.revision?.first { return String(revision.prefix(7)) }
            return path == nil ? "Unresolved" : "local"
        }
    }

    public let root: URL
    public let name: String
    public let targets: [Target]
    public var dependencies: [Dependency] = []

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
            let dependencies: [Dependency]?
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
        return Self(root: root.standardizedFileURL.resolvingSymlinksInPath(), name: description.name, targets: targets, dependencies: description.dependencies ?? [])
    }

    mutating func loadResolvedDependencies(_ data: Data) throws {
        struct Node: Decodable {
            let identity: String
            let url: String
            let version: String
            let path: String
            let dependencies: [Node]
        }
        let graph = try JSONDecoder().decode(Node.self, from: data)
        let declared = Dictionary(uniqueKeysWithValues: dependencies.map { ($0.identity, $0) })
        var loaded: [Dependency] = []
        var seen: Set<String> = []
        func append(_ node: Node) {
            guard seen.insert(node.identity).inserted else { return }
            var dependency = declared[node.identity] ?? Dependency(identity: node.identity, url: node.url,
                path: node.url.hasPrefix("/") ? node.path : nil, requirement: nil)
            dependency.checkoutPath = node.path
            dependency.resolvedVersion = node.version
            loaded.append(dependency)
            node.dependencies.forEach(append)
        }
        graph.dependencies.forEach(append)
        dependencies = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func entryURL(for target: Target) -> URL {
        root.appending(path: target.path).appending(path: target.entry)
    }
}
