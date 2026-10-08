import SwiftUI

@MainActor
public struct InlineSourceResult: Identifiable {
    public let id: Int
    public let line: Int
    public let content: AnyView
    public init<Content: View>(id: Int, line: Int, @ViewBuilder content: () -> Content) {
        self.id = id; self.line = line; self.content = AnyView(content())
    }
}
