import SwiftUI

public struct EditorPane<Tabs: View, Content: View>: View {
    private let showsTabs: Bool
    private let tabs: Tabs
    private let content: Content

    public init(showsTabs: Bool = true, @ViewBuilder tabs: () -> Tabs, @ViewBuilder content: () -> Content) {
        self.showsTabs = showsTabs; self.tabs = tabs(); self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsTabs { tabs.frame(height: 28); Divider() }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
