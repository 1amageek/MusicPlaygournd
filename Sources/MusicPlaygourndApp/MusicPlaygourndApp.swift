import AppKit
import SwiftUI

@main
struct MusicPlaygourndApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @State private var model = SessionModel()

    var body: some Scene {
        Window("MusicPlaygournd", id: "editor") {
            ContentView(model: model)
                .onAppear { delegate.model = model; model.prepareInitialSource(); NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1160, height: 760)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…", action: model.newProject).keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open Project…", action: model.chooseProject).keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Open Session…", action: model.openDocument).keyboardShortcut("o")
                Button("Close Tab") { model.closeDocument(model.activeDocumentID) }.keyboardShortcut("w").disabled(!model.hasOpenDocument)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Session") { model.saveDocument() }.keyboardShortcut("s").disabled(!model.hasOpenDocument)
            }
            CommandGroup(after: .textEditing) {
                Button("Toggle Comment") {
                    NSApp.sendAction(#selector(CompletionTextView.toggleComment(_:)), to: nil, from: nil)
                }.keyboardShortcut("/", modifiers: .command)
                    .disabled(!model.hasOpenDocument || model.activeDocument.isReadOnly)
            }
            CommandMenu("Session") {
                Button("Apply Edit") { model.scheduleEvaluation(immediate: true) }.keyboardShortcut("r").disabled(!model.hasOpenDocument)
                Button("Play / Pause", action: model.togglePlayback).disabled(!model.hasOpenDocument && !model.isPlaying)
                Divider()
                Button("Inline Results") { model.inlineLayout = true }
                Button("Side Timeline") { model.inlineLayout = false; model.bottomLayout = false }
                Button("Bottom Overview") { model.inlineLayout = false; model.bottomLayout = true }
            }
        }
        Settings { EditorSettingsView(semanticTokens: model.previewSemanticTokens) }
    }
}
