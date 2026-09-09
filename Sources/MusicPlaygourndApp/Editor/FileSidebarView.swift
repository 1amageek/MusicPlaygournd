import AppKit
import SwiftUI

struct FileSidebarView: View {
    @Bindable var model: SessionModel
    @Bindable var browser: SessionFileBrowser
    @SwiftUI.State private var filter = ""
    @SwiftUI.State private var rootExpanded = true
    @SwiftUI.State private var selection: URL?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                if let root = browser.directory {
                    DisclosureGroup(isExpanded: $rootExpanded) {
                        let children = Dictionary(grouping: visibleEntries, by: { $0.url.deletingLastPathComponent() })
                        let dirtyFiles = Set(model.documents.filter(\.isDirty).compactMap(\.fileURL))
                        ForEach(children[root] ?? []) { entry in
                            FileTreeRow(entry: entry, browser: browser, children: children, dirtyFiles: dirtyFiles)
                        }
                    } label: {
                        Label {
                            Text(root.lastPathComponent).fontWeight(.semibold)
                        } icon: {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 12, height: 12).foregroundStyle(.mint)
                        }
                    }
                    .tag(root)
                }
                if model.project != nil || model.isOpeningPackage {
                    Section("Package Dependencies") {
                        ForEach(model.project?.dependencies ?? []) { dependency in
                            DependencyTreeRow(dependency: dependency, model: model, selection: $selection)
                                .id((dependency.checkoutPath ?? dependency.identity) + dependency.versionDescription)
                        }
                        if model.isOpeningPackage || model.isPreparing {
                            HStack(alignment: .top, spacing: 8) {
                                ProgressView().controlSize(.mini)
                                Text(model.preparationProgress)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .help(model.preparationProgress)
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("package-preparation-progress")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .font(.system(size: 12))
            .controlSize(.small)
            .environment(\.defaultMinListRowHeight, 22)
            .onChange(of: selection) { _, url in
                guard let url, let entry = browser.entries.first(where: { $0.url == url }), !entry.isDirectory else { return }
                open(entry)
            }
            .onChange(of: model.fileURL, initial: true) { _, url in selection = url }
            if let error = browser.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled).padding(8)
            }
            Divider()
            HStack(spacing: 7) {
                Menu {
                    Button("New Project…", action: model.newProject)
                    Button("Open Project…", action: model.chooseProject)
                    if let project = model.project, project.targets.count > 1 {
                        Menu("Target") {
                            ForEach(project.targets) { target in
                                Button(target.name) { model.selectProjectTarget(target) }
                            }
                        }
                    }
                    Divider()
                    Button("New Swift File…", action: model.newProjectFile).disabled(browser.directory == nil)
                    Button("Refresh") { perform { try browser.refresh() } }.disabled(browser.directory == nil)
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Add files or open a package")
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                    TextField("Filter", text: $filter).textFieldStyle(.plain)
                        .accessibilityLabel("Filter expanded project files")
                    if !filter.isEmpty {
                        Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear filter")
                    }
                }
                .font(.system(size: 12)).padding(.horizontal, 7).frame(height: 24)
                .background(.primary.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
            }.padding(.horizontal, 6).frame(height: 36)
        }
        .background(.bar)
        .onChange(of: browser.directory) { _, _ in rootExpanded = true; filter = "" }
        .accessibilityIdentifier("project-sidebar")
    }

    private var visibleEntries: [SessionFileBrowser.Entry] {
        guard !filter.isEmpty, let root = browser.directory else { return browser.entries }
        var included: Set<URL> = []
        for entry in browser.entries where entry.url.lastPathComponent.localizedStandardContains(filter) {
            var url = entry.url
            while url.path.hasPrefix(root.path + "/") {
                included.insert(url)
                url.deleteLastPathComponent()
            }
        }
        return browser.entries.filter { included.contains($0.url) }
    }

    private func open(_ entry: SessionFileBrowser.Entry) {
        perform {
            if entry.isDirectory { try browser.toggle(entry) }
            else if ["swift", "md", "txt", "json", "resolved"].contains(entry.url.pathExtension.lowercased()) {
                try model.openDocument(at: entry.url)
            } else { NSWorkspace.shared.open(entry.url) }
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() }
        catch { browser.errorMessage = error.localizedDescription }
    }
}
