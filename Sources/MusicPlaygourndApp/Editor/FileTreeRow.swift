import SwiftUI

struct FileTreeRow: View {
    let entry: SessionFileBrowser.Entry
    @Bindable var browser: SessionFileBrowser
    let children: [URL: [SessionFileBrowser.Entry]]
    let dirtyFiles: Set<URL>
    var load: ((URL, Int) -> Void)? = nil

    var body: some View {
        if entry.isDirectory {
            DisclosureGroup(isExpanded: Binding(
                get: { browser.expanded.contains(entry.url) },
                set: { expanded in
                    guard expanded != browser.expanded.contains(entry.url) else { return }
                    do { try browser.toggle(entry) }
                    catch { browser.errorMessage = error.localizedDescription }
                }
            )) {
                ForEach(children[entry.url] ?? []) { child in
                    FileTreeRow(entry: child, browser: browser, children: children, dirtyFiles: dirtyFiles, load: load)
                }
            } label: {
                Label {
                    Text(entry.url.lastPathComponent)
                } icon: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .frame(width: 12, height: 12)
                }
            }
            .tag(entry.url)
            .help(entry.url.path)
        } else {
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                } icon: {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .frame(width: 12, height: 12)
                }
                if dirtyFiles.contains(entry.url) {
                    Spacer(minLength: 0)
                    Circle().fill(.secondary).frame(width: 4, height: 4)
                        .accessibilityLabel("Unsaved changes")
                }
            }
            .tag(entry.url)
            .draggable(entry.url)
            .contextMenu {
                if let load, entry.url.pathExtension == "swift", entry.url.lastPathComponent != "Package.swift" {
                    Button("Load into Deck A") { load(entry.url, 0) }
                    Button("Load into Deck B") { load(entry.url, 1) }
                }
            }
            .help(entry.url.path)
        }
    }

    private var icon: String {
        if entry.url.lastPathComponent == "Package.swift" { return "shippingbox" }
        if entry.url.pathExtension == "swift" { return "swift" }
        if ["wav", "aif", "aiff", "mp3", "m4a"].contains(entry.url.pathExtension.lowercased()) { return "waveform" }
        return "doc"
    }
}
