import Foundation
import Observation

@MainActor @Observable
final class SourceDocument: Identifiable {
    let id = UUID()
    let url: URL
    let isReadOnly: Bool
    private(set) var source: String
    private(set) var baseline: String
    var isDirty: Bool { source != baseline }
    var name: String { url.lastPathComponent }

    init(_ snapshot: DocumentSnapshot) {
        url = snapshot.url; source = snapshot.source; baseline = snapshot.source
        isReadOnly = snapshot.isReadOnly
    }

    func edit(_ source: String) throws {
        guard !isReadOnly else { throw DocumentFailure.readOnly }
        self.source = source
    }

    func didSave(_ snapshot: String) { baseline = snapshot }
}
