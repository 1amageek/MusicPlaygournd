import SwiftUI

public struct SidebarDisclosureGroup<Label: View, Content: View>: View {
    @Binding private var isExpanded: Bool
    private let indentation: CGFloat
    private let name: String
    private let label: Label
    private let content: () -> Content

    public init(isExpanded: Binding<Bool>, indentation: CGFloat = 0, name: String,
                @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        _isExpanded = isExpanded
        self.indentation = indentation; self.name = name
        self.content = content; self.label = label()
    }

    public var body: some View {
        #if os(macOS)
        DisclosureGroup(isExpanded: $isExpanded, content: content) { label }
        #else
        Button { isExpanded.toggle() } label: {
            HStack(spacing: 4) {
                label
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 6 + indentation, bottom: 0, trailing: 6))
        .accessibilityLabel(name)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("sidebar-disclosure-" + name)
        if isExpanded { content() }
        #endif
    }
}
