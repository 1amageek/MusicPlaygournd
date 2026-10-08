import SwiftUI
import MusicPlaygroundUI

struct FileTabsView: View {
    @Bindable var model: SessionModel
    var accent: Color = .accentColor
    var deckName: String? = nil
    var editing = true
    var activate: () -> Void = {}
    var load: ((SessionDocument, Int) -> Void)? = nil

    var body: some View {
        FileTabStrip(
            tabs: model.documents.filter { $0.fileURL != nil || $0.isDirty }.map {
                FileTabItem(id: $0.id, name: $0.name, fileURL: $0.fileURL, isDirty: $0.isDirty, isReadOnly: $0.isReadOnly)
            },
            selected: model.activeDocumentID, audible: model.isPlaying ? model.audibleDocumentID : nil,
            accent: accent, deckName: deckName, editing: editing, canCreate: model.canCreateProjectFile,
            select: { activate(); model.selectDocument($0) }, close: { model.closeDocument($0) },
            create: { activate(); model.newProjectFile() },
            load: load.map { operation in { id, deck in
                if let document = model.documents.first(where: { $0.id == id }) { operation(document, deck) }
            } }
        )
    }
}
