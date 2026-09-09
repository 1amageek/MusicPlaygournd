import AppKit
import SwiftUI

struct FileSidebarView: View {
    @Bindable var model: SessionModel
    @Bindable var browser: SessionFileBrowser

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "shippingbox")
                Text(browser.directory?.lastPathComponent ?? "Projects").lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Button("New Project…", action: model.newProject)
                    Button("Open Project…", action: model.chooseProject)
                    Divider()
                    Button("New Swift File…", action: model.newProjectFile).disabled(browser.directory == nil)
                    Button("Refresh") { perform { try browser.refresh() } }.disabled(browser.directory == nil)
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).fixedSize()
            }.font(.system(size: 12, weight: .semibold)).padding(12)
            if let project = model.project, project.targets.count > 1 {
                Menu(model.projectTarget?.name ?? "Target") {
                    ForEach(project.targets) { target in
                        Button(target.name) { model.selectProjectTarget(target) }
                    }
                }.padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            if browser.directory != nil {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(browser.entries) { entry in
                            Button { open(entry) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: browser.expanded.contains(entry.url) ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                        .opacity(entry.isDirectory ? 1 : 0).frame(width: 10)
                                    Image(systemName: icon(entry)).frame(width: 14)
                                        .foregroundStyle(entry.isDirectory ? Color.secondary : .mint)
                                    Text(entry.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                    if model.documents.contains(where: { $0.fileURL == entry.url.standardizedFileURL && $0.isDirty }) {
                                        Circle().fill(.mint).frame(width: 4, height: 4)
                                    }
                                }.font(.system(size: 11)).padding(.leading, 8 + CGFloat(entry.depth) * 14)
                                    .padding(.trailing, 8).padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                    .background(model.fileURL?.standardizedFileURL == entry.url.standardizedFileURL
                                        ? Color.mint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
                            }.buttonStyle(.plain).help(entry.url.path)
                        }
                    }.padding(5)
                }
            } else {
                Spacer()
            }
            if let error = browser.errorMessage {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).textSelection(.enabled).padding(12)
            }
        }.frame(maxHeight: .infinity, alignment: .top)
            .background(Color(red: 0.045, green: 0.055, blue: 0.065))
            .accessibilityIdentifier("project-sidebar")
    }

    private func icon(_ entry: SessionFileBrowser.Entry) -> String {
        if entry.isDirectory { return "folder" }
        if entry.url.lastPathComponent == "Package.swift" { return "shippingbox" }
        if entry.url.pathExtension == "swift" { return "swift" }
        if ["wav", "aif", "aiff", "mp3", "m4a"].contains(entry.url.pathExtension.lowercased()) { return "waveform" }
        return "doc"
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
