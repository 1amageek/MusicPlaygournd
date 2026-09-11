import SwiftUI
import MusicPlaygourndCore

struct AudioSettingsView: View {
    @Bindable var workspace: DeckWorkspace

    @AppStorage("playback.sourceUpdateTiming") private var sourceUpdateTiming: SourceUpdateTiming = .immediate

    var body: some View {
        VStack(spacing: 10) {
            Picker("Main Output", selection: Binding(get: { workspace.mainDeviceID }, set: workspace.selectMainDevice)) {
                if workspace.mainDeviceID == nil { Text("Unavailable").tag(Optional<UInt32>.none) }
                ForEach(workspace.audioDevices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }.frame(width: 300).padding(.top, 20)
            Picker("Code Updates", selection: $sourceUpdateTiming) {
                ForEach(SourceUpdateTiming.allCases, id: \.self) { timing in
                    Text(timing.title).tag(timing)
                }
            }.frame(width: 300)
            Divider().frame(width: 332)
            CueSettingsView(workspace: workspace)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { workspace.refreshCueDevices() }
    }
}
