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
            VStack(spacing: 10) {
                Button(action: model.newProject) {
                    Label("Create a new project…", systemImage: "plus.square")
                        .fixedSize()
                        .frame(width: 264, height: 28, alignment: .leading)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button(action: model.chooseProject) {
                    Label("Open an existing project…", systemImage: "folder")
                        .fixedSize()
                        .frame(width: 264, height: 28, alignment: .leading)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            .font(.system(size: 13))
            .buttonStyle(.bordered)
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
