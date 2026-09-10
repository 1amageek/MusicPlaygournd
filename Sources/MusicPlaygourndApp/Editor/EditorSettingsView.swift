import SwiftUI
import MusicPlaygourndCore

struct EditorSettingsView: View {
    let workspace: DeckWorkspace
    let semanticTokens: @MainActor (String) async throws -> [SwiftSemanticToken]
    @State private var highlightingStatus = ""
    @AppStorage("editor.fontSize") private var fontSize = 12.0
    @AppStorage("editor.theme") private var theme: EditorTheme = .midnight

    var body: some View {
        TabView {
            HStack(spacing: 0) {
                List(EditorTheme.allCases, selection: Binding<EditorTheme?>(
                    get: { theme }, set: { if let value = $0 { theme = value } }
                )) { theme in
                    HStack(spacing: 10) {
                        Text("Aa").font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(nsColor: theme.palette.keyword))
                            .frame(width: 34, height: 28)
                            .background(Color(nsColor: theme.palette.background), in: RoundedRectangle(cornerRadius: 4))
                        Text(theme.rawValue)
                    }.tag(theme)
                }.listStyle(.sidebar).frame(width: 185)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(theme.rawValue).font(.headline)
                        Spacer()
                        Stepper(value: $fontSize, in: 10...24, step: 1) {
                            Text("Font size: \(Int(fontSize)) pt").monospacedDigit()
                        }.fixedSize()
                        .accessibilityIdentifier("editor-font-size")
                    }
                    preview
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    if !highlightingStatus.isEmpty {
                        Text(highlightingStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Changes apply immediately to all editor tabs.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .tabItem { Label("Themes & Fonts", systemImage: "textformat") }
            AudioSettingsView(workspace: workspace)
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
        }.frame(width: 720, height: 400)
    }

    private var preview: some View {
        CodeEditor(text: .constant("""
        import SwiftMusic

        // A rhythm in motion.
        struct Session: Music {
            var body: some Sound {
                Track("Kick") {
                    Sample("kick")
                        .rhythm("x ~ x ~")
                        .gain(0.8)
                }
            }
        }
        """), inlineLoop: nil, inlineEnabled: false, resultLines: [:], beatPosition: 0,
            isPlaying: false, selectionLine: nil, selectionToken: 0, rhythmLines: [], rowLines: [:],
            patternTexts: [:], activeTokens: [:], scrollDelta: 0, onLayout: { _ in }, beforeEdit: { _, _ in },
            onEdit: {}, completions: { _, _ in [] }, onCompletionStatus: { _ in }, semanticTokens: semanticTokens,
            onHighlightStatus: { highlightingStatus = $0 }, isReadOnly: true)
    }
}
