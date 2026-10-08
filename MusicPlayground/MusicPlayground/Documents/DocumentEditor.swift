import SwiftUI
import MusicPlaygroundUI

struct DocumentEditor: View {
    @Bindable var workspace: DocumentWorkspace
    let audibleIDs: [UUID?]
    let colors: [Color]
    let load: (SourceDocument, Int) -> Void
    @Binding var visibility: NavigationSplitViewVisibility
    @State private var formatRequest = 0
    @State private var completionRequest = 0
    @State private var revealRequest = 0
    @State private var revealRange: NSRange?
    @State private var settings = false
    @State private var expandedDiagnostics = false
    @State private var analyses: [UUID: SourceAnalysis] = [:]
    @State private var parsingFailure = ""

    var body: some View {
        VStack(spacing: 0) {
            EditorPane {
                HStack(spacing: 0) {
                    SidebarToggle(visibility: $visibility)
                    tabs(0)
                    Divider()
                    tabs(1)
                    Menu {
                        if let document = workspace.activeDocument {
                            Button("Save") { Task { await workspace.save(document.id) } }
                                .keyboardShortcut("s", modifiers: .command).disabled(document.isReadOnly || workspace.isBusy)
                        }
                        Button("Format Source") { formatRequest += 1 }.disabled(!canEditSwift)
                            .keyboardShortcut("f", modifiers: [.command, .shift])
                        Button("Syntax Symbols") { completionRequest += 1 }.disabled(!canEditSwift)
                        Button("Themes & Fonts") { settings = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
                    }.accessibilityLabel("Editor actions").accessibilityIdentifier("editor-actions")
                        .padding(.trailing, 8)
                }
            } content: {
                if let document = workspace.activeDocument {
                    SourceEditor(documentID: document.id, source: document.source,
                        retainedDocuments: workspace.retainedIDs,
                        isReadOnly: document.isReadOnly || (workspace.isBusy && workspace.replacingProject),
                        formatRequest: formatRequest, completionRequest: completionRequest,
                        isSyntaxEnabled: document.url.pathExtension.lowercased() == "swift",
                        revealRequest: revealRequest, revealRange: revealRange,
                        analyzer: SwiftSourceAnalyzer(importedTypes: ["Music", "Sound", "Track", "Sample", "Synthesizer"]),
                        onEdit: { workspace.edit($0, source: $1) },
                        onAnalysis: { id, result in analyses[id] = result }, onFailure: { parsingFailure = $0 })
                } else {
                    Text(workspace.isBusy ? "Reading project…" : "Select a source file")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            diagnostics
        }
        .onChange(of: workspace.retainedIDs) { _, retained in
            analyses = analyses.filter { retained.contains($0.key) }
        }
        .onChange(of: workspace.activeDocument?.id) { _, _ in
            parsingFailure = ""; expandedDiagnostics = false; revealRange = nil
        }
        .sheet(isPresented: $settings) {
            NavigationStack {
                EditorAppearanceControls().padding(24).navigationTitle("Themes & Fonts")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { settings = false }.contentShape(Rectangle())
                    } }
            }.presentationDetents([.medium])
        }
        .alert("Save Changes?", isPresented: Binding(get: { workspace.pendingClose != nil }, set: { if !$0 { workspace.cancelClose() } })) {
            Button("Save") { workspace.saveAndCloseAction() }
            Button("Discard", role: .destructive) { workspace.discardClose() }
            Button("Cancel", role: .cancel) { workspace.cancelClose() }
        } message: { Text("Unsaved source is retained if saving fails.") }
    }

    private var canEditSwift: Bool {
        workspace.activeDocument.map { !$0.isReadOnly && $0.url.pathExtension.lowercased() == "swift" } ?? false
    }

    private func tabs(_ deck: Int) -> some View {
        FileTabStrip(tabs: workspace.tabs(in: deck).map {
            FileTabItem(id: $0.id, name: $0.name, fileURL: $0.url, isDirty: $0.isDirty, isReadOnly: $0.isReadOnly)
        }, selected: workspace.selectedDocument(in: deck)?.id, audible: audibleIDs[deck], accent: colors[deck],
            deckName: deck == 0 ? "A" : "B", editing: workspace.editingDeck == deck, canCreate: workspace.canCreateFile,
            select: { workspace.select($0, deck: deck) }, close: { workspace.requestClose($0, deck: deck) },
            create: { Task { await workspace.newFile(deck: deck) } },
            load: { id, target in if let document = workspace.documents.first(where: { $0.id == id }) { load(document, target) } })
    }

    private var diagnostics: some View {
        let issues = workspace.activeDocument.flatMap { analyses[$0.id] }?.diagnostics ?? []
        return Group {
            if !issues.isEmpty || !parsingFailure.isEmpty {
                Divider()
                DisclosureGroup(isExpanded: $expandedDiagnostics) {
                    if !parsingFailure.isEmpty { Text(parsingFailure).foregroundStyle(.orange) }
                    ForEach(issues) { issue in
                        Button {
                            revealRange = issue.range; revealRequest += 1
                        } label: {
                            Text("Parsing \(issue.line):\(issue.column): \(issue.message)")
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.orange)
                    }
                } label: {
                    Text("Diagnostics · \(issues.count + (parsingFailure.isEmpty ? 0 : 1))")
                        .foregroundStyle(.orange).contentShape(Rectangle())
                }.font(.system(size: 11, design: .monospaced)).padding(8)
            }
        }
    }
}
