import SwiftUI

struct CueSettingsView: View {
    @Bindable var workspace: DeckWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Headphones", systemImage: "headphones").font(.headline)
            Picker("Output", selection: Binding(get: { workspace.cueDeviceID }, set: workspace.selectCueDevice)) {
                Text("None").tag(Optional<UInt32>.none)
                ForEach(workspace.cueDevices) { device in Text(device.name).tag(Optional(device.id)) }
            }
            HStack {
                Text("CUE")
                Slider(value: $workspace.cueMix, in: 0...1).accessibilityLabel("Headphone cue master mix")
                Text("MASTER")
            }.font(.caption)
            HStack {
                Image(systemName: "speaker.wave.2")
                Slider(value: $workspace.cueLevel, in: 0...1).accessibilityLabel("Headphone volume")
            }
            if let error = workspace.cueError {
                Text(error).foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true)
            } else if workspace.cueDeviceID == nil {
                Text("Connect headphones or an audio interface, then select its output. The main output is excluded.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Refresh Outputs") { workspace.refreshCueDevices() }
                .controlSize(.small)
        }.padding(16).frame(width: 300)
    }
}
