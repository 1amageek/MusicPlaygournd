import Foundation
import Testing
import SwiftMusic
@testable import MusicPlaygourndCore
@testable import MusicPlaygourndApp

extension NativeHostTests {
    struct SwiftPackageProjectTests {
        @Test(.timeLimit(.minutes(2))) @MainActor
        func newProjectUsesItsNameAndPreservesExistingDirectory() async throws {
            let host = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let project = root.appending(path: "Evening Set")
            try SessionModel.createProject(at: project)
            let entry = project.appending(path: "Sources/Evening Set/Session.swift")
            #expect(try String(contentsOf: entry, encoding: .utf8) == SessionModel.initialSource)
            try "Keep this edit".write(to: entry, atomically: true, encoding: .utf8)
            #expect(throws: SessionFileBrowser.Failure.self) { try SessionModel.createProject(at: project) }
            #expect(try String(contentsOf: entry, encoding: .utf8) == "Keep this edit")
            let evaluator = SourceEvaluator(packageURL: host, workspace: root.appending(path: "Evaluation"), swiftExecutable: "/usr/bin/swift")
            do {
                let loaded = try await evaluator.openProject(at: project)
                #expect(loaded.name == "Evening Set")
                let dependency = try #require(loaded.dependencies.first { $0.identity == "swiftmusic" })
                #expect(dependency.name == "SwiftMusic" && dependency.versionDescription == "0.5.0")
                let checkout = try #require(dependency.checkoutPath)
                #expect(FileManager.default.fileExists(atPath: checkout + "/Package.swift"))
                let target = try #require(loaded.targets.first)
                #expect(target.name == "Evening Set")
                #expect(target.path == "Sources/Evening Set")
                #expect(loaded.entryURL(for: target).path == entry.path)
                let request = try ProjectEvaluationRequest(project: loaded, target: target,
                    buffers: [entry: SessionModel.initialSource])
                let initial = try await evaluator.evaluateRetained(source: SessionModel.initialSource,
                    bpm: 140, beatsPerBar: 4, revision: 1, project: request)
                #expect(initial.loop.rows.count == 4)
                #expect(initial.metadata.sliders.count == 2)
                #expect(initial.loop.samples.contains { abs($0) > 0.001 })
                #expect(await evaluator.adopt(revision: 1))
                var values = Dictionary(uniqueKeysWithValues: initial.performanceControls.map { ($0.controlID, $0.value) })
                let acid = try #require(initial.metadata.sliders.first)
                let level = try #require(initial.metadata.sliders.last)
                values[acid.id] = .double(0.1)
                let changed = try await evaluator.renderPerformance(values: values, revision: 1, generation: 1)
                let filterChangedPCM = changed.loop.samples != initial.loop.samples
                #expect(filterChangedPCM)
                await evaluator.discardPerformance(revision: 1, generation: 1)
                values[level.id] = .double(0)
                let muted = try await evaluator.renderPerformance(values: values, revision: 1, generation: 2)
                let levelChangedPCM = muted.loop.samples != changed.loop.samples
                #expect(levelChangedPCM)
                #expect(muted.loop.samples.contains { abs($0) > 0.001 })
                #expect(muted.metadata.sliders.last?.value == 0)
                await evaluator.discardPerformance(revision: 1, generation: 2)
                try await evaluator.shutdown()
            } catch { try await evaluator.shutdown(); throw error }
        }

