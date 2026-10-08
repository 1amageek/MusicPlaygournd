import SwiftUI

public struct FileTreeItemRow<Children: View>: View {
    private let url: URL
    private let isDirectory: Bool
    private let isDirty: Bool
    @Binding private var expanded: Bool
    private let children: @MainActor () -> Children
    private let load: ((URL, Int) -> Void)?

    public init(url: URL, isDirectory: Bool, isDirty: Bool, expanded: Binding<Bool>,
                load: ((URL, Int) -> Void)? = nil, @ViewBuilder children: @escaping @MainActor () -> Children) {
        self.url = url; self.isDirectory = isDirectory; self.isDirty = isDirty
        _expanded = expanded; self.load = load; self.children = children
    }

    public var body: some View {
        if isDirectory {
            DisclosureGroup(isExpanded: $expanded) { children() } label: {
                Label { Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle) } icon: { icon("folder") }
                    .contentShape(Rectangle())
            }.tag(url).help(url.path)
        } else {
            HStack {
                Label { Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle) } icon: { icon(fileIcon) }
                if isDirty {
                    Spacer(minLength: 0)
                    Circle().fill(.secondary).frame(width: 4, height: 4).accessibilityLabel("Unsaved changes")
                }
            }.contentShape(Rectangle()).tag(url).draggable(url).help(url.path)
                .accessibilityIdentifier("source-file-" + url.lastPathComponent)
                .contextMenu {
                    if let load, url.pathExtension.lowercased() == "swift", url.lastPathComponent != "Package.swift" {
                        Button("Load into Deck A") { load(url, 0) }
                        Button("Load into Deck B") { load(url, 1) }
                    }
                }
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 10)).frame(width: 12, height: 12)
    }
    private var fileIcon: String {
        if url.lastPathComponent == "Package.swift" { return "shippingbox" }
        if url.pathExtension.lowercased() == "swift" { return "swift" }
        if ["wav", "aif", "aiff", "mp3", "m4a"].contains(url.pathExtension.lowercased()) { return "waveform" }
        return "doc"
    }
}
