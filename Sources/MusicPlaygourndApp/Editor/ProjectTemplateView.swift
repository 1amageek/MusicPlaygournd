import SwiftUI

struct ProjectTemplateView: View {
    @Bindable var model: SessionModel
    @State private var selection = ProjectTemplate.deepCurrent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose a template").font(.title2.bold())
            HStack(spacing: 14) {
                ForEach(ProjectTemplate.allCases) { template in
                    Button { selection = template } label: {
                        VStack(spacing: 12) {
                            Image(systemName: template.symbol)
                                .font(.system(size: 32, weight: .light)).foregroundStyle(.mint)
                            Text(template.title).font(.headline)
                            Text(template.detail).font(.callout).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).frame(height: 160).padding(12)
                        .background(selection == template ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selection == template ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == template ? .isSelected : [])
                }
            }
            if let error = model.fileBrowser.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Next…") { model.createNewProject(template: selection) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 560)
    }
}
