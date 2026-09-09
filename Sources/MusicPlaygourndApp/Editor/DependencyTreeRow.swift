import AppKit
import MusicPlaygourndCore
import SwiftUI

struct DependencyTreeRow: View {
    let dependency: SwiftPackageProject.Dependency
    let model: SessionModel
    @Binding var selection: URL?
    @SwiftUI.State private var browser = SessionFileBrowser()
    @SwiftUI.State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded },
            set: { value in
                if value, browser.directory == nil, let path = dependency.checkoutPath {
                    do { try browser.load(URL(fileURLWithPath: path)) }
                    catch { browser.errorMessage = error.localizedDescription }
                }
                expanded = value
            }
        )) {
            let children = Dictionary(grouping: browser.entries, by: { $0.url.deletingLastPathComponent() })
            if let root = browser.directory {
                ForEach(children[root] ?? []) { entry in
                    FileTreeRow(entry: entry, browser: browser, children: children, dirtyFiles: [])
                }
            }
            if let error = browser.errorMessage {
                Text(error).foregroundStyle(.orange).font(.caption)
            }
        } label: {
            Label {
                HStack(spacing: 5) {
                    Text(dependency.name)
                    Text(dependency.versionDescription).foregroundStyle(.secondary)
                }.lineLimit(1)
            } icon: {
                Image(systemName: "shippingbox").font(.system(size: 12))
                    .foregroundStyle(.brown).frame(width: 14, height: 14)
            }
            .help(dependency.url ?? dependency.path ?? dependency.identity)
        }
        .onChange(of: selection) { _, url in
            guard let url, browser.entries.contains(where: { $0.url == url && !$0.isDirectory }) else { return }
            do {
                if ["swift", "md", "txt", "json", "resolved", "h", "c", "cpp"].contains(url.pathExtension.lowercased()) || url.pathExtension.isEmpty {
                    try model.openDocument(at: url, readOnly: true)
                } else { NSWorkspace.shared.open(url) }
            } catch { browser.errorMessage = error.localizedDescription }
        }
    }
}
