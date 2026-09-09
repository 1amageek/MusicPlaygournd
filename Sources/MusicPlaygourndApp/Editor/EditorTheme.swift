import AppKit

/// Complete syntax palettes shared by the editor and Settings preview.
enum EditorTheme: String, CaseIterable, Identifiable {
    case midnight = "Midnight"
    case light = "Light"
    case dark = "Dark"
    case dracula = "Dracula"
    case solarized = "Solarized Dark"
    var id: Self { self }

    struct Palette {
        let background, foreground, comment, string, keyword, type, accent: NSColor
        init(_ background: UInt32, _ foreground: UInt32, _ comment: UInt32, _ string: UInt32,
             _ keyword: UInt32, _ type: UInt32, _ accent: UInt32) {
            func color(_ hex: UInt32) -> NSColor {
                NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                        green: Double((hex >> 8) & 255) / 255,
                        blue: Double(hex & 255) / 255, alpha: 1)
            }
            self.background = color(background); self.foreground = color(foreground)
            self.comment = color(comment); self.string = color(string)
            self.keyword = color(keyword); self.type = color(type); self.accent = color(accent)
        }
    }

    private static let midnightPalette = Palette(0x111318, 0xE1E1E1, 0x8D959F, 0xFFAA60, 0xFF497C, 0x3CDEEF, 0x36D9B8)
    private static let lightPalette = Palette(0xFFFFFF, 0x202124, 0x637167, 0xB3261E, 0x9B2393, 0x245F91, 0x1769AA)
    private static let darkPalette = Palette(0x202124, 0xE8EAED, 0x98A1A8, 0xFC8C87, 0xFC69B0, 0x66C8D1, 0x78B9FF)
    private static let draculaPalette = Palette(0x282A36, 0xF8F8F2, 0x8996C0, 0xF1FA8C, 0xFF79C6, 0x8BE9FD, 0xBD93F9)
    private static let solarizedPalette = Palette(0x002B36, 0x93A1A1, 0x839496, 0x2AA198, 0xB58900, 0x268BD2, 0x2AA198)

    var palette: Palette {
        switch self {
        case .midnight: Self.midnightPalette
        case .light: Self.lightPalette
        case .dark: Self.darkPalette
        case .dracula: Self.draculaPalette
        case .solarized: Self.solarizedPalette
        }
    }
}
