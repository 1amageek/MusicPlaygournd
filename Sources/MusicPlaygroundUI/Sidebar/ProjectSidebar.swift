import SwiftUI

public struct ProjectSidebar<Selection: Hashable, Rows: View, Footer: View>: View {
    @Binding private var selection: Selection?
    private let rows: Rows
    private let footer: Footer
    private let error: String?

    public init(selection: Binding<Selection?>, error: String? = nil,
                @ViewBuilder rows: () -> Rows, @ViewBuilder footer: () -> Footer) {
        _selection = selection; self.error = error; self.rows = rows(); self.footer = footer()
    }

    public var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) { rows }
                .listStyle(.sidebar)
                .font(.system(size: 12))
                .controlSize(.small)
                .environment(\.defaultMinListRowHeight, minimumRowHeight)
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                    .textSelection(.enabled).padding(8)
            }
            Divider()
            footer
        }
        .background(.bar)
        .accessibilityIdentifier("project-sidebar")
    }

    private var minimumRowHeight: CGFloat {
        #if os(macOS)
        22
        #else
        44
        #endif
    }
}
