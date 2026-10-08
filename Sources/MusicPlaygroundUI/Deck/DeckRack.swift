import SwiftUI

public struct DeckRack<A: View, Master: View, B: View>: View {
    private let a: A
    private let master: Master
    private let b: B

    public init(@ViewBuilder a: () -> A, @ViewBuilder master: () -> Master, @ViewBuilder b: () -> B) {
        self.a = a(); self.master = master(); self.b = b()
    }

    public var body: some View {
        GeometryReader { geometry in
            let centerWidth = min(260, max(170, geometry.size.width * 0.22))
            HStack(spacing: 0) {
                a
                Divider()
                master.frame(width: centerWidth)
                Divider()
                b
            }
        }
        .frame(height: 208)
        .background(LinearGradient(colors: [Color(red: 0.055, green: 0.07, blue: 0.08), .black.opacity(0.45)],
                                   startPoint: .top, endPoint: .bottom))
    }
}
