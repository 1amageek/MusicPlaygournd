import CryptoKit
import Darwin
import Foundation
import SwiftMusic

/// Evaluates trusted local Swift in a cancellable child process, outside the audio path.
public actor SourceEvaluator {
    private let packageURL: URL
    private let workspace: URL
    private let swiftExecutable: String
    private let runtimeSDK: URL?
    private let projectBuildCache: URL?
    private struct CompilerEnvironment: Decodable {
        let artifactDigests: [String: String]
        let compilerVersion: String
        let sdkPath: String
        let pluginPath: String
        let target: String
    }
    private var compilerEnvironment: CompilerEnvironment?
    private var binaryDirectory: String?
    private var busy = false
    private struct Worker {
        let revision: UInt64
        let connection: RenderWorkerConnection
        let directory: URL
        var resultLines: [Int: Int]
        let source: String
        let ast: Data
        let prefixBytes: Int
        var performanceControls: [PerformanceControlMetadata]
        var switchBank: PreparedSwitchBank?
        var switchIndex: Int = 0
        var performanceGenerationOffset: UInt64 = 0
        var confirmedPerformanceGeneration: UInt64 = 0
        var latestPerformanceGeneration: UInt64 = 0
        var pendingPerformance: PerformanceCandidate?
    }
    private struct PerformanceCandidate {
        let generation: UInt64
        let evaluation: RetainedEvaluation
        var adoptionRequested = false
        var acknowledged = false
    }
    private var audiblePerformanceControls: [PerformanceControlMetadata] = []
    private var adopted: Worker?
    private var candidate: Worker?
    private var exportingWorker: Worker?
    private var retiredExportWorker: Worker?


    public init(packageURL: URL, workspace: URL, swiftExecutable: String, runtimeSDK: URL? = nil, projectBuildCache: URL? = nil) {
        self.packageURL = packageURL
        self.workspace = workspace
        self.swiftExecutable = swiftExecutable
        self.runtimeSDK = runtimeSDK?.resolvingSymlinksInPath()
        self.projectBuildCache = projectBuildCache
    }

    private func acquireProjectCacheLock(required: Bool) async throws -> Int32? {
        guard required, let projectBuildCache else { return nil }
        try FileManager.default.createDirectory(at: projectBuildCache, withIntermediateDirectories: true)
        let descriptor = open(projectBuildCache.appending(path: "build.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw EvaluationError.processFailed("Cannot open project build cache lock: \(errno)") }
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(240))
            while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                guard errno == EWOULDBLOCK || errno == EAGAIN else {
                    throw EvaluationError.processFailed("Cannot lock project build cache: \(errno)")
                }
                guard ContinuousClock.now < deadline else {
                    throw EvaluationError.processFailed("Another project build is still using the compiler cache.")
                }
                try await Task.sleep(for: .milliseconds(40))
            }
            try Task.checkCancellation()
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func resolveCompilerEnvironment() async throws -> CompilerEnvironment {
        if let compilerEnvironment { return compilerEnvironment }
        let environment: CompilerEnvironment
        let manager = FileManager.default
        if let runtimeSDK {
            do {
                environment = try JSONDecoder().decode(CompilerEnvironment.self,
                    from: Data(contentsOf: runtimeSDK.appending(path: "environment.json")))
            } catch { throw EvaluationError.invalidResult("The bundled runtime SDK is unreadable: \(error)") }
            for name in ["SwiftMusic.o", "MusicPlayground.o", "MusicPlaygourndCore.o", "SwiftMusic.swiftmodule", "MusicPlayground.swiftmodule", "MusicPlaygourndCore.swiftmodule"] {
                guard manager.fileExists(atPath: runtimeSDK.appending(path: name).path) else {
                    throw EvaluationError.invalidResult("The bundled runtime SDK is missing \(name). Rebuild the app.")
                }
            }
            guard !environment.artifactDigests.isEmpty else {
                throw EvaluationError.invalidResult("The runtime SDK artifact manifest is empty.")
            }
            do {
                let files: Set<String> = try {
                var files = Set<String>()
                for name in ["SwiftMusic.o", "MusicPlayground.o", "MusicPlaygourndCore.o", "SwiftMusic.swiftmodule", "MusicPlayground.swiftmodule", "MusicPlaygourndCore.swiftmodule"] {
                    let root = runtimeSDK.appending(path: name)
                    let values = try root.resourceValues(forKeys: [.isDirectoryKey])
                    if values.isDirectory == true {
                        guard let entries = manager.enumerator(atPath: root.path) else {
                            throw EvaluationError.invalidResult("Unable to enumerate runtime SDK artifacts.")
                        }
                        for case let relative as String in entries {
                            let file = root.appending(path: relative)
                            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                                files.insert(name + "/" + relative)
                            }
                        }
                    } else { files.insert(name) }
                }
                return files
                }()
                guard files == Set(environment.artifactDigests.keys) else {
                    throw EvaluationError.invalidResult("The runtime SDK artifact set has changed. Rebuild the app.")
                }
                for (path, digest) in environment.artifactDigests {
                    guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
                        throw EvaluationError.invalidResult("The runtime SDK artifact path is invalid.")
                    }
                    let data = try Data(contentsOf: runtimeSDK.appending(path: path), options: .mappedIfSafe)
                    let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard actual == digest else {
                        throw EvaluationError.invalidResult("The runtime SDK artifact has changed: \(path). Rebuild the app.")
                    }
                }
            } catch {
                throw EvaluationError.invalidResult("The runtime SDK artifact validation failed: \(error)")
            }
            let version = try await run(swiftExecutable, ["--version"], timeout: 10)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard version == environment.compilerVersion else {
                throw EvaluationError.invalidResult("The runtime SDK compiler has changed. Rebuild the app.")
            }
            guard !environment.target.isEmpty else { throw EvaluationError.invalidResult("The runtime SDK target is missing.") }
        } else {
            let sdk = try await run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"], timeout: 20)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            struct TargetInfo: Decodable {
                struct Paths: Decodable { let runtimeResourcePath: String }
                let paths: Paths
            }
            let output = try await run(swiftExecutable, ["-print-target-info"], timeout: 10)
            let info: TargetInfo
            do { info = try JSONDecoder().decode(TargetInfo.self, from: Data(output.utf8)) }
            catch { throw EvaluationError.invalidResult("Unable to read compiler resource paths: \(error)") }
            environment = CompilerEnvironment(artifactDigests: [:], compilerVersion: "", sdkPath: sdk,
                pluginPath: URL(fileURLWithPath: info.paths.runtimeResourcePath).appending(path: "host/plugins").path, target: "")
        }
        for path in [environment.sdkPath, environment.pluginPath] {
            var isDirectory: ObjCBool = false
            guard path.hasPrefix("/"), manager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw EvaluationError.invalidResult("A compiler SDK or plugin directory is unavailable: \(path)")
            }
        }
        compilerEnvironment = environment
        return environment
    }

    internal func workerStateForTests() async -> (pid: pid_t?, exporting: UInt64?, retired: UInt64?) {
        let worker = adopted
        let exporting = exportingWorker?.revision
        let retired = retiredExportWorker?.revision
        return (await worker?.connection.processIdentifierForTests, exporting, retired)
    }

    public func format(source: String) async throws -> String {
        guard source.utf8.count <= 65_536 else {
            throw EvaluationError.invalidSource("Source exceeds the 64 KiB editor limit.")
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "SwiftMusic-Format-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = SourceEvaluator(packageURL: packageURL, workspace: directory, swiftExecutable: swiftExecutable)
        do {
            let file = directory.appending(path: "Session.swift")
            try source.write(to: file, atomically: true, encoding: .utf8)
            _ = try await formatter.run(swiftExecutable,
                ["format", "--in-place", "--configuration", #"{"indentation":{"spaces":4}}"#, file.path], timeout: 10)
            let output = try String(contentsOf: file, encoding: .utf8)
            guard output.utf8.count <= 65_536 else {
                throw EvaluationError.invalidSource("Formatted source exceeds the 64 KiB editor limit.")
            }
            try FileManager.default.removeItem(at: directory)
            return output
        } catch {
            let failure = error
            do { try FileManager.default.removeItem(at: directory) }
            catch { throw EvaluationError.invalidResult("Formatter cleanup failed: \(error); formatting failed: \(failure)") }
            throw failure
        }
    }

    public func evaluate(source: String, bpm: Double, beatsPerBar: Int) async throws -> PreparedLoop {
        let result = try await evaluateRetained(source: source, bpm: bpm, beatsPerBar: beatsPerBar, revision: 0)
        await discard(revision: 0)
        return result.loop
    }

    public func openProject(at root: URL, resolveDependencies: Bool = false, progress: (@Sendable (String) async -> Void)? = nil) async throws -> SwiftPackageProject {
        while busy { try await Task.sleep(for: .milliseconds(40)) }
        busy = true
        defer { busy = false }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: root.appending(path: "Package.swift").path) else {
            throw EvaluationError.invalidSource("Select a folder containing Package.swift.")
        }
        await progress?(resolveDependencies ? "Resolving package dependencies…" : "Loading package…")
        _ = try await run(swiftExecutable, ["package", "--package-path", root.path, "resolve"], timeout: 120, progress: progress)
        let description = try await run(swiftExecutable, ["package", "--package-path", root.path, "describe", "--type", "json"], timeout: 60)
        var project = try SwiftPackageProject.decode(Data(description.utf8), root: root)
        await progress?("Loading package dependencies…")
        let graph = try await run(swiftExecutable, ["package", "--package-path", root.path,
            "show-dependencies", "--format", "json"], timeout: 120, progress: progress)
        try project.loadResolvedDependencies(Data(graph.utf8))
        return project
    }

    public func evaluateRetained(source: String, bpm: Double, beatsPerBar: Int,
                                 revision: UInt64, project: ProjectEvaluationRequest? = nil, progress: (@Sendable (String) async -> Void)? = nil) async throws -> RetainedEvaluation {
        // An actor may reenter at every await. This slot also protects the incremental workspace.
        while busy {
            try await Task.sleep(for: .milliseconds(40))
        }
        try Task.checkCancellation()
        busy = true
        defer { busy = false }
        if let previous = candidate {
            candidate = nil
            await previous.connection.shutdown()
            try FileManager.default.removeItem(at: previous.directory)
        }
        guard source.utf8.count <= 65_536 else {
            throw EvaluationError.invalidSource("Source exceeds the 64 KiB editor limit.")
        }
        guard bpm.isFinite, (40...240).contains(bpm), (2...7).contains(beatsPerBar) else {
            throw EvaluationError.invalidSource("Tempo must be 40–240 BPM and meter 2/4–7/4.")
        }
        let manager = FileManager.default
        let workerDirectory = workspace.appending(path: "Worker-" + UUID().uuidString)
        await progress?("Preparing package build…")
        let cacheLock = try await acquireProjectCacheLock(required: project != nil)
        defer { if let cacheLock { flock(cacheLock, LOCK_UN); close(cacheLock) } }
        let projectRoot = projectBuildCache?.appending(path: "Project") ?? workspace.appending(path: "Project")
        let projectWorkspace = try project.map { try ProjectWorkspace.prepare($0, at: projectRoot, host: packageURL) }
        let buildRoot = projectWorkspace?.root ?? workspace
        let product = projectWorkspace == nil ? "Evaluation" : "MusicPlaygourndEvaluation"
        let sources = workspace.appending(path: "Sources/Evaluation")
        let entryFile = projectWorkspace?.entry ?? sources.appending(path: "Session.swift")
        try manager.createDirectory(at: sources, withIntermediateDirectories: true)
        let manifest = """
        // swift-tools-version: 6.4
        import PackageDescription
        let package = Package(
            name: "MusicPlaygourndEvaluation",
            platforms: [.macOS(.v15)],
            dependencies: [
                .package(url: "https://github.com/1amageek/SwiftMusic.git", exact: "0.4.0"),
                .package(path: \(Self.swiftLiteral(packageURL.path)))
            ],
            targets: [.executableTarget(name: "Evaluation", dependencies: [
                .product(name: "MusicPlaygourndCore", package: "MusicPlaygournd"),
                .product(name: "SwiftMusic", package: "SwiftMusic")
            ])]
        )
        """
        let manifestURL = workspace.appending(path: "Package.swift")
        if try !manager.fileExists(atPath: manifestURL.path) || String(contentsOf: manifestURL, encoding: .utf8) != manifest {
            try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        }
        let output = workerDirectory.appending(path: "prepared.plist")
        if manager.fileExists(atPath: output.path) { try manager.removeItem(at: output) }
        let maximumLiveBeats = Int(min(
            PreparedLoop.maximumBeatCount,
            (PreparedLoop.maximumDurationSeconds * bpm / 60).rounded(.down)
        ))
        let wrapper = Self.makeWrapper(
            source: source,
            revision: revision,
            bpm: bpm,
            beatsPerBar: beatsPerBar,
            maximumLiveBeats: maximumLiveBeats,
            output: output,
            discovery: nil
        )
        try wrapper.write(to: entryFile, atomically: true, encoding: .utf8)
        let environment = try await resolveCompilerEnvironment()
        let binaryPath: String
        let executable: URL
        try manager.createDirectory(at: workerDirectory, withIntermediateDirectories: true)
        do {
        if let runtimeSDK, projectWorkspace == nil {
            binaryPath = runtimeSDK.path
            executable = workerDirectory.appending(path: "Evaluation")
            let compiler = URL(fileURLWithPath: swiftExecutable).deletingLastPathComponent().appending(path: "swiftc")
            _ = try await run(compiler.path, ["-parse-as-library", "-O", "-target", environment.target,
                "-sdk", environment.sdkPath, "-I", runtimeSDK.path,
                entryFile.path,
                runtimeSDK.appending(path: "SwiftMusic.o").path,
                runtimeSDK.appending(path: "MusicPlayground.o").path,
                runtimeSDK.appending(path: "MusicPlaygourndCore.o").path,
                "-o", executable.path], timeout: 60, progress: progress)
        } else {
            _ = try await run(swiftExecutable, ["build", "--configuration", "release", "--build-system", "native", "-Xswiftc", "-Xfrontend", "-Xswiftc", "-disable-round-trip-debug-types", "--package-path", buildRoot.path, "--product", product], timeout: 240, progress: progress)
            if let binaryDirectory, projectWorkspace == nil { binaryPath = binaryDirectory }
            else {
                let output = try await run(swiftExecutable, ["build", "--configuration", "release", "--build-system", "native", "--package-path", buildRoot.path, "--show-bin-path"], timeout: 20)
                let paths = output.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("/") }
                guard paths.count == 1, let path = paths.first else {
                    throw EvaluationError.invalidResult("SwiftPM did not report one absolute binary directory.")
                }
                binaryPath = String(path)
                if projectWorkspace == nil { binaryDirectory = binaryPath }
            }
            executable = URL(fileURLWithPath: binaryPath).appending(path: product)
        }
        } catch {
            let original = error
            do { try manager.removeItem(at: workerDirectory) }
            catch { throw EvaluationError.invalidResult("Compilation failed: \(original); worker cleanup failed: \(error)") }
            throw original
        }
        let prefix = "import Foundation\nimport SwiftMusic\nimport MusicPlaygourndCore\n"
        let displaySource = workspace.appending(path: "ResultLocations.swift")
        try (prefix + source).write(to: displaySource, atomically: true, encoding: .utf8)
        var astArguments = ["-frontend", "-dump-ast", "-dump-ast-format", "json", "-suppress-warnings",
            "-plugin-path", environment.pluginPath, "-sdk", environment.sdkPath,
            "-I", binaryPath, "-I", URL(fileURLWithPath: binaryPath).appending(path: "Modules").path]
        if !environment.target.isEmpty { astArguments += ["-target", environment.target] }
        if let projectWorkspace, let project {
            astArguments = try projectWorkspace.astArguments(binaryPath: binaryPath, module: project.target.moduleName, displaySource: displaySource)
        } else {
            astArguments.append(displaySource.path)
        }
        let astOutput = try await run(swiftExecutable, astArguments, timeout: 20)
        let ast = Data(astOutput.utf8)
        let discovery = try SwitchBankDiscovery.discover(
            ast: ast,
            source: source,
            prefixBytes: prefix.utf8.count
        )
        if discovery.isSupported {
            let switchedWrapper = Self.makeWrapper(
                source: source,
                revision: revision,
                bpm: bpm,
                beatsPerBar: beatsPerBar,
                maximumLiveBeats: maximumLiveBeats,
                output: output,
                discovery: discovery
            )
            try switchedWrapper.write(to: entryFile, atomically: true, encoding: .utf8)
            do {
                if let runtimeSDK, projectWorkspace == nil {
                    let compiler = URL(fileURLWithPath: swiftExecutable).deletingLastPathComponent().appending(path: "swiftc")
                    _ = try await run(compiler.path, ["-parse-as-library", "-O", "-target", environment.target,
                        "-sdk", environment.sdkPath, "-I", runtimeSDK.path,
                        entryFile.path,
                        runtimeSDK.appending(path: "SwiftMusic.o").path,
                        runtimeSDK.appending(path: "MusicPlayground.o").path,
                        runtimeSDK.appending(path: "MusicPlaygourndCore.o").path,
                        "-o", executable.path], timeout: 60, progress: progress)
                } else {
                    _ = try await run(swiftExecutable, ["build", "--configuration", "release", "--build-system", "native",
                        "-Xswiftc", "-Xfrontend", "-Xswiftc", "-disable-round-trip-debug-types",
                        "--package-path", buildRoot.path, "--product", product], timeout: 240, progress: progress)
                }
            } catch {
                throw EvaluationError.processFailed("Switch variant preparation failed: \(error.localizedDescription)")
            }
        }
        await progress?("Preparing audio…")
        let connection = try RenderWorkerConnection(
            executable: executable,
            outputURL: output, revision: revision, workingDirectory: project?.project.root)
        do {
        var initial = try await connection.ready()
        var performanceGenerationOffset: UInt64 = 0
        var transferIssue: PerformanceControlError?
        let acceptedControls = audiblePerformanceControls
        if !acceptedControls.isEmpty {
            if Self.samePerformanceSchema(acceptedControls, initial.performanceControls) {
                initial = try await connection.renderPerformance(
                    values: Dictionary(uniqueKeysWithValues: acceptedControls.map { ($0.controlID, $0.value) }),
                    overrides: [], generation: 1)
                guard await connection.adoptPerformance(generation: 1) else {
                    throw EvaluationError.invalidResult("The candidate worker did not accept transferred performance values.")
                }
                performanceGenerationOffset = 1
            } else {
                transferIssue = .invalidMapping("The edited performance schema differs; source-declared initial values are used.")
            }
        }
        let loop = initial.loop
        let resultLines = try ExpressionResultLocations.lines(ast: ast, source: source, prefixBytes: prefix.utf8.count, rows: loop.rows)
        let located = PreparedLoop(sampleRate: loop.sampleRate, bpm: loop.bpm, beatsPerBar: loop.beatsPerBar,
            beatCount: loop.beatCount, samples: loop.samples, events: loop.events,
            rows: loop.rows.map { row in
                LoopRow(sourceID: row.sourceID, label: row.label, anchor: row.anchor, peaks: row.peaks,
                    patternText: row.patternText, resultLine: resultLines[row.sourceID], trackID: row.trackID)
            }, meters: loop.meters)
        try located.validate()
        try Task.checkCancellation()
        let locatedSwitchBank: PreparedSwitchBank?
        if let bank = initial.switchBank {
            let variants = try bank.variants.map { variant in
                try SwitchVariant(
                    selection: variant.selection,
                    loop: Self.locate(variant.loop, ast: ast, source: source, prefixBytes: prefix.utf8.count),
                    catalog: variant.catalog,
                    metadata: variant.metadata
                )
            }
            locatedSwitchBank = try PreparedSwitchBank(
                controls: bank.controls,
                variants: variants,
                initialIndex: bank.initialIndex
            )
        } else {
            locatedSwitchBank = nil
        }
        candidate = Worker(revision: revision, connection: connection,
                           directory: workerDirectory, resultLines: resultLines, source: source,
                           ast: ast, prefixBytes: prefix.utf8.count,
                           performanceControls: initial.performanceControls,
                           switchBank: locatedSwitchBank,
                           switchIndex: initial.switchBank?.initialIndex ?? 0,
                           performanceGenerationOffset: performanceGenerationOffset)
        return RetainedEvaluation(
            loop: located,
            catalog: initial.catalog,
            metadata: initial.metadata,
            performanceControls: initial.performanceControls,
            performanceTransferIssue: transferIssue,
            switchBank: locatedSwitchBank,
            switchIssues: discovery.issues
        )
        } catch let error as EvaluationError {
            await connection.shutdown()
            try manager.removeItem(at: workerDirectory)
            if case .workerCompilerDiagnostic(let diagnostic) = error {
                let range: SourceDiagnosticRange?
                do {
                    range = try ExpressionResultLocations.diagnosticRange(source: source, diagnostic: diagnostic)
                } catch {
                    range = nil
                }
                throw EvaluationError.compilerDiagnostic(message: diagnostic.message, range: range)
            }
            throw error
        } catch {
            await connection.shutdown()
            try manager.removeItem(at: workerDirectory)
            throw error
        }
    }

    @discardableResult public func adopt(revision: UInt64) async -> Bool {
        if let adopted, adopted.revision == revision { return await adopted.connection.isAvailable }
        guard let next = candidate, next.revision == revision,
              await next.connection.isAvailable else { return false }
        guard candidate?.revision == revision else { return false }
        let previous = adopted
        adopted = next
        audiblePerformanceControls = next.performanceControls
        candidate = nil
        if let previous {
            if exportingWorker?.revision == previous.revision {
                retiredExportWorker = previous
            } else {
                await previous.connection.shutdown()
                do { try FileManager.default.removeItem(at: previous.directory) }
                catch { /* Workspace cleanup is retried by shutdown. */ }
            }
        }
        return await controlsAvailable(revision: revision)
    }

    public func controlsAvailable(revision: UInt64) async -> Bool {
        guard let worker = adopted, worker.revision == revision else { return false }
        let available = await worker.connection.isAvailable
        return available && adopted?.revision == revision
    }

    /// Selects a precompiled Swift switch variant without recompiling or rendering.
    /// The caller supplies the host audio generation that already contains the cached PCM.
    public func selectSwitchVariant(
        index: Int,
        revision: UInt64,
        generation: UInt64 = 0
    ) async throws -> Bool {
        guard let worker = adopted, worker.revision == revision,
              let bank = worker.switchBank,
              bank.variants.indices.contains(index) else {
            throw EvaluationError.invalidResult("The adopted source has no available Swift switch variant.")
        }
        let accepted = try await worker.connection.selectSwitchVariant(index: index, generation: generation)
        guard accepted else { return false }
        guard adopted?.revision == revision else { throw CancellationError() }
        let selected = bank.variants[index].loop
        adopted?.switchIndex = index
        adopted?.resultLines = Dictionary(uniqueKeysWithValues: selected.rows.compactMap { row in
            row.resultLine.map { (row.sourceID, $0) }
        })
        return true
    }

    public func discard(revision: UInt64) async {
        guard let value = candidate, value.revision == revision else { return }
        candidate = nil
        await value.connection.shutdown()
        do { try FileManager.default.removeItem(at: value.directory) }
        catch { /* Workspace cleanup is retried by shutdown. */ }
    }

    public func render(overrides: [LiveControlOverride], revision: UInt64,
                       generation: UInt64) async throws -> PreparedLoop {
        guard let worker = adopted, worker.revision == revision else {
            throw EvaluationError.invalidResult("Control revision is not adopted.")
        }
        let loop = try await worker.connection.render(overrides: overrides, generation: generation)
        guard adopted?.revision == revision else { throw CancellationError() }
        let located = PreparedLoop(sampleRate: loop.sampleRate, bpm: loop.bpm,
            beatsPerBar: loop.beatsPerBar, beatCount: loop.beatCount, samples: loop.samples,
            events: loop.events, rows: loop.rows.map {
                LoopRow(sourceID: $0.sourceID, label: $0.label, anchor: $0.anchor, peaks: $0.peaks,
                        patternText: $0.patternText, resultLine: worker.resultLines[$0.sourceID], trackID: $0.trackID)
            }, meters: loop.meters)
        try located.validate()
        return located
    }

    /// Prepares a complete model value set without accepting it for playback or hot edits.
    public func renderPerformance(
        values: [String: PerformanceControlValue],
        overrides: [LiveControlOverride] = [],
        revision: UInt64,
        generation: UInt64
    ) async throws -> RetainedEvaluation {
        try Task.checkCancellation()
        guard let worker = adopted, worker.revision == revision else {
            throw EvaluationError.invalidResult("Performance revision is not adopted.")
        }
        guard worker.pendingPerformance?.adoptionRequested != true else {
            throw EvaluationError.invalidResult("Performance adoption is awaiting audible confirmation.")
        }
        guard generation > worker.latestPerformanceGeneration else {
            throw EvaluationError.invalidResult("Performance generation is stale.")
        }
        let wire = try Self.wireGeneration(generation, in: worker)
        adopted?.latestPerformanceGeneration = generation
        adopted?.pendingPerformance = nil
        do {
            if let previous = worker.pendingPerformance {
                await worker.connection.discardPerformance(generation: try Self.wireGeneration(previous.generation, in: worker))
            }
            try Task.checkCancellation()
            guard adopted?.revision == revision, adopted?.latestPerformanceGeneration == generation else {
                throw CancellationError()
            }
            let result = try await worker.connection.renderPerformance(
                values: values, overrides: overrides, generation: wire)
            try Task.checkCancellation()
            guard adopted?.revision == revision,
                  adopted?.latestPerformanceGeneration == generation else { throw CancellationError() }
            let located = try Self.locate(result.loop, in: worker)
            let prepared = RetainedEvaluation(loop: located, catalog: result.catalog,
                metadata: result.metadata, performanceControls: result.performanceControls)
            adopted?.pendingPerformance = PerformanceCandidate(generation: generation, evaluation: prepared)
            return prepared
        } catch {
            if let wire = Self.checkedWireGeneration(generation, in: worker) {
                await worker.connection.discardPerformance(generation: wire)
            }
            if case EvaluationError.workerCompilerDiagnostic(let diagnostic) = error {
                let range = try ExpressionResultLocations.diagnosticRange(source: worker.source, diagnostic: diagnostic)
                throw EvaluationError.compilerDiagnostic(message: diagnostic.message, range: range)
            }
            throw error
        }
    }

    /// Acknowledges an admitted candidate. The host confirms it after the audio fade completes.
    @discardableResult
    public func adoptPerformance(revision: UInt64, generation: UInt64) async -> Bool {
        guard let worker = adopted, worker.revision == revision else { return false }
        if worker.confirmedPerformanceGeneration == generation, generation > 0 { return true }
        guard let pending = worker.pendingPerformance, pending.generation == generation else { return false }
        if pending.acknowledged { return true }
        guard !pending.adoptionRequested else { return false }
        adopted?.pendingPerformance?.adoptionRequested = true
        guard let wire = Self.checkedWireGeneration(generation, in: worker) else { return false }
        let accepted = await worker.connection.adoptPerformance(generation: wire)
        guard adopted?.revision == revision,
              adopted?.pendingPerformance?.generation == generation else { return false }
        if accepted {
            adopted?.pendingPerformance?.acknowledged = true
            adopted?.resultLines = Dictionary(uniqueKeysWithValues: pending.evaluation.loop.rows.compactMap { row in
                row.resultLine.map { (row.sourceID, $0) }
            })
        }
        else { adopted?.pendingPerformance = nil }
        return accepted
    }

    /// Releases an unacknowledged candidate. An active handshake must finish first.
    public func discardPerformance(revision: UInt64, generation: UInt64) async {
        guard let worker = adopted, worker.revision == revision,
              worker.pendingPerformance?.generation == generation,
              worker.pendingPerformance?.adoptionRequested != true else { return }
        adopted?.pendingPerformance = nil
        if let wire = Self.checkedWireGeneration(generation, in: worker) {
            await worker.connection.discardPerformance(generation: wire)
        }
    }

    /// Confirms the generation reported as fully audible by PlaybackSnapshot.
    @discardableResult
    public func confirmPerformance(revision: UInt64, generation: UInt64) -> Bool {
        guard let worker = adopted, worker.revision == revision else { return false }
        if worker.confirmedPerformanceGeneration == generation, generation > 0 { return true }
        guard let pending = worker.pendingPerformance, pending.generation == generation,
              pending.acknowledged else { return false }
        audiblePerformanceControls = pending.evaluation.performanceControls
        adopted?.performanceControls = pending.evaluation.performanceControls
        adopted?.confirmedPerformanceGeneration = generation
        adopted?.pendingPerformance = nil
        return true
    }

    private static func checkedWireGeneration(_ generation: UInt64, in worker: Worker) -> UInt64? {
        let (wire, overflow) = generation.addingReportingOverflow(worker.performanceGenerationOffset)
        return overflow ? nil : wire
    }

    private static func wireGeneration(_ generation: UInt64, in worker: Worker) throws -> UInt64 {
        guard let wire = checkedWireGeneration(generation, in: worker) else {
            throw EvaluationError.invalidResult("Performance generation limit reached.")
        }
        return wire
    }

    private static func samePerformanceSchema(
        _ lhs: [PerformanceControlMetadata], _ rhs: [PerformanceControlMetadata]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let other = Dictionary(uniqueKeysWithValues: rhs.map { ($0.controlID, $0) })
        return lhs.allSatisfy { control in
            guard let value = other[control.controlID] else { return false }
            return control.modelID == value.modelID && control.domain == value.domain
        }
    }

    private static func locate(_ loop: PreparedLoop, in worker: Worker) throws -> PreparedLoop {
        try locate(loop, ast: worker.ast, source: worker.source, prefixBytes: worker.prefixBytes)
    }

    private static func locate(
        _ loop: PreparedLoop,
        ast: Data,
        source: String,
        prefixBytes: Int
    ) throws -> PreparedLoop {
        let lines = try ExpressionResultLocations.lines(
            ast: ast,
            source: source,
            prefixBytes: prefixBytes,
            rows: loop.rows
        )
        let result = PreparedLoop(sampleRate: loop.sampleRate, bpm: loop.bpm,
            beatsPerBar: loop.beatsPerBar, beatCount: loop.beatCount, samples: loop.samples,
            events: loop.events, rows: loop.rows.map { row in
                LoopRow(sourceID: row.sourceID, label: row.label, anchor: row.anchor, peaks: row.peaks,
                    patternText: row.patternText, resultLine: lines[row.sourceID], trackID: row.trackID)
            }, meters: loop.meters)
        try result.validate()
        return result
    }

    /// Samples one selected control through the retained worker without changing PCM or render generation.
    public func visualization(
        address: LiveControlAddress,
        overrides: [LiveControlOverride] = [],
        revision: UInt64,
        selectionGeneration: UInt64
    ) async throws -> PreparedControlVisualization {
        guard address.revision == revision else {
            throw LiveControlError.staleRevision(expected: revision, actual: address.revision)
        }
        guard let worker = adopted, worker.revision == revision else {
            throw EvaluationError.invalidResult("Control revision is not adopted.")
        }
        let result = try await worker.connection.visualization(
            address: address,
            overrides: overrides,
            selectionGeneration: selectionGeneration
        )
        guard adopted?.revision == revision else { throw CancellationError() }
        return result
    }

    /// Exports the adopted retained session's Track stems without replacing its loop result.
    public func exportStems(
        revision: UInt64,
        generation: UInt64,
        overrides: [LiveControlOverride],
        destination: URL
    ) async throws -> StemExportSnapshot {
        guard destination.isFileURL, destination.path.hasPrefix("/"), destination.path != "/" else {
            throw StemExportError.invalidDestination
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw StemExportError.destinationExists
        }
        guard let worker = adopted, worker.revision == revision else {
            throw EvaluationError.invalidResult("Control revision is not adopted.")
        }
        guard exportingWorker == nil else {
            throw EvaluationError.invalidResult("A stem export is already in progress.")
        }
        exportingWorker = worker
        do {
            let snapshot = try await worker.connection.exportStems(
                overrides: overrides,
                generation: generation,
                destination: destination
            )
            guard snapshot.revision == revision, snapshot.generation == generation else {
                throw EvaluationError.invalidResult("Stem export snapshot identity does not match its request.")
            }
            await finishExport(worker)
            return snapshot
        } catch {
            await finishExport(worker)
            throw error
        }
    }

    private func finishExport(_ worker: Worker) async {
        guard exportingWorker?.revision == worker.revision else { return }
        exportingWorker = nil
        let remainsAdopted = adopted?.revision == worker.revision
        if retiredExportWorker?.revision == worker.revision {
            retiredExportWorker = nil
        }
        guard !remainsAdopted else { return }
        await worker.connection.shutdown()
        do { try FileManager.default.removeItem(at: worker.directory) }
        catch { /* Workspace cleanup is retried by shutdown. */ }
    }

    /// Call after cancelling the caller's evaluation task; waits for child cleanup before removing scratch data.
    public func shutdown() async throws {
        while busy { try await Task.sleep(for: .milliseconds(40)) }
        let allWorkers = [adopted, candidate, retiredExportWorker, exportingWorker].compactMap { $0 }
        var workers = [Worker]()
        for worker in allWorkers where !workers.contains(where: { $0.revision == worker.revision }) {
            workers.append(worker)
        }
        adopted = nil
        audiblePerformanceControls = []
        candidate = nil
        exportingWorker = nil
        retiredExportWorker = nil
        for worker in workers { await worker.connection.shutdown() }
        if FileManager.default.fileExists(atPath: workspace.path) {
            try FileManager.default.removeItem(at: workspace)
        }
    }

    internal func run(_ executable: String, _ arguments: [String], timeout: Double, progress: (@Sendable (String) async -> Void)? = nil) async throws -> String {
        try Task.checkCancellation()
        let log = workspace.appending(path: "process.log")
        try Data().write(to: log)
        let output = try FileHandle(forWritingTo: log)
        defer { do { try output.close() } catch { /* Closing an already-finished diagnostic file cannot alter playback. */ } }
        let reader = try progress == nil ? nil : FileHandle(forReadingFrom: log)
        defer { if let reader { do { try reader.close() } catch { } } }
        var pending = Data()
        let process = Process()
        let completion = ProcessCompletion()
        process.terminationHandler = { @Sendable task in
            completion.finish(status: task.terminationStatus, exited: task.terminationReason == .exit)
        }
        // Start a process group so cancellation also terminates swiftc and evaluated child processes.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", Self.processRunner, executable] + arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        do {
            while completion.result == nil {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw EvaluationError.timedOut("Evaluation exceeded \(Int(timeout)) seconds. The previous loop is still available.")
                }
                let size = try FileManager.default.attributesOfItem(atPath: log.path)[.size] as? NSNumber
                guard (size?.intValue ?? 0) <= 1_048_576 else {
                    throw EvaluationError.processFailed("Compiler or session output exceeded 1 MiB.")
                }
                if let reader, let chunk = try reader.read(upToCount: 65_536), !chunk.isEmpty {
                    pending.append(chunk)
                    if let newline = pending.lastIndex(of: 10) {
                        let lines = String(decoding: pending[...newline], as: UTF8.self).split(whereSeparator: \.isNewline)
                        if let line = lines.last(where: { $0.hasPrefix("Fetching ") || $0.hasPrefix("Fetched ") || $0.hasPrefix("Computing ") || $0.hasPrefix("Computed ") || $0.hasPrefix("Creating working copy") || $0.hasPrefix("Working copy") || $0.hasPrefix("Building ") || $0.hasPrefix("[") }) {
                            await progress?(String(line.prefix(300)))
                        }
                        pending.removeSubrange(...newline)
                    }
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            let pid = process.processIdentifier
            // Let the launcher stop and reap compiler descendants in their own groups.
            if process.isRunning { kill(pid, SIGTERM) }
            // Cleanup must finish even when the evaluating Task is cancelled. Foundation's
            // termination handler reaps the child; waitUntilExit can deadlock across actor hops.
            let cleanup = Task.detached {
                while completion.result == nil { try await Task.sleep(for: .milliseconds(20)) }
            }
            try await cleanup.value
            if completion.result?.status == 70 {
                let detail = String(decoding: try Data(contentsOf: log), as: UTF8.self)
                throw EvaluationError.processFailed("\(error.localizedDescription)\n\(detail)")
            }
            throw error
        }
        // A session may start descendants; none should outlive evaluation.
        kill(-process.processIdentifier, SIGKILL)
        let data = try Data(contentsOf: log)
        guard data.count <= 1_048_576 else { throw EvaluationError.processFailed("Diagnostic output exceeded 1 MiB.") }
        let message = String(decoding: data, as: UTF8.self)
        guard let result = completion.result, result.exited, result.status == 0 else {
            throw EvaluationError.processFailed(message.isEmpty ? "The Swift process failed." : message)
        }
        try Task.checkCancellation()
        return message
    }

    // The pipe collector holds one 64 KiB chunk and writes at most 1 MiB to the log.
    // The group contains this launcher and its ordinary compiler/session descendants.
    private static let processRunner = """
    import ctypes, errno, os, signal, subprocess, sys, time
    native = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    native.proc_listchildpids.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
    native.proc_listchildpids.restype = ctypes.c_int
    class BSDInfo(ctypes.Structure):
        # Matches macOS sys/proc_info.h proc_bsdinfo; all borrows remain in this launcher.
        _fields_ = [("ids", ctypes.c_uint32 * 12), ("command", ctypes.c_char * 16),
                    ("name", ctypes.c_char * 32), ("values", ctypes.c_uint32 * 6),
                    ("seconds", ctypes.c_uint64), ("microseconds", ctypes.c_uint64)]
    native.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
    native.proc_pidinfo.restype = ctypes.c_int
    def identity(pid):
        value = BSDInfo()
        ctypes.set_errno(0)
        size = native.proc_pidinfo(pid, 3, 0, ctypes.byref(value), ctypes.sizeof(value))
        if size == 0 and ctypes.get_errno() == errno.ESRCH:
            return None
        if size != ctypes.sizeof(value):
            raise RuntimeError("Unable to identify compiler descendant")
        return (value.seconds, value.microseconds)
    def children(pid):
        capacity = max(1, native.proc_listchildpids(pid, None, 0))
        storage = (ctypes.c_int * capacity)()
        count = native.proc_listchildpids(pid, storage, ctypes.sizeof(storage))
        if count < 0 or count > capacity:
            raise RuntimeError("Unable to enumerate compiler descendants")
        return [storage[index] for index in range(count)]
    def terminate_tree(pid, owned):
        try:
            os.kill(pid, signal.SIGSTOP)
        except ProcessLookupError:
            return
        stamp = identity(pid)
        if stamp is not None:
            owned.append((pid, stamp))
        # A stopped parent cannot spawn or reap children, keeping their identities stable.
        for descendant in children(pid):
            terminate_tree(descendant, owned)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    def cleanup():
        owned = []
        for pid in children(os.getpid()):
            terminate_tree(pid, owned)
        while True:
            try:
                os.waitpid(-1, 0)
            except ChildProcessError:
                break
        deadline = time.monotonic() + 2
        while any(identity(pid) == stamp for pid, stamp in owned):
            if time.monotonic() >= deadline:
                raise RuntimeError("Compiler descendants did not exit within cleanup deadline")
            time.sleep(0.01)
    def terminate(signum, frame):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        try:
            cleanup()
        except Exception as error:
            sys.stderr.write("Compiler cleanup failed: " + str(error))
            sys.stderr.flush()
            os._exit(70)
        os._exit(143)
    signal.signal(signal.SIGTERM, terminate)
    if os.getpgrp() != os.getpid():
        os.setpgid(0, 0)
    child = subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    limit = 1048576
    marker = b"\\nOutput exceeded the 1 MiB diagnostic limit.\\n"
    accepted = 0
    while True:
        chunk = child.stdout.read1(65536)
        if not chunk:
            break
        room = limit - len(marker) - accepted
        if len(chunk) > room:
            sys.stdout.buffer.write(chunk[:max(0, room)] + marker)
            sys.stdout.buffer.flush()
            cleanup()
            sys.exit(1)
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        accepted += len(chunk)
    status = child.wait()
    sys.exit(status if status >= 0 else 128 - status)
    """

    private static func makeWrapper(
        source: String,
        revision: UInt64,
        bpm: Double,
        beatsPerBar: Int,
        maximumLiveBeats: Int,
        output: URL,
        discovery: SwitchBankDiscovery.Result?
    ) -> String {
        let supportedDiscovery = discovery.flatMap { $0.isSupported ? $0 : nil }
        let factory = supportedDiscovery.map(makeSwitchFactory) ?? ""
        let preparation: String
        if let supportedDiscovery {
            let selections = switchSelections(for: supportedDiscovery.controls)
            let selectionLiteral = selections.map { "[" + $0.map(String.init).joined(separator: ", ") + "]" }
                .joined(separator: ", ")
            let controlLiteral = supportedDiscovery.controls.map(makeSwitchControl).joined(separator: ",\n                ")
            preparation = """
                        let selections: [[Int]] = [\(selectionLiteral)]
                        let session = Session()
                        let initialSelection = session.__swiftMusicSwitchInitialSelection()
                        guard let initialIndex = selections.firstIndex(of: initialSelection) else {
                            throw EvaluationError.invalidResult("Session switch defaults are outside the prepared bank.")
                        }
                        let preparations: [RenderWorkerPreparation]
                        do {
                            var values = [RenderWorkerPreparation]()
                            values.reserveCapacity(selections.count)
                            for selection in selections {
                                session.__swiftMusicSwitchApply(selection)
                                values.append(try EvaluationEntry.makePreparation(
                                    session,
                                    bounds: bounds,
                                    fallbackBPM: \(bpm),
                                    beatsPerBar: \(beatsPerBar),
                                    maximumLiveBeats: \(maximumLiveBeats),
                                    source: \(swiftLiteral(source)),
                                    revision: \(revision)
                                ))
                            }
                            session.__swiftMusicSwitchApply(initialSelection)
                            preparations = values
                        } catch {
                            session.__swiftMusicSwitchApply(initialSelection)
                            throw error
                        }
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Mutable sliders are not supported in fixed switch banks.
                        // Generated session preparation rejects this combination until every retained variant
                        // can update and adopt the same slider generation without replaying stale audio.
                        guard preparations.allSatisfy({ $0.performanceControls.isEmpty }) else {
                            throw EvaluationError.invalidResult("Inline sliders require a session without a pre-rendered switch bank.")
                        }
                        let variants = try preparations.enumerated().map { offset, preparation in
                            guard let metadata = preparation.metadata else {
                                throw EvaluationError.invalidResult("Switch variant metadata is unavailable.")
                            }
                            return try SwitchVariant(
                                selection: selections[offset],
                                loop: preparation.session.baseline,
                                catalog: preparation.session.catalog,
                                metadata: metadata
                            )
                        }
                        let controls = [
                            \(controlLiteral)
                        ]
                        let bank = try PreparedSwitchBank(
                            controls: controls,
                            variants: variants,
                            initialIndex: initialIndex
                        )
                        let initial = preparations[bank.initialIndex]
                        return RenderWorkerPreparation(
                            session: initial.session,
                            metadata: initial.metadata,
                            source: initial.source,
                            performanceControls: initial.performanceControls,
                            performanceAdapter: initial.performanceAdapter,
                            switchBank: bank,
                            switchSessions: preparations.map(\\.session),
                            switchSelection: { @MainActor @Sendable selection in
                                session.__swiftMusicSwitchApply(selection)
                            }
                        )
            """
        } else {
            preparation = """
                        try EvaluationEntry.makePreparation(
                            Session(),
                            bounds: bounds,
                            fallbackBPM: \(bpm),
                            beatsPerBar: \(beatsPerBar),
                            maximumLiveBeats: \(maximumLiveBeats),
                            source: \(swiftLiteral(source)),
                            revision: \(revision)
                        )
            """
        }
        return """
        import Foundation
        import SwiftMusic
        import MusicPlaygourndCore
        #sourceLocation(file: "Session.swift", line: 1)
        \(source)
        #sourceLocation()
        \(factory)
        @main
        struct EvaluationEntry {
            @MainActor
            static func makePreparation<M: Music>(
                _ session: M,
                bounds: SoundCompiler.Limits,
                fallbackBPM: Double,
                beatsPerBar: Int,
                maximumLiveBeats: Int,
                source: String,
                revision: UInt64
            ) throws -> RenderWorkerPreparation {
                let adapter = PerformanceWorkerAdapter(
                    base: session, model: PlaygroundSessionModel(), compiler: SoundCompiler(limits: bounds))
                return try adapter.prepare(revision: revision, source: source,
                    fallbackBPM: fallbackBPM, beatsPerBar: beatsPerBar)
            }

            @MainActor
            static func makePreparation<M: PerformanceEntry>(
                _ session: M,
                bounds: SoundCompiler.Limits,
                fallbackBPM: Double,
                beatsPerBar: Int,
                maximumLiveBeats: Int,
                source: String,
                revision: UInt64
            ) throws -> RenderWorkerPreparation {
                _ = maximumLiveBeats
                let model = M.makePerformanceModel()
                let adapter = PerformanceWorkerAdapter(
                    base: session,
                    model: model,
                    compiler: SoundCompiler(limits: bounds)
                )
                return try adapter.prepare(
                    revision: revision,
                    source: source,
                    fallbackBPM: fallbackBPM,
                    beatsPerBar: beatsPerBar
                )
            }

            static func main() async {
              do {
                let bounds = try SoundCompiler.Limits(maximumEvents: 1024, maximumSources: 32, maximumRenderNodes: 256, maximumBuses: 32)
                try await RenderWorker.runPrepared(revision: \(revision), outputURL: URL(fileURLWithPath: \(swiftLiteral(output.path)))) {
            \(preparation)
                }
              } catch {
                if let located = error as? LocatedSoundCompilationError {
                  do {
                    let diagnostic = try WorkerCompilerDiagnostic(revision: \(revision), error: located)
                    FileHandle.standardError.write(try diagnostic.encodedStderrLine())
                  } catch {
                FileHandle.standardError.write(Data("Compiler diagnostic serialization failed: \\(error)\\n".utf8))
                  }
                }
                FileHandle.standardError.write(Data("Music preparation error: \\(String(describing: error))\\n".utf8))
                exit(1)
              }
            }
        }
        """
    }

    private static func makeSwitchFactory(_ result: SwitchBankDiscovery.Result) -> String {
        let assignments = result.controls.enumerated().map { index, control in
            let cases = control.cases.enumerated().map { caseIndex, name in
                "            case \(caseIndex): self.\(escapedProjectedIdentifier(control.propertyName)).wrappedValue = .\(escapedIdentifier(name))"
            }.joined(separator: "\n")
            return """
                    switch selection[\(index)] {
                \(cases)
                    default: preconditionFailure("Invalid Swift switch selection.")
                    }
            """
        }.joined(separator: "\n")
        let initial = result.controls.map { control in
            let cases = control.cases.enumerated().map { index, name in
                "            case .\(escapedIdentifier(name)): return \(index)"
            }.joined(separator: "\n")
            return """
                    { switch self.\(escapedIdentifier(control.propertyName)) {
                \(cases)
                    } }()
            """
        }.joined(separator: ",\n")
        return """
        extension Session {
            @MainActor
            func __swiftMusicSwitchApply(_ selection: [Int]) {
                guard selection.count == \(result.controls.count) else {
                    preconditionFailure("Swift switch selection shape is invalid.")
                }
        \(assignments)
            }

            @MainActor
            func __swiftMusicSwitchInitialSelection() -> [Int] {
                return [
        \(initial)
                ]
            }
        }
        """
    }

    private static func makeSwitchControl(_ control: SwitchBankDiscovery.Control) -> String {
        let sites = control.sites.map { site in
            let ranges = site.caseRanges.map { "NSRange(location: \($0.location), length: \($0.length))" }.joined(separator: ", ")
            return "try SwitchSite(switchLine: \(site.switchLine), endLine: \(site.endLine), caseRanges: [\(ranges)])"
        }.joined(separator: ", ")
        let cases = control.cases.map(swiftLiteral).joined(separator: ", ")
        return "try SwitchControl(id: \(swiftLiteral("switch.\(control.propertyName)")), propertyName: \(swiftLiteral(control.propertyName)), cases: [\(cases)], sites: [\(sites)])"
    }

    private static func switchSelections(for controls: [SwitchBankDiscovery.Control]) -> [[Int]] {
        controls.reduce(into: [[]]) { partial, control in
            partial = partial.flatMap { prefix in
                control.cases.indices.map { prefix + [$0] }
            }
        }
    }

    private static func escapedIdentifier(_ value: String) -> String {
        "`\(value.replacingOccurrences(of: "`", with: ""))`"
    }

    private static func escapedProjectedIdentifier(_ value: String) -> String {
        "$" + value.replacingOccurrences(of: "`", with: "")
    }

    private static func swiftLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
}
