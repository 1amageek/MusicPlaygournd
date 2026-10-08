import SwiftUI
import MusicPlaygroundUI

struct FileTreeRow: View {
    let entry: SessionFileBrowser.Entry
    @Bindable var browser: SessionFileBrowser
    let children: [URL: [SessionFileBrowser.Entry]]
    let dirtyFiles: Set<URL>
    var load: ((URL, Int) -> Void)? = nil

    var body: some View {
        FileTreeItemRow(url: entry.url, isDirectory: entry.isDirectory,
            isDirty: dirtyFiles.contains(entry.url), expanded: Binding(
                get: { browser.expanded.contains(entry.url) },
                set: { expanded in
                    guard expanded != browser.expanded.contains(entry.url) else { return }
                    do { try browser.toggle(entry) }
                    catch { browser.errorMessage = error.localizedDescription }
                }), load: load) {
            ForEach(children[entry.url] ?? []) { child in
                FileTreeRow(entry: child, browser: browser, children: children, dirtyFiles: dirtyFiles, load: load)
            }
        }
    }
}
