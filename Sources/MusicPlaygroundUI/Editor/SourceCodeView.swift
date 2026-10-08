import SwiftUI

/// Read-only source adapter; editing and evaluation belong to the application.
public struct SourceCodeView: View {
    private let source: String
    public init(source: String) { self.source = source }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 16) {
                Text((1...max(1, source.split(separator: "\n", omittingEmptySubsequences: false).count))
                    .map(String.init).joined(separator: "\n"))
                    .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    .accessibilityHidden(true)
                Text(source).textSelection(.enabled).accessibilityIdentifier("source-code")
            }
            .font(.system(size: 13, design: .monospaced)).lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.08))
    }
}
