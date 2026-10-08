import SwiftUI

public struct UnavailableEffectView: View {
    private let reason: String
    public init(reason: String) { self.reason = reason }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("FX unavailable", systemImage: "slider.horizontal.3").font(.headline)
            Text(reason).font(.callout).foregroundStyle(.secondary)
        }.padding(18).frame(width: 300).accessibilityIdentifier("effect-unavailable")
    }
}
