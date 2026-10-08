import SwiftUI

public struct WorkspaceSplitView<Sidebar: View, Detail: View>: View {
    @Binding private var visibility: NavigationSplitViewVisibility
    private let sidebar: Sidebar
    private let detail: Detail

    public init(visibility: Binding<NavigationSplitViewVisibility>,
                @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        _visibility = visibility; self.sidebar = sidebar(); self.detail = detail()
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            sidebar.navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 320)
        } detail: { detail }
        .navigationSplitViewStyle(.balanced)
    }
}
