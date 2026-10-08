import Foundation
import Observation

@MainActor @Observable
final class DocumentWorkspace {
    private(set) var project: ProjectSnapshot?
    private(set) var documents: [SourceDocument] = []
    private(set) var isBusy = false
    private(set) var staleListing = false
    var errorMessage: String?
    var sourceDidChange: ((UUID, NSRange, String) -> Void)?
    var filter = ""
    var expanded: Set<URL> = []
    var editingDeck = 0
    var selectedTarget: String?
    private(set) var pendingClose: UUID?
    private var pendingCloseDeck = 0
    private var pendingProject: URL?
    private(set) var replacingProject = false
    private var memberships: [[UUID]] = [[], []]
    private var selections: [UUID?] = [nil, nil]
    private let files: any ProjectFileAccess
    private let defaults: UserDefaults

    init(files: any ProjectFileAccess, defaults: UserDefaults = .standard) {
        self.files = files; self.defaults = defaults
    }

    var activeDocument: SourceDocument? { selectedDocument(in: editingDeck) }
    var retainedIDs: Set<UUID> { Set(documents.map(\.id)) }
    var target: ProjectTarget? { project?.targets.first { $0.id == selectedTarget } }
    var canCreateFile: Bool { target != nil && !isBusy }

    func tabs(in deck: Int) -> [SourceDocument] {
        guard (0...1).contains(deck) else { return [] }
        return memberships[deck].compactMap { id in documents.first { $0.id == id } }
    }
    func selectedDocument(in deck: Int) -> SourceDocument? {
        guard (0...1).contains(deck), let id = selections[deck] else { return nil }
        return documents.first { $0.id == id }
    }

