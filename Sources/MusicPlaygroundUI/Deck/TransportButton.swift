import SwiftUI

public struct TransportButton: View {
    private let symbol: String
    private let label: String
    private let value: String
    private let enabled: Bool
    private let action: () -> Void

    public init(symbol: String, label: String, value: String = "", enabled: Bool = true,
                action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.value = value
        self.enabled = enabled; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.3)).contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label).accessibilityValue(value)
    }
}
