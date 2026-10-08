import Foundation
import SwiftParser
import SwiftSyntax

actor ProjectFiles: ProjectFileAccess {
    private let projectsDirectory: URL
    private let dependencyRoot: URL?
    private var root: URL?

    init(projectsDirectory: URL, dependencyRoot: URL? = nil) {
        self.projectsDirectory = projectsDirectory
        self.dependencyRoot = dependencyRoot
    }

    func openProject(_ candidate: URL) throws -> ProjectSnapshot {
        try Task.checkCancellation()
        return try scoped(candidate) {
            let canonical = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard try canonical.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw DocumentFailure.invalidProject("Choose a folder containing Package.swift.")
            }
            let manifestURL = canonical.appending(path: "Package.swift")
            let manifest = try text(manifestURL)
            let targets = try staticTargets(manifest, root: canonical)
            let entries = try enumerate(canonical)
            let canonicalDependency = dependencyRoot?.standardizedFileURL.resolvingSymlinksInPath()
            let dependencyEntries = try canonicalDependency.map { try enumerate($0) } ?? []
            let snapshot = ProjectSnapshot(root: canonical, scopeURL: candidate, entries: entries, targets: targets,
                                           dependencyRoot: canonicalDependency, dependencyEntries: dependencyEntries)
            root = candidate
            return snapshot
        }
    }

    func createProject(template: String) throws -> ProjectSnapshot {
        try Task.checkCancellation()
        guard template.utf8.count <= 65_536 else { throw DocumentFailure.sourceTooLarge }
        do {
            try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            let staging = projectsDirectory.appending(path: ".project-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            do {
                let sources = staging.appending(path: "Sources/Session", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
                let manifest = """
                // swift-tools-version: 6.0
                import PackageDescription
                let package = Package(
                    name: "Session",
                    products: [.library(name: "Session", targets: ["Session"])],
                    dependencies: [.package(url: "https://github.com/1amageek/SwiftMusic.git", exact: "0.5.1")],
                    targets: [.target(name: "Session", dependencies: [.product(name: "SwiftMusic", package: "SwiftMusic")])]
                )

                """
                try Data(manifest.utf8).write(to: staging.appending(path: "Package.swift"), options: .withoutOverwriting)
                try Data(template.utf8).write(to: sources.appending(path: "Session.swift"), options: .withoutOverwriting)
                for number in 1...4096 {
                    let destination = projectsDirectory.appending(path: "Playground\(number)", directoryHint: .isDirectory)
                    do {
                        try FileManager.default.moveItem(at: staging, to: destination)
                        return try openProject(destination)
                    } catch let error as CocoaError where error.code == .fileWriteFileExists { continue }
                }
                throw DocumentFailure.tooManyEntries
            } catch {
                if FileManager.default.fileExists(atPath: staging.path) {
                    do { try FileManager.default.removeItem(at: staging) }
                    catch let cleanup { throw DocumentFailure.io("\(error.localizedDescription); staging cleanup: \(cleanup.localizedDescription)") }
                }
                throw error
            }
        } catch let error as DocumentFailure { throw error }
        catch { throw DocumentFailure.io(error.localizedDescription) }
    }

    func read(_ url: URL) throws -> DocumentSnapshot {
        try Task.checkCancellation()
        let authority = try readAuthority(url)
        return try scoped(authority) {
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            return DocumentSnapshot(url: canonical, source: try text(canonical),
                                    isReadOnly: dependencyRoot.map { contains(canonical, in: $0) } ?? false)
        }
    }

    func save(_ url: URL, source: String, baseline: String) throws {
        try Task.checkCancellation()
        guard source.utf8.count <= 65_536 else { throw DocumentFailure.sourceTooLarge }
        let authority = try writeAuthority(url)
        try scoped(authority) {
            guard try text(url) == baseline else { throw DocumentFailure.externalModification }
            try Data(source.utf8).write(to: url, options: .atomic)
        }
    }

    func createNumberedSource(in directory: URL) throws -> URL {
        try Task.checkCancellation()
        let authority = try writeAuthority(directory)
        return try scoped(authority) {
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw DocumentFailure.invalidProject("The selected target source directory does not exist.")
            }
            for number in 1...4096 {
                let url = directory.appending(path: "Sound\(number).swift")
                do { try Data("import SwiftMusic\n".utf8).write(to: url, options: .withoutOverwriting); return url }
                catch let error as CocoaError where error.code == .fileWriteFileExists { continue }
            }
            throw DocumentFailure.tooManyEntries
        }
    }

    func bookmark(_ root: URL) throws -> Data {
        try scoped(root) { try root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
    }

    func resolveBookmark(_ data: Data) throws -> URL {
        do {
            var stale = false
            return try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch { throw DocumentFailure.io(error.localizedDescription) }
    }

    private func scoped<Result>(_ url: URL, _ operation: () throws -> Result) throws -> Result {
        let acquired = url.startAccessingSecurityScopedResource()
        defer { if acquired { url.stopAccessingSecurityScopedResource() } }
        do { return try operation() }
        catch let error as DocumentFailure { throw error }
        catch { throw DocumentFailure.io(error.localizedDescription) }
    }

    private func contains(_ child: URL, in parent: URL) -> Bool {
        let path = child.standardizedFileURL.resolvingSymlinksInPath().path
        let base = parent.standardizedFileURL.resolvingSymlinksInPath().path
        return path == base || path.hasPrefix(base + "/")
    }

    private func readAuthority(_ url: URL) throws -> URL {
        if let root, contains(url, in: root) { return root }
        if let dependencyRoot, contains(url, in: dependencyRoot) { return dependencyRoot }
        throw DocumentFailure.outsideProject
    }

    private func writeAuthority(_ url: URL) throws -> URL {
        if let dependencyRoot, contains(url, in: dependencyRoot) { throw DocumentFailure.readOnly }
        guard let root, contains(url, in: root) else { throw DocumentFailure.outsideProject }
        return root
    }

    private func text(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw DocumentFailure.io("Choose a regular text file: \(url.lastPathComponent)") }
        guard (values.fileSize ?? 0) <= 65_536 else { throw DocumentFailure.sourceTooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= 65_536 else { throw DocumentFailure.sourceTooLarge }
        guard let source = String(data: data, encoding: .utf8) else { throw DocumentFailure.io("The file is not UTF-8: \(url.lastPathComponent)") }
        return source
    }

    private func enumerate(_ directory: URL) throws -> [ProjectTreeEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var failure: Error?
        guard let iterator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in failure = error; return false }) else {
            throw DocumentFailure.io("Directory enumeration failed: \(directory.lastPathComponent)")
        }
        var entries: [ProjectTreeEntry] = []
        var count = 0
        for case let url as URL in iterator {
            count += 1
            guard count <= 4096 else { throw DocumentFailure.tooManyEntries }
            let values = try url.resourceValues(forKeys: Set(keys))
            if url.lastPathComponent == ".build" || values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if values.isDirectory == true || values.isRegularFile == true {
                entries.append(ProjectTreeEntry(url: url.standardizedFileURL.resolvingSymlinksInPath(), isDirectory: values.isDirectory == true))
            }
        }
        if let failure { throw failure }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }

    private func staticTargets(_ manifest: String, root: URL) throws -> [ProjectTarget] {
        let tree = Parser.parse(source: manifest)
        guard !tree.hasError else { throw DocumentFailure.invalidProject("Package.swift has parsing errors.") }
        for item in tree.statements {
            guard let declaration = item.item.as(VariableDeclSyntax.self) else { continue }
            for binding in declaration.bindings {
                guard binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "package",
                      let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                      call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Package" else { continue }
                guard let argument = call.arguments.first(where: { $0.label?.text == "targets" }),
                      let array = argument.expression.as(ArrayExprSyntax.self) else {
                    throw DocumentFailure.compilerRequired("Computed package target metadata")
                }
                return try array.elements.compactMap { element in
                    guard let target = element.expression.as(FunctionCallExprSyntax.self),
                          let kind = target.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text else {
                        throw DocumentFailure.compilerRequired("Computed target declarations")
                    }
                    guard ["target", "executableTarget", "testTarget"].contains(kind) else { return nil }
                    guard let nameArgument = target.arguments.first(where: { $0.label?.text == "name" }),
                          let name = literal(nameArgument.expression), !name.isEmpty else {
                        throw DocumentFailure.compilerRequired("Computed target name")
                    }
                    let path: String
                    if let pathArgument = target.arguments.first(where: { $0.label?.text == "path" }) {
                        guard let value = literal(pathArgument.expression) else { throw DocumentFailure.compilerRequired("Computed target path") }
                        path = value
                    } else { path = (kind == "testTarget" ? "Tests/" : "Sources/") + name }
                    guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw DocumentFailure.outsideProject }
                    let directory = root.appending(path: path, directoryHint: .isDirectory).standardizedFileURL.resolvingSymlinksInPath()
                    guard contains(directory, in: root) else { throw DocumentFailure.outsideProject }
                    return ProjectTarget(name: name, sourceDirectory: directory)
                }
            }
        }
        throw DocumentFailure.invalidProject("A literal Package declaration is required for native target selection.")
    }

    private func literal(_ expression: ExprSyntax) -> String? {
        expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    }
}