        @Test(.timeLimit(.minutes(6)))
        func packageUsesSeparateFilesDependenciesResourcesAndUnsavedBuffers() async throws {
            let host = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = FileManager.default.temporaryDirectory.appending(path: "MusicProject-\(UUID().uuidString)")
            let project = root.appending(path: "Live")
            let kit = root.appending(path: "Kit")
            let sources = project.appending(path: "Sources/LiveSet")
            try FileManager.default.createDirectory(at: sources.appending(path: "Resources"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: kit.appending(path: "Sources/Kit"), withIntermediateDirectories: true)
            func write(_ text: String, _ url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
            try write("""
            // swift-tools-version: 6.4
            import PackageDescription
            let package = Package(name: "Kit", products: [.library(name: "Kit", targets: ["Kit"])], targets: [.target(name: "Kit")])
            """, kit.appending(path: "Package.swift"))
            try write("public let basePitch = \"C2\"", kit.appending(path: "Sources/Kit/Pitch.swift"))
            let manifest = """
            // swift-tools-version: 6.4
            import PackageDescription
            let package = Package(name: "Live", platforms: [.macOS(.v15)], dependencies: [
                .package(url: "https://github.com/1amageek/SwiftMusic.git", exact: "0.5.0"), .package(path: "../Kit")
            ], targets: [.target(name: "LiveSet", dependencies: [.product(name: "SwiftMusic", package: "SwiftMusic"), "Kit"], resources: [.copy("Resources")], swiftSettings: [.define("LIVE_PROJECT")])])
            """
            try write(manifest, project.appending(path: "Package.swift"))
            try write("sample", sources.appending(path: "Resources/note.txt"))
            let helper = "import Kit\nimport SwiftMusic\nfunc pitch() -> NotePattern { basePitch == \"C2\" ? \"C2\" : \"C3\" }\n"
            try write(helper, sources.appending(path: "Pitch.swift"))
            let source = """
            import Foundation
            import SwiftMusic
            #if !LIVE_PROJECT
            #error("The project compiler settings must apply to execution and AST inspection.")
            #endif
            struct Session: Music {
                init() { precondition(Bundle.module.url(forResource: "note", withExtension: "txt", subdirectory: "Resources") != nil) }
                var body: some Sound { Synthesizer(.sine).notes(pitch()).gain(0.1) }
            }
            """
            try write(source, sources.appending(path: "Session.swift"))
            let evaluator = SourceEvaluator(packageURL: host, workspace: root.appending(path: "Evaluation"), swiftExecutable: "/usr/bin/swift", projectBuildCache: root.appending(path: "Cache"))
            do {
                let loaded = try await evaluator.openProject(at: project)
                let target = try #require(loaded.targets.first)
                #expect(target.sources.contains("Pitch.swift"))
                let coldStart = ContinuousClock.now
                let first = try await evaluator.evaluateRetained(source: source, bpm: 120, beatsPerBar: 4, revision: 1,
                    project: ProjectEvaluationRequest(project: loaded, target: target, buffers: [:]))
                print("PROJECT COLD", coldStart.duration(to: .now))
                #expect(!first.loop.samples.isEmpty)
                #expect(await evaluator.adopt(revision: 1))
                let changed = [sources.appending(path: "Pitch.swift"): "import SwiftMusic\nfunc pitch() -> NotePattern { \"G3\" }"]
                let second = try await evaluator.evaluateRetained(source: source, bpm: 120, beatsPerBar: 4, revision: 2,
                    project: ProjectEvaluationRequest(project: loaded, target: target, buffers: changed))
                #expect(first.loop != second.loop)
                #expect(try String(contentsOf: sources.appending(path: "Pitch.swift"), encoding: .utf8) == helper)
                #expect(try String(contentsOf: project.appending(path: "Package.swift"), encoding: .utf8) == manifest)
                do {
                    _ = try await evaluator.evaluateRetained(source: source, bpm: 120, beatsPerBar: 4, revision: 3,
                        project: ProjectEvaluationRequest(project: loaded, target: target, buffers: [sources.appending(path: "Pitch.swift"): "import SwiftMusic\nfunc pitch() -> NotePattern { missingPitch }"]))
                    Issue.record("Invalid helper source must fail compilation.")
                } catch is CancellationError { throw CancellationError() }
                catch { #expect(!error.localizedDescription.isEmpty) }
                let retained = try await evaluator.render(overrides: [], revision: 1, generation: 1)
                #expect(retained == first.loop)
                let lsp = try await evaluator.run("/usr/bin/xcrun", ["--find", "sourcekit-lsp"], timeout: 10).trimmingCharacters(in: .whitespacesAndNewlines)
                let completion = ProjectCompletionService(root: loaded.root, executable: lsp)
                do {
                    let completionSource = source.replacingOccurrences(of: "pitch()", with: "pit")
                    let cursor = NSMaxRange((completionSource as NSString).range(of: "pit"))
                    let values = try await completion.completions(source: completionSource, utf16Offset: cursor,
                        file: loaded.entryURL(for: target), buffers: [:])
                    #expect(values.contains { $0.label.hasPrefix("pitch(") })
                    try await completion.shutdown()
                } catch {
                    do { try await completion.shutdown() } catch { Issue.record(error) }
                    throw error
                }
                try await evaluator.shutdown()
                #expect(FileManager.default.fileExists(atPath: root.appending(path: "Cache/Project/.build").path))
                let restarted = SourceEvaluator(packageURL: host, workspace: root.appending(path: "Restarted"), swiftExecutable: "/usr/bin/swift", projectBuildCache: root.appending(path: "Cache"))
                do {
                    let warmStart = ContinuousClock.now
                    let warm = try await restarted.evaluateRetained(source: source, bpm: 120, beatsPerBar: 4, revision: 1,
                        project: ProjectEvaluationRequest(project: loaded, target: target, buffers: [:]))
                    print("PROJECT WARM RESTART", warmStart.duration(to: .now))
                    #expect(warm.loop == first.loop)
                    try await restarted.shutdown()
                } catch { try await restarted.shutdown(); throw error }
                try FileManager.default.removeItem(at: root)
            } catch {
                do { try await evaluator.shutdown() } catch { Issue.record(error) }
                do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
                throw error
            }
        }
    }
}
