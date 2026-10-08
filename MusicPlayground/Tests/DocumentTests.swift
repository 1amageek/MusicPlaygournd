import Foundation
import XCTest
@testable import MusicPlayground

@MainActor
final class DocumentTests: XCTestCase {
    private let template = "import SwiftMusic\nstruct Session { var value = 1 }\n"

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "documents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func cleanup(_ root: URL) {
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Temporary file cleanup failed: \(error)") }
    }
    private func preferences() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "DocumentTests.\(UUID().uuidString)"))
    }

    func testCommittedEditsRejectMismatchAndKeepUnicodeReplacementWhole() async throws {
        let root = try temporaryDirectory()
        defer { cleanup(root) }
        let workspace = DocumentWorkspace(files: ProjectFiles(projectsDirectory: root), defaults: try preferences())
        await workspace.start(template: "😀\nlet value = 1\n")
        let document = try XCTUnwrap(workspace.activeDocument)
        let original = document.source
        var changes: [(NSRange, String)] = []
        workspace.sourceDidChange = { _, range, text in changes.append((range, text)) }
        workspace.edit(document.id, source: "😃\nlet value = 1\n")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].0, NSRange(location: 0, length: 2))
        XCTAssertEqual(changes[0].1, "😃")
        XCTAssertEqual((original as NSString).replacingCharacters(in: changes[0].0, with: changes[0].1), document.source)
        let accepted = document.source
        workspace.edit(document.id, source: "unrelated", edits: [(NSRange(location: 0, length: 1), "x")])
        XCTAssertEqual(document.source, accepted)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(workspace.errorMessage, DocumentFailure.invalidSourceEdit.localizedDescription)
    }

    func testNumberedFilesUseActualTargetAndNeverOverwrite() async throws {
        let root = try temporaryDirectory()
        defer { cleanup(root) }
        let files = ProjectFiles(projectsDirectory: root)
        let project = try await files.createProject(template: template)
        let target = try XCTUnwrap(project.targets.first)
        XCTAssertEqual(target.name, "Session")
        XCTAssertTrue(target.sourceDirectory.path.hasSuffix("Sources/Session"))
        let collision = target.sourceDirectory.appending(path: "Sound1.swift")
        try Data("sentinel".utf8).write(to: collision)
        let first = try await files.createNumberedSource(in: target.sourceDirectory)
        let second = try await files.createNumberedSource(in: target.sourceDirectory)
        XCTAssertEqual(first.lastPathComponent, "Sound2.swift")
        XCTAssertEqual(second.lastPathComponent, "Sound3.swift")
        XCTAssertEqual(try String(contentsOf: collision, encoding: .utf8), "sentinel")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "import SwiftMusic\n")
        do { _ = try await files.read(root.appending(path: "outside.swift")); XCTFail("Outside-root reads must fail.") }
        catch DocumentFailure.outsideProject { }
    }

    func testSharedDirtyBuffersCloseCancelSaveAndRelaunchBookmark() async throws {
        let root = try temporaryDirectory()
        defer { cleanup(root) }
        let defaults = try preferences()
        let files = ProjectFiles(projectsDirectory: root)
        let workspace = DocumentWorkspace(files: files, defaults: defaults)
        await workspace.start(template: template)
        let original = try XCTUnwrap(workspace.activeDocument)
        await workspace.newFile(deck: 0)
        let first = try XCTUnwrap(workspace.activeDocument)
        workspace.edit(first.id, source: "let value = \"edited\"\n")
        await workspace.openFile(original.url, deck: 0)
        await workspace.openFile(first.url, deck: 1)
        XCTAssertTrue(workspace.activeDocument === first)
        XCTAssertTrue(first.isDirty)
        XCTAssertEqual(first.source, "let value = \"edited\"\n")
        workspace.requestClose(first.id, deck: 0)
        XCTAssertNil(workspace.pendingClose)
        XCTAssertTrue(workspace.tabs(in: 1).contains { $0 === first })
        workspace.requestClose(first.id, deck: 1)
        XCTAssertEqual(workspace.pendingClose, first.id)
        workspace.cancelClose()
        XCTAssertTrue(first.isDirty)
        workspace.requestClose(first.id, deck: 1)
        await workspace.saveAndClose()
        XCTAssertNil(workspace.pendingClose)
        XCTAssertFalse(workspace.documents.contains { $0.id == first.id })
        XCTAssertEqual(try String(contentsOf: first.url, encoding: .utf8), "let value = \"edited\"\n")
        let restored = DocumentWorkspace(files: ProjectFiles(projectsDirectory: root), defaults: defaults)
        await restored.start(template: template)
        XCTAssertEqual(restored.project?.root, workspace.project?.root)
        await restored.openFile(first.url)
        XCTAssertEqual(restored.activeDocument?.source, "let value = \"edited\"\n")
    }

    func testExternalChangeFailedSaveFilterAndStaleRefreshPreserveData() async throws {
        let root = try temporaryDirectory()
        defer { cleanup(root) }
        let workspace = DocumentWorkspace(files: ProjectFiles(projectsDirectory: root), defaults: try preferences())
        await workspace.start(template: template)
        let document = try XCTUnwrap(workspace.activeDocument)
        workspace.edit(document.id, source: "let retained = 42\n")
        try Data("external bytes".utf8).write(to: document.url)
        await workspace.save(document.id)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.source, "let retained = 42\n")
        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertEqual(try String(contentsOf: document.url, encoding: .utf8), "external bytes")
        let project = try XCTUnwrap(workspace.project)
        workspace.filter = "Session.swift"
        let visible = workspace.visibleEntries(project.entries, root: project.root)
        XCTAssertTrue(visible.contains { $0.url == document.url })
        XCTAssertTrue(visible.contains { $0.isDirectory && $0.url.lastPathComponent == "Sources" })
        XCTAssertFalse(visible.contains { $0.url.lastPathComponent == "Package.swift" })
        workspace.filter = ""
        XCTAssertEqual(workspace.visibleEntries(project.entries, root: project.root), project.entries)
        try FileManager.default.removeItem(at: project.root)
        await workspace.refresh()
        XCTAssertTrue(workspace.staleListing)
        XCTAssertEqual(workspace.project?.entries, project.entries)
        XCTAssertEqual(document.source, "let retained = 42\n")
    }

    func testActualDependencyFilesAreReadOnlyAndDynamicTargetsRequireCompiler() async throws {
        let root = try temporaryDirectory()
        defer { cleanup(root) }
        let dependency = root.appending(path: "Dependency")
        try FileManager.default.createDirectory(at: dependency, withIntermediateDirectories: true)
        let source = dependency.appending(path: "Library.swift")
        try Data("public struct Library {}\n".utf8).write(to: source)
        let files = ProjectFiles(projectsDirectory: root.appending(path: "Projects"), dependencyRoot: dependency)
        let project = try await files.createProject(template: template)
        XCTAssertTrue(project.dependencyEntries.contains { $0.url == source.standardizedFileURL.resolvingSymlinksInPath() },
                      "Actual dependency entries: \(project.dependencyEntries.map(\.url))")
        let snapshot = try await files.read(source)
        XCTAssertTrue(snapshot.isReadOnly)
        do { try await files.save(source, source: "changed", baseline: snapshot.source); XCTFail("Dependency writes must fail.") }
        catch DocumentFailure.readOnly { }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "public struct Library {}\n")
        try Data("import PackageDescription\nlet package = Package(name: \"Dynamic\", targets: makeTargets())\n".utf8)
            .write(to: project.root.appending(path: "Package.swift"))
        do { _ = try await files.openProject(project.root); XCTFail("Computed targets must not be fabricated.") }
        catch DocumentFailure.compilerRequired { }
    }
}