    func start(template: String) async {
        guard project == nil, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let candidate: ProjectSnapshot
            if let bookmark = defaults.data(forKey: "workspace.project") {
                let url = try await files.resolveBookmark(bookmark)
                candidate = try await files.openProject(url)
            } else { candidate = try await files.createProject(template: template) }
            adopt(candidate)
            await rememberProject()
            try await openInitialDocument()
        } catch { errorMessage = error.localizedDescription }
    }

    func attach(_ id: UUID, to deck: Int) throws {
        guard (0...1).contains(deck), documents.contains(where: { $0.id == id }) else { throw DocumentFailure.outsideProject }
        if !memberships[deck].contains(id) { memberships[deck].append(id) }
        if selections[deck] == nil { selections[deck] = id }
    }

    func reorder(_ id: UUID, before target: UUID, deck: Int) {
        guard (0...1).contains(deck), id != target,
              let old = memberships[deck].firstIndex(of: id), memberships[deck].contains(target) else { return }
        memberships[deck].remove(at: old)
        guard let destination = memberships[deck].firstIndex(of: target) else { return }
        memberships[deck].insert(id, at: destination)
    }

    func select(_ id: UUID, deck: Int) {
        guard (0...1).contains(deck), memberships[deck].contains(id) else { return }
        editingDeck = deck; selections[deck] = id
    }

    func openFile(_ url: URL, deck: Int? = nil) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await openDocument(url, deck: deck ?? editingDeck); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func edit(_ id: UUID, source: String, edits: [(NSRange, String)] = []) {
        guard let document = documents.first(where: { $0.id == id }) else { return }
        do {
            let original = document.source
            guard original != source else { return }
            let before = original.utf16, after = source.utf16
            var prefix = 0
            for (old, new) in zip(before, after) {
                guard old == new else { break }; prefix += 1
            }
            while prefix > 0 && (!Self.isScalarBoundary(prefix, in: before) || !Self.isScalarBoundary(prefix, in: after)) { prefix -= 1 }
            var suffix = 0
            let available = min(before.count, after.count) - prefix
            for (old, new) in zip(before.reversed(), after.reversed()) {
                guard suffix < available, old == new else { break }; suffix += 1
            }
            while suffix > 0 && (!Self.isScalarBoundary(before.count - suffix, in: before) || !Self.isScalarBoundary(after.count - suffix, in: after)) { suffix -= 1 }
            let range = NSRange(location: prefix, length: before.count - prefix - suffix)
            let replacement = (source as NSString).substring(with: NSRange(location: prefix, length: after.count - prefix - suffix))
            if !edits.isEmpty {
                var replay = document.source
                for (range, replacement) in edits {
                    let text = replay as NSString
                    guard range.location >= 0, range.length >= 0, range.location <= text.length,
                          range.length <= text.length - range.location, Self.isScalarBoundary(range.location, in: replay.utf16),
                          Self.isScalarBoundary(range.location + range.length, in: replay.utf16) else { throw DocumentFailure.invalidSourceEdit }
                    replay = text.replacingCharacters(in: range, with: replacement)
                }
                guard replay == source else { throw DocumentFailure.invalidSourceEdit }
            }
            try document.edit(source)
            if edits.isEmpty { sourceDidChange?(id, range, replacement) }
            else { for (range, replacement) in edits { sourceDidChange?(id, range, replacement) } }
        }
        catch { errorMessage = error.localizedDescription }
    }

    private static func isScalarBoundary(_ offset: Int, in units: String.UTF16View) -> Bool {
        guard offset > 0 && offset < units.count else { return true }
        let index = units.index(units.startIndex, offsetBy: offset)
        return !((0xD800...0xDBFF).contains(units[units.index(before: index)]) && (0xDC00...0xDFFF).contains(units[index]))
    }

    func save(_ id: UUID) async {
        guard !isBusy, let document = documents.first(where: { $0.id == id }) else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await saveDocument(document); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func newFile(deck: Int? = nil) async {
        guard !isBusy, let target else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try await files.createNumberedSource(in: target.sourceDirectory)
            if let project { self.project = try await files.openProject(project.scopeURL) }
            expanded.insert(target.sourceDirectory)
            expanded.insert(target.sourceDirectory.deletingLastPathComponent())
            try await openDocument(url, deck: deck ?? editingDeck)
            staleListing = false; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() async {
        guard !isBusy, let project else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            self.project = try await files.openProject(project.scopeURL)
            staleListing = false; errorMessage = nil
        } catch { staleListing = true; errorMessage = "Stale listing · \(error.localizedDescription)" }
    }

    func requestClose(_ id: UUID, deck: Int) {
        guard !isBusy, (0...1).contains(deck), let document = documents.first(where: { $0.id == id }) else { return }
        let count = memberships.reduce(0) { $0 + ($1.contains(id) ? 1 : 0) }
        if document.isDirty && count == 1 {
            pendingClose = id; pendingCloseDeck = deck
        } else { removeMembership(id, deck: deck) }
    }

    func cancelClose() { pendingClose = nil }
    func discardClose() {
        guard let id = pendingClose else { return }
        removeMembership(id, deck: pendingCloseDeck); pendingClose = nil
    }
    func saveAndClose() async {
        guard let id = pendingClose else { return }
        await saveAndClose(id: id, deck: pendingCloseDeck)
    }
    func saveAndCloseAction() {
        guard let id = pendingClose else { return }
        let deck = pendingCloseDeck
        Task { await saveAndClose(id: id, deck: deck) }
    }
    private func saveAndClose(id: UUID, deck: Int) async {
        await save(id)
        guard let document = documents.first(where: { $0.id == id }) else { return }
        guard !document.isDirty else { pendingClose = id; pendingCloseDeck = deck; return }
        removeMembership(id, deck: deck); pendingClose = nil
    }

    func requestProject(_ url: URL?) {
        guard !isBusy else { return }
        pendingProject = url; replacingProject = true
    }
    func cancelProjectReplacement() { replacingProject = false; pendingProject = nil }

    func replaceProjectAction(template: String, saving: Bool) {
        guard replacingProject, !isBusy else { return }
        let url = pendingProject
        Task { await performReplacement(url: url, template: template, saving: saving) }
    }
    func replaceProject(template: String, saving: Bool) async {
        guard replacingProject, !isBusy else { return }
        await performReplacement(url: pendingProject, template: template, saving: saving)
    }
    private func performReplacement(url: URL?, template: String, saving: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if saving {
                for document in documents where document.isDirty { try await saveDocument(document) }
                guard !documents.contains(where: \.isDirty) else { throw DocumentFailure.changedDuringSave }
            }
            let candidate: ProjectSnapshot
            if let url { candidate = try await files.openProject(url) }
            else { candidate = try await files.createProject(template: template) }
            adopt(candidate)
            replacingProject = false; pendingProject = nil
            await rememberProject()
            try await openInitialDocument()
        } catch { errorMessage = error.localizedDescription }
    }

    func visibleEntries(_ entries: [ProjectTreeEntry], root: URL) -> [ProjectTreeEntry] {
        guard !filter.isEmpty else { return entries }
        var included: Set<URL> = []
        for entry in entries where entry.url.lastPathComponent.localizedStandardContains(filter) {
            var url = entry.url
            while url.path.hasPrefix(root.path + "/") {
                included.insert(url); url.deleteLastPathComponent()
            }
        }
        return entries.filter { included.contains($0.url) }
    }

    private func openDocument(_ url: URL, deck: Int) async throws {
        guard (0...1).contains(deck) else { throw DocumentFailure.invalidProject("Choose Deck A or Deck B.") }
        let document: SourceDocument
        if let existing = documents.first(where: { $0.url == url }) { document = existing }
        else {
            guard documents.count < 32 else { throw DocumentFailure.tooManyDocuments }
            let snapshot = try await files.read(url)
            if let existing = documents.first(where: { $0.url == snapshot.url }) { document = existing }
            else { document = SourceDocument(snapshot); documents.append(document) }
        }
        if !memberships[deck].contains(document.id) { memberships[deck].append(document.id) }
        selections[deck] = document.id; editingDeck = deck
    }

    private func saveDocument(_ document: SourceDocument) async throws {
        guard !document.isReadOnly else { throw DocumentFailure.readOnly }
        let snapshot = document.source
        try await files.save(document.url, source: snapshot, baseline: document.baseline)
        document.didSave(snapshot)
        if document.isDirty { throw DocumentFailure.changedDuringSave }
    }

    private func removeMembership(_ id: UUID, deck: Int) {
        memberships[deck].removeAll { $0 == id }
        if selections[deck] == id { selections[deck] = memberships[deck].last }
        if selections[editingDeck] == nil, selections[1 - editingDeck] != nil { editingDeck = 1 - editingDeck }
        let retained = Set(memberships.flatMap { $0 })
        documents.removeAll { !retained.contains($0.id) }
    }

    private func adopt(_ snapshot: ProjectSnapshot) {
        project = snapshot; selectedTarget = snapshot.targets.first?.id
        documents = []; memberships = [[], []]; selections = [nil, nil]; editingDeck = 0
        filter = ""; staleListing = false; errorMessage = nil
        expanded = Set([snapshot.root] + snapshot.targets.flatMap { [$0.sourceDirectory, $0.sourceDirectory.deletingLastPathComponent()] })
    }

    private func openInitialDocument() async throws {
        guard let project else { return }
        let preferred = project.entries.first { !$0.isDirectory && $0.url.lastPathComponent == "Session.swift" }
        let first = preferred ?? project.entries.first { !$0.isDirectory && $0.url.pathExtension == "swift" && $0.url.lastPathComponent != "Package.swift" }
        if let first { try await openDocument(first.url, deck: 0) }
    }

    private func rememberProject() async {
        guard let project else { return }
        do { defaults.set(try await files.bookmark(project.scopeURL), forKey: "workspace.project") }
        catch { errorMessage = "Project opened; restoring it after relaunch failed: \(error.localizedDescription)" }
    }
}
