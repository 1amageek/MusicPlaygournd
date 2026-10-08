import SwiftUI

public struct SidebarToggle: View {
    @Binding private var visibility: NavigationSplitViewVisibility
    public init(visibility: Binding<NavigationSplitViewVisibility>) { _visibility = visibility }

    public var body: some View {
        Button { visibility = visibility == .detailOnly ? .all : .detailOnly } label: {
            Image(systemName: "sidebar.left").frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(visibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar")
        .accessibilityIdentifier("sidebar-toggle")
        .help("Show or hide the file sidebar")
    }
}
