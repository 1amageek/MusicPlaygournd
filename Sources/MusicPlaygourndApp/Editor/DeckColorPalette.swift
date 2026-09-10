import AppKit
import SwiftUI

struct DeckColorPalette: View {
    let name: String
    @Binding var selection: Color
    private let colors: [(String, Color)] = [
        ("Cyan", .cyan), ("Mint", .mint), ("Green", .green),
        ("Yellow", .yellow), ("Orange", .orange), ("Red", .red),
        ("Rose", Color(red: 1, green: 55.0 / 255, blue: 95.0 / 255)),
        ("Magenta", Color(red: 219.0 / 255, green: 52.0 / 255, blue: 242.0 / 255)),
        ("Purple", Color(red: 168.0 / 255, green: 85.0 / 255, blue: 247.0 / 255)), ("Indigo", .indigo), ("Blue", .blue), ("White", .white)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deck \(name) Color").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 6), spacing: 10) {
                ForEach(colors.indices, id: \.self) { index in
                    let (label, color) = colors[index]
                    Button { selection = color } label: {
                        RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 26, height: 26)
                            .overlay {
                                if selected(color) {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                                }
                            }
                    }.buttonStyle(.plain).accessibilityLabel("Deck \(name) \(label)")
                        .accessibilityValue(selected(color) ? "Selected" : "Not selected")
                        .help(label)
                }
            }
            Divider()
            ColorPicker("Custom…", selection: $selection, supportsOpacity: false)
        }.padding(14).frame(width: 224)
    }

    private func selected(_ color: Color) -> Bool {
        guard let a = NSColor(selection).usingColorSpace(.sRGB), let b = NSColor(color).usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.002
            && abs(a.greenComponent - b.greenComponent) < 0.002
            && abs(a.blueComponent - b.blueComponent) < 0.002
    }
}
