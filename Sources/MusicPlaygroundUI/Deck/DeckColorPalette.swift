import SwiftUI

public struct DeckColorPalette: View {
    public init(name: String, selection: Binding<Color>) { self.name = name; self._selection = selection }
    let name: String
    @Binding var selection: Color
    @Environment(\.self) private var environment
    private let colors: [(String, Color)] = [
        ("Cyan", .cyan), ("Mint", .mint), ("Green", .green),
        ("Yellow", .yellow), ("Orange", .orange), ("Red", .red),
        ("Rose", Color(red: 1, green: 55.0 / 255, blue: 95.0 / 255)),
        ("Magenta", Color(red: 219.0 / 255, green: 52.0 / 255, blue: 242.0 / 255)),
        ("Purple", Color(red: 168.0 / 255, green: 85.0 / 255, blue: 247.0 / 255)), ("Indigo", .indigo), ("Blue", .blue), ("White", .white)
    ]

    public var body: some View {
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
                    }.buttonStyle(.plain).contentShape(Rectangle()).accessibilityLabel("Deck \(name) \(label)")
                        .accessibilityValue(selected(color) ? "Selected" : "Not selected")
                        .help(label)
                }
            }
            Divider()
            ColorPicker("Custom…", selection: $selection, supportsOpacity: false)
        }.padding(14).frame(width: 224)
    }

    private func selected(_ color: Color) -> Bool {
        let a = selection.resolve(in: environment), b = color.resolve(in: environment)
        return abs(a.red - b.red) < 0.002 && abs(a.green - b.green) < 0.002 && abs(a.blue - b.blue) < 0.002
    }
}
