import SwiftUI

struct WelcomeView: View {
    @Bindable var model: SessionModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.mint.gradient)
                    .frame(height: 84)
                    .padding(.bottom, 8)
                Text("MusicPlayground").font(.system(size: 20, weight: .semibold))
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("Version \(version)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button("Open…", action: model.chooseProject)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .accessibilityLabel("Open an existing project…")
                Button("New Project…", action: model.newProject)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .accessibilityLabel("Create a new project…")
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            if model.isOpeningPackage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.preparationProgress).font(.callout).foregroundStyle(.secondary)
                }
            }
            if let error = model.fileBrowser.errorMessage {
                ScrollView {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 64)
            }
        }
        .padding(32)
        .frame(width: 480, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("welcome")
    }
}
