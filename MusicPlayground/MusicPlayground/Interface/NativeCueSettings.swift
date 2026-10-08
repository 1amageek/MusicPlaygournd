import SwiftUI

struct NativeCueSettings: View {
    @Bindable var audio: AudioWorkspace
    @State private var devices: [CueOutputDevice] = []
    @State private var cueDevices: [CueOutputDevice] = []
    @State private var mainID: UInt32?
    @State private var cueID: UInt32?
    @State private var mix = 0.0
    @State private var level = 0.5
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Headphones", systemImage: "headphones").font(.headline)
            Picker("Main Output", selection: Binding(get: { mainID }, set: { id in
                guard let id else { return }; perform { try audio.output.selectMainOutput(id) }; refresh()
            })) {
                ForEach(devices) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Cue Output", selection: Binding(get: { cueID }, set: { id in perform { try audio.output.selectCueDevice(id) }; refresh() })) {
                Text("None").tag(Optional<UInt32>.none)
                ForEach(cueDevices) { Text($0.name).tag(Optional($0.id)) }
            }
            HStack { Text("CUE"); Slider(value: Binding(get: { mix }, set: { value in perform { try audio.output.setCueMix(Float(value)) }; mix = Double(audio.output.cueMix) }), in: 0...1); Text("MASTER") }
                .accessibilityLabel("Cue master mix")
            Slider(value: Binding(get: { level }, set: { value in perform { try audio.output.setCueLevel(Float(value)) }; level = Double(audio.output.cueLevel) }), in: 0...1).accessibilityLabel("Headphone level")
            if let error { Text(error).foregroundStyle(.orange) }
            else if cueDevices.isEmpty { Text("Connect an audio interface with a separate stereo headphone output.").foregroundStyle(.secondary) }
            Button("Refresh Outputs", action: refresh).contentShape(Rectangle())
        }.font(.system(size: 11)).padding(18).frame(width: 300).onAppear(perform: refresh)
    }
    private func perform(_ body: () throws -> Void) { do { try body(); error = nil } catch { self.error = error.localizedDescription } }
    private func refresh() {
        perform {
            devices = try CueOutputDevice.available(); mainID = try audio.output.mainOutputDeviceID()
            cueDevices = try audio.output.availableCueDevices(); cueID = audio.output.cueDeviceID
            mix = Double(audio.output.cueMix); level = Double(audio.output.cueLevel)
        }
        audio.refresh()
    }
}
