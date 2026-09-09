import Foundation
import Testing
@testable import MusicPlaygourndApp

extension NativeHostTests {
    @MainActor
    struct SessionDocumentTests {
        @Test(.timeLimit(.minutes(1)))
        func manifestNavigationAndUnchangedSaveRetainProject() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let sources = root.appending(path: "Sources/Session")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let manifest = root.appending(path: "Package.swift")
            let text = """
            // swift-tools-version: 6.4
            import PackageDescription
            let package = Package(name: "Before", targets: [.target(name: "Session")])
            """
            try text.write(to: manifest, atomically: true, encoding: .utf8)
            try "".write(to: sources.appending(path: "Session.swift"), atomically: true, encoding: .utf8)
            let outside = root.deletingLastPathComponent().appending(path: UUID().uuidString + ".txt")
            try "Notes".write(to: outside, atomically: true, encoding: .utf8)
            defer { do { try FileManager.default.removeItem(at: outside) } catch { Issue.record(error) } }
            let model = SessionModel()
            do {
                func waitForPackage() async throws {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
                    while model.isOpeningPackage && ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    try #require(!model.isOpeningPackage)
                }
                model.openProject(at: root)
                try await waitForPackage()
                try #require(model.project?.name == "Before")
                try model.openDocument(at: outside)
                try await Task.sleep(for: .milliseconds(100))
                let revision = model.revision
                try model.openDocument(at: manifest)
                #expect(model.revision == revision)
                #expect(!model.isOpeningPackage)
                let date = try manifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                #expect(model.saveDocument())
                #expect(!model.isOpeningPackage)
                #expect(try manifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == date)
                model.source = text + "\n"
                model.sourceChanged()
                #expect(model.revision == revision)
                model.source = text
                model.sourceChanged()
                #expect(model.saveDocument())
                #expect(!model.isOpeningPackage)
                model.source = text.replacingOccurrences(of: "Before", with: "After")
                model.sourceChanged()
                #expect(model.saveDocument())
                #expect(model.isOpeningPackage)
                try await waitForPackage()
                #expect(model.project?.name == "After")
                #expect(model.saveDocument())
                #expect(!model.isOpeningPackage)
                try await model.shutdown()
            } catch { try await model.shutdown(); throw error }
        }

        @Test(.timeLimit(.minutes(2)))
        func dependencyDocumentRejectsEditingAndSaving() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".swift")
            try "// Dependency".write(to: url, atomically: true, encoding: .utf8)
            defer { do { try FileManager.default.removeItem(at: url) } catch { Issue.record(error) } }
            let model = SessionModel()
            do {
                try model.openDocument(at: url, readOnly: true)
                model.source = "changed"
                #expect(model.source == "// Dependency")
                #expect(!model.saveDocument())
                #expect(try String(contentsOf: url, encoding: .utf8) == "// Dependency")
                try await model.shutdown()
            } catch { try await model.shutdown(); throw error }
        }

        @Test(.timeLimit(.minutes(2)))
        func dirtyBuffersDuplicateOpenSaveAndCloseAreIsolated() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let a = root.appending(path: "A.swift")
            let b = root.appending(path: "B.swift")
            try "A".write(to: a, atomically: true, encoding: .utf8)
            try "B".write(to: b, atomically: true, encoding: .utf8)
            let model = SessionModel()
            do {
                try model.openDocument(at: a)
                let first = model.activeDocument
                model.source = "A edited"; model.hasUnsavedChanges = true
                try model.openDocument(at: b)
                let second = model.activeDocument
                model.source = "B edited"; model.hasUnsavedChanges = true
                try model.openDocument(at: a)
                #expect(model.activeDocumentID == first.id && model.source == "A edited")
                #expect(second.source == "B edited" && second.isDirty)
                #expect(model.documents.count == 3)
                #expect(!model.closeDocument(second.id, decision: .cancel))
                #expect(model.activeDocumentID == first.id && model.documents.count == 3)
                #expect(!model.saveDocument(first, to: b))
                #expect(try String(contentsOf: b, encoding: .utf8) == "B")
                #expect(model.saveDocument(second))
                #expect(try String(contentsOf: b, encoding: .utf8) == "B edited")
                #expect(first.isDirty && !second.isDirty)
                #expect(!model.confirmAllDocuments { _ in .cancel })
                #expect(model.closeDocument(second.id))
                #expect(model.activeDocumentID == first.id)
                #expect(model.closeDocument(first.id, decision: .discard))
                #expect(model.documents.count == 1)
                let untitled = model.activeDocumentID
                #expect(model.closeDocument(untitled))
                #expect(model.documents.count == 1 && model.activeDocumentID != untitled)
                try await model.shutdown()
            } catch { try await model.shutdown(); throw error }
        }

        @Test(.timeLimit(.minutes(2)))
        func failedAndOverLimitOpensPreserveSelectedBuffer() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let model = SessionModel()
            do {
                let initial = model.activeDocumentID
                let invalid = root.appending(path: "Invalid.swift")
                try Data([0xff]).write(to: invalid)
                #expect(throws: (any Error).self) { try model.openDocument(at: invalid) }
                #expect(model.activeDocumentID == initial && model.documents.count == 1)
                for index in 1..<SessionModel.maximumOpenDocuments {
                    let url = root.appending(path: "\(index).swift")
                    try "// \(index)".write(to: url, atomically: true, encoding: .utf8)
                    try model.openDocument(at: url)
                }
                let selected = model.activeDocumentID
                #expect(throws: SessionModel.DocumentFailure.self) { try model.openDocument(at: root.appending(path: "Overflow.swift")) }
                #expect(model.activeDocumentID == selected && model.documents.count == SessionModel.maximumOpenDocuments)
                try await model.shutdown()
            } catch { try await model.shutdown(); throw error }
        }
    }
}
