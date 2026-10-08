import SwiftUI
import MusicPlaygroundUI

struct NativeMasterView: View {
    @Bindable var audio: AudioWorkspace
    let colors: [Color]
    @Binding var maximumTakeMinutes: Int
    @State private var scope = false
    @State private var cue = false
    @State private var savedTake: NativeSavedRecording?
    var body: some View {
        MasterStrip(colorA: colors[0], colorB: colors[1], crossfade: Binding(get: { audio.crossfade }, set: { value in perform { try audio.setCrossfade(value) } }),
            volume: Binding(get: { audio.volume }, set: { value in perform { try audio.setVolume(value) } })) {
            Button { scope = true } label: {
                DeckVectorscopeView(samplesA: audio.a.samples, samplesB: audio.b.samples, colorA: colors[0], colorB: colors[1])
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.13))).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("A and B vectorscopes").accessibilityIdentifier("master-output")
                .accessibilityValue("A \(audio.a.isPlaying ? "playing" : "paused"); B \(audio.b.isPlaying ? "playing" : "paused")")
                .popover(isPresented: $scope) {
                    VectorscopeControlView(samples: audio.a.samples, balance: audio.balance, space: audio.space,
                        onBalanceChange: { value in perform { try audio.setBalance(value) } }, onSpaceChange: { value in perform { try audio.setSpace(value) } },
                        samplesB: audio.b.samples, colorA: colors[0], colorB: colors[1]).frame(width: 440, height: 360).padding(12)
                }
        } headphones: {
            Button { cue = true } label: { Image(systemName: "headphones").font(.system(size: 12)).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("Headphone output settings").popover(isPresented: $cue) { NativeCueSettings(audio: audio) }
        } record: {
            Button { Task { await record() } } label: {
                Image(systemName: audio.isRecording ? "stop.circle.fill" : "record.circle").contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Record master")
                .disabled(!audio.a.isPlaying && !audio.b.isPlaying && !audio.isRecording)
        }
        .sheet(item: $savedTake) { take in
                NavigationStack {
                    VStack(spacing: 24) {
                        Text("Recording saved").font(.headline)
                        Text(take.destination.lastPathComponent)
                        ShareLink("Save or Share WAV", item: take.destination).contentShape(Rectangle())
                    }.padding().navigationTitle("Master Recording")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { savedTake = nil }.contentShape(Rectangle()) } }
                }.presentationDetents([.medium])
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { audio.error = error.localizedDescription } }
    private func record() async {
        do {
            if audio.isRecording {
                let result = try await audio.output.stopRecording(); savedTake = NativeSavedRecording(destination: result.destination)
            } else {
                let url = try NativeControlsView.exportDestination(name: "Mix", extension: "wav")
                try audio.output.startRecording(MasterRecordingRequest(destination: url, maximumDuration: .seconds(maximumTakeMinutes * 60)))
            }
            audio.refresh()
        } catch { audio.error = error.localizedDescription }
    }
}
