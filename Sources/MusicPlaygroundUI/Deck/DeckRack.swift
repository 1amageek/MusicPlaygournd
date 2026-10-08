import SwiftUI

public struct DeckRack<A: View, Master: View, B: View>: View {
    private let a: @MainActor () -> A
    private let master: @MainActor () -> Master
    private let b: @MainActor () -> B

    public init(@ViewBuilder a: @escaping @MainActor () -> A, @ViewBuilder master: @escaping @MainActor () -> Master, @ViewBuilder b: @escaping @MainActor () -> B) {
        self.a = a; self.master = master; self.b = b
    }

    public var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 860 {
                let centerWidth = min(260, max(170, geometry.size.width * 0.22))
                let deckWidth = (geometry.size.width - centerWidth - 2) / 2
                HStack(spacing: 0) {
                    a().frame(width: deckWidth)
                    Divider()
                    master().frame(width: centerWidth)
                    Divider()
                    b().frame(width: deckWidth)
                }.frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        a().frame(minWidth: 340).frame(height: 198)
                        Divider()
                        master().frame(height: 190)
                        Divider()
                        b().frame(minWidth: 340).frame(height: 198)
                    }
                }.accessibilityIdentifier("stacked-deck-rack")
            }
        }
        .frame(maxWidth: .infinity).frame(height: 208)
        .background(LinearGradient(colors: [Color(red: 0.055, green: 0.07, blue: 0.08), .black.opacity(0.45)],
                                   startPoint: .top, endPoint: .bottom))
    }
}
