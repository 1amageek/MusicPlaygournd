import SwiftUI

public struct EditorAppearanceControls: View {
    @AppStorage("editor.fontSize") private var fontSize = 12.0
    @AppStorage("editor.theme") private var theme: EditorTheme = .midnight

    public init() { }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Theme", selection: $theme) {
                ForEach(EditorTheme.allCases) { Text($0.rawValue).tag($0) }
            }.contentShape(Rectangle()).accessibilityIdentifier("editor-theme")
            Stepper(value: $fontSize, in: 10...24, step: 1) {
                Text("Font size: \(Int(fontSize)) pt").monospacedDigit()
            }.contentShape(Rectangle()).accessibilityIdentifier("editor-font-size")
            Text("Changes apply immediately to all editor tabs.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
