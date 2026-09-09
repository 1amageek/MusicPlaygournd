import SwiftUI

struct WelcomeView: View {
    @Bindable var model: SessionModel

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.mint.gradient)
                Text("MusicPlayground").font(.system(size: 32, weight: .semibold))
                Text("Make music with Swift.").foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Button(action: model.newProject) {
                    Label("Create a new project…", systemImage: "plus.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button(action: model.chooseProject) {
                    Label("Open an existing project…", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .frame(width: 300)
            if model.isOpeningPackage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.preparationProgress).font(.callout).foregroundStyle(.secondary)
                }
            }
            if let error = model.fileBrowser.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange)
                    .textSelection(.enabled).frame(maxWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("welcome")
    }
}
