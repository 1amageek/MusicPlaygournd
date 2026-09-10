import Foundation
import MusicPlaygourndCore

/// Shares source identity and undo across deck tab memberships.
@MainActor
final class SessionDocumentStore {
    private var documents: [URL: SessionDocument] = [:]
    var manifestDidSave: ((SessionModel, URL) -> Void)?
    var membershipDidChange: (() -> Void)?
    var sourceDidChange: ((SessionDocument) -> Void)?

    var buffers: [URL: String] {
        Dictionary(uniqueKeysWithValues: documents.compactMap { url, document in
            document.isReadOnly ? nil : (url, document.source)
        })
    }

    func validateSave(_ document: SessionDocument, to url: URL) throws {
        if let existing = documents[url], existing !== document { throw SessionModel.DocumentFailure.duplicateDestination }
    }
    func didSave(_ document: SessionDocument) {
        documents = documents.filter { $0.value !== document }
        if let url = document.fileURL { documents[url] = document }
    }
    func retain(_ identities: Set<UUID>) {
        documents = documents.filter { identities.contains($0.value.id) }
    }

    func open(_ url: URL, readOnly: Bool = false) throws -> SessionDocument {
        let identity = url.standardizedFileURL.resolvingSymlinksInPath()
        if let document = documents[identity] { return document }
        guard documents.count < SessionModel.maximumOpenDocuments * 2 else { throw SessionModel.DocumentFailure.tabLimit }
        let source = try String(contentsOf: identity, encoding: .utf8)
        guard source.utf8.count <= 65_536 else { throw MusicPlaygourndCore.EvaluationError.invalidSource("Source exceeds 64 KiB.") }
        let document = SessionDocument(source: source, fileURL: identity, isReadOnly: readOnly)
        documents[identity] = document
        return document
    }
}
