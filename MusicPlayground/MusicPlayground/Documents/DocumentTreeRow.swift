import SwiftUI
import MusicPlaygroundUI

struct DocumentTreeRow: View {
    let entry: ProjectTreeEntry
    let children: [URL: [ProjectTreeEntry]]
    @Bindable var workspace: DocumentWorkspace
    var readOnly = false
    let load: (URL, Int) -> Void

    var body: some View {
        FileTreeItemRow(url: entry.url, isDirectory: entry.isDirectory,
                        isDirty: workspace.documents.contains { $0.url == entry.url && $0.isDirty },
                        expanded: Binding(get: { workspace.expanded.contains(entry.url) }, set: { value in
                            if value { workspace.expanded.insert(entry.url) } else { workspace.expanded.remove(entry.url) }
                        }), load: readOnly ? nil : load) {
            ForEach(children[entry.url] ?? []) { child in
                DocumentTreeRow(entry: child, children: children, workspace: workspace, readOnly: readOnly, load: load)
            }
        }
    }
}
