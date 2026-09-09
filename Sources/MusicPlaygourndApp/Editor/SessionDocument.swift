import Foundation
import Observation

@MainActor @Observable
final class SessionDocument: Identifiable {
    let id = UUID()
    var source: String
    var fileURL: URL?
    let isReadOnly: Bool
    var isDirty = false
    var editorState = EditorDocumentState()
    var name: String { fileURL?.lastPathComponent ?? "Untitled.swift" }

    init(source: String, fileURL: URL? = nil, isReadOnly: Bool = false) {
        self.isReadOnly = isReadOnly
        self.source = source
        self.fileURL = fileURL
    }
}
