import Foundation

enum DocumentFailure: Error, LocalizedError, Sendable {
    case invalidProject(String)
    case compilerRequired(String)
    case outsideProject
    case readOnly
    case tooManyEntries
    case tooManyDocuments
    case sourceTooLarge
    case externalModification
    case changedDuringSave
    case fileExists
    case io(String)

    var errorDescription: String? {
        switch self {
        case .invalidProject(let reason): "Invalid project: \(reason)"
        case .compilerRequired(let reason): "\(reason) requires Swift compilation/evaluation, which is a separate capability. Existing music is retained."
        case .outsideProject: "The file is outside the selected project."
        case .readOnly: "Dependency source is read-only."
        case .tooManyEntries: "The project exceeds the 4096-entry limit."
        case .tooManyDocuments: "Close a document before opening another; the limit is 32."
        case .sourceTooLarge: "The document exceeds the 64 KiB file limit; existing text is retained."
        case .externalModification: "The file changed outside the editor. Your edits are retained; reopen or resolve the conflict before saving."
        case .changedDuringSave: "The document changed while saving. The saved snapshot is on disk and newer edits are retained."
        case .fileExists: "The destination already exists."
        case .io(let reason): "File operation failed: \(reason)"
        }
    }
}
