import Foundation
import CryptoKit

/// Mirrors package inputs into evaluator-owned storage without sharing mutable source files.
struct ProjectWorkspace {
    let root: URL
    let entry: URL

    static func prepare(_ request: ProjectEvaluationRequest, at destination: URL, host: URL) throws -> Self {
        let manager = FileManager.default
        let origin = request.project.root
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        var iterationError: Error?
        guard let iterator = manager.enumerator(at: origin, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles], errorHandler: { _, error in iterationError = error; return false }) else {
            throw EvaluationError.invalidSource("Cannot enumerate the project.")
        }
        var paths = Set<String>()
        var count = 0
        for case let url as URL in iterator {
            count += 1
            guard count <= 4096 else { throw EvaluationError.invalidSource("Project exceeds 4096 entries.") }
            let canonicalPath = url.resolvingSymlinksInPath().path
            let canonicalRoot = origin.resolvingSymlinksInPath().path
            guard canonicalPath.hasPrefix(canonicalRoot + "/") else {
                throw EvaluationError.invalidSource("Project input escapes its root: \(url.lastPathComponent)")
            }
            let relative = String(canonicalPath.dropFirst(canonicalRoot.count + 1))
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else {
                throw EvaluationError.invalidSource("Project inputs must be regular files; symbolic link: \(relative)")
            }
            let copy = destination.appending(path: relative)
            paths.insert(relative)
            if values.isDirectory == true {
                try manager.createDirectory(at: copy, withIntermediateDirectories: true)
            } else if relative == "Package.swift" || copy.standardizedFileURL == destination.appending(path: request.target.path).appending(path: request.target.entry).standardizedFileURL {
                // The manifest is augmented below; preserve its timestamp until the final text changes.
                continue
            } else if url.pathExtension == "swift" || url.lastPathComponent == "Package.resolved" {
                let text = try request.buffers[url.standardizedFileURL.resolvingSymlinksInPath()] ?? String(contentsOf: url, encoding: .utf8)
                guard text.utf8.count <= 65_536 else { throw EvaluationError.invalidSource("\(relative) exceeds 64 KiB.") }
                try writeIfChanged(text, to: copy)
            } else {
                // Resources are copied only when their size or modification date changes.
                let old = manager.fileExists(atPath: copy.path) ? try copy.resourceValues(forKeys: keys) : nil
                if old?.fileSize != values.fileSize || old?.contentModificationDate != values.contentModificationDate {
                    if manager.fileExists(atPath: copy.path) { try manager.removeItem(at: copy) }
                    try manager.copyItem(at: url, to: copy)
                }
            }
        }
        if let iterationError { throw iterationError }
        let inventory = destination.appending(path: ".musicplayground-inputs.json")
        if manager.fileExists(atPath: inventory.path) {
            let previous = try JSONDecoder().decode([String].self, from: Data(contentsOf: inventory))
            for path in previous.sorted(by: { $0.count > $1.count }) where !paths.contains(path) {
                let url = destination.appending(path: path)
                if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            }
        }
        try JSONEncoder().encode(paths.sorted()).write(to: inventory, options: .atomic)
        let manifestURL = destination.appending(path: "Package.swift")
        let originalManifest = origin.appending(path: "Package.swift").standardizedFileURL.resolvingSymlinksInPath()
        let original = try request.buffers[originalManifest] ?? String(contentsOf: originalManifest, encoding: .utf8)
        guard original.utf8.count <= 65_536 else { throw EvaluationError.invalidSource("Package.swift exceeds 64 KiB.") }
        let hostManifest = try Data(contentsOf: host.appending(path: "Package.swift"))
        let hostIdentity = SHA256.hash(data: hostManifest).map { String(format: "%02x", $0) }.joined()
        let addition = """

        // MusicPlayground host manifest: \(hostIdentity)
        import Foundation
        package.dependencies = package.dependencies.map { dependency in
            if case .fileSystem(let name, let path) = dependency.kind {
                let resolved = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: \(literal(origin.path)), isDirectory: true)).standardizedFileURL.path
                if let name { return .package(name: name, path: resolved) }
                return .package(path: resolved)
            }
            return dependency
        }
        package.dependencies.append(.package(path: \(literal(host.path))))
        if let index = package.targets.firstIndex(where: { $0.name == \(literal(request.target.name)) }) {
            let original = package.targets[index]
            package.targets[index] = .executableTarget(
                name: original.name,
                dependencies: original.dependencies + [.product(name: "MusicPlaygourndCore", package: "MusicPlaygournd")],
                path: original.path, exclude: original.exclude, sources: original.sources,
                resources: original.resources, cSettings: original.cSettings, cxxSettings: original.cxxSettings,
                swiftSettings: original.swiftSettings, linkerSettings: original.linkerSettings, plugins: original.plugins)
        }
        package.products = [.executable(name: "MusicPlaygourndEvaluation", targets: [\(literal(request.target.name))])]
        """
        try writeIfChanged(original + addition, to: manifestURL)
        let targetDirectory = destination.appending(path: request.target.path)
        return Self(root: destination, entry: targetDirectory.appending(path: request.target.entry))
    }

    func astArguments(binaryPath: String, module: String, displaySource: URL) throws -> [String] {
        struct Plan: Decodable {
            struct Command: Decodable {
                let moduleName: String
                let importPath: String
                let sources: [String]
                let otherArguments: [String]
            }
            let swiftCommands: [String: Command]
        }
        let planURL = URL(fileURLWithPath: binaryPath).appending(path: "description.json")
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: planURL))
        let matches = plan.swiftCommands.values.filter { $0.moduleName == module }
        guard matches.count == 1, let command = matches.first else {
            throw EvaluationError.invalidResult("SwiftPM did not produce one compiler command for the session target.")
        }
        var arguments = ["-frontend", "-dump-ast", "-dump-ast-format", "json", "-suppress-warnings",
                         "-module-name", module, "-I", command.importPath]
        var index = 0
        while index < command.otherArguments.count {
            let argument = command.otherArguments[index]
            index += 1
            if ["-num-threads", "-L", "-Xlinker"].contains(argument) { index += 1; continue }
            if ["-whole-module-optimization", "-serialize-diagnostics", "-parseable-output", "-Xfrontend"].contains(argument)
                || argument.hasPrefix("-j") { continue }
            arguments.append(argument)
        }
        arguments += ["-primary-file", displaySource.path]
        let identity = entry.resolvingSymlinksInPath().path
        guard command.sources.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == identity }) else {
            throw EvaluationError.invalidSource("The manifest no longer includes this Session.swift. Reopen the project to select its entry.")
        }
        arguments += command.sources.filter { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path != identity }
        return arguments
    }

    static func writeIfChanged(_ text: String, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path), try String(contentsOf: url, encoding: .utf8).utf8.elementsEqual(text.utf8) { return }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}
