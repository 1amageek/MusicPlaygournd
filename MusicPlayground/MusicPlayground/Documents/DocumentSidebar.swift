import SwiftUI
import UniformTypeIdentifiers
import MusicPlaygroundUI

struct DocumentSidebar: View {
    @Bindable var workspace: DocumentWorkspace
    let template: String
    let load: (URL, Int) -> Void
    @State private var selection: URL?
    @State private var importer = false

    var body: some View {
        ProjectSidebar(selection: $selection, error: workspace.errorMessage) {
            if let project = workspace.project {
                DisclosureGroup(isExpanded: expansion(project.root)) {
                    let children = Dictionary(grouping: workspace.visibleEntries(project.entries, root: project.root), by: { $0.url.deletingLastPathComponent() })
                    ForEach(children[project.root] ?? []) { entry in
                        DocumentTreeRow(entry: entry, children: children, workspace: workspace, load: load)
                    }
                } label: {
                    Label {
                        Text(project.root.lastPathComponent).fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "music.note.list").font(.system(size: 10, weight: .medium))
                            .frame(width: 12, height: 12).foregroundStyle(.mint)
                    }.contentShape(Rectangle())
                }
                if let dependency = project.dependencyRoot {
                    Section("Package Dependencies") {
                        DisclosureGroup(isExpanded: expansion(dependency)) {
                            let children = Dictionary(grouping: workspace.visibleEntries(project.dependencyEntries, root: dependency), by: { $0.url.deletingLastPathComponent() })
                            ForEach(children[dependency] ?? []) { entry in
                                DocumentTreeRow(entry: entry, children: children, workspace: workspace, readOnly: true, load: load)
                            }
                        } label: {
                            Label("SwiftMusic 0.5.1", systemImage: "shippingbox").contentShape(Rectangle())
                        }
                    }
                }
            }
            if workspace.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Reading project files") }
        } footer: {
            HStack(spacing: 7) {
                Menu {
                    Button("New Project…") { workspace.requestProject(nil) }
                    Button("Open Project…") { importer = true }
                    if let project = workspace.project, project.targets.count > 1 {
                        Menu("Target") {
                            ForEach(project.targets) { target in
                                Button(target.name) { workspace.selectedTarget = target.id }
                            }
                        }
                    }
                    Divider()
                    Button("New Swift File") { Task { await workspace.newFile() } }.disabled(!workspace.canCreateFile)
                    Button("Refresh") { Task { await workspace.refresh() } }.disabled(workspace.project == nil)
                } label: { Image(systemName: "plus").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .disabled(workspace.isBusy).accessibilityLabel("Add files or open a package")
                    .accessibilityIdentifier("project-actions")
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                    TextField("Filter", text: $workspace.filter).textFieldStyle(.plain)
                        .accessibilityIdentifier("project-filter")
                    if !workspace.filter.isEmpty {
                        Button { workspace.filter = "" } label: {
                            Image(systemName: "xmark.circle.fill").contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear filter")
                    }
                }.font(.system(size: 12)).padding(.horizontal, 7).frame(height: 24)
                    .background(.primary.opacity(0.07), in: Capsule())
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
            }.padding(.horizontal, 6).frame(height: 36)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importer, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): workspace.requestProject(url)
            case .failure(let error): workspace.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: selection) { _, url in
            guard let url, url != workspace.activeDocument?.url else { return }
            let entries = (workspace.project?.entries ?? []) + (workspace.project?.dependencyEntries ?? [])
            guard entries.contains(where: { $0.url == url && !$0.isDirectory }) else { return }
            Task { await workspace.openFile(url) }
        }
        .onChange(of: workspace.activeDocument?.url, initial: true) { _, url in selection = url }
        .alert("Replace Project?", isPresented: Binding(get: { workspace.replacingProject }, set: { if !$0 { workspace.cancelProjectReplacement() } })) {
            Button("Save All & Open") { workspace.replaceProjectAction(template: template, saving: true) }
            Button("Discard & Open", role: .destructive) { workspace.replaceProjectAction(template: template, saving: false) }
            Button("Cancel", role: .cancel) { workspace.cancelProjectReplacement() }
        } message: { Text("The current tabs will close. Unsaved edits are retained if saving fails.") }
    }

    private func expansion(_ url: URL) -> Binding<Bool> {
        Binding(get: { workspace.expanded.contains(url) }, set: {
            if $0 { workspace.expanded.insert(url) } else { workspace.expanded.remove(url) }
        })
    }
}
