import SwiftUI

struct FileTreeRow: View {
    let entry: SessionFileBrowser.Entry
    @Bindable var browser: SessionFileBrowser
    let children: [URL: [SessionFileBrowser.Entry]]
    let dirtyFiles: Set<URL>

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
                    FileTreeRow(entry: child, browser: browser, children: children, dirtyFiles: dirtyFiles)
                }
            } label: {
                Label(entry.url.lastPathComponent, systemImage: "folder")
            }
            .tag(entry.url)
            .help(entry.url.path)
        } else {
            HStack {
                Label(entry.url.lastPathComponent, systemImage: icon)
                if dirtyFiles.contains(entry.url) {
                    Spacer(minLength: 0)
                    Circle().fill(.secondary).frame(width: 4, height: 4)
                        .accessibilityLabel("Unsaved changes")
                }
            }
            .tag(entry.url)
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
