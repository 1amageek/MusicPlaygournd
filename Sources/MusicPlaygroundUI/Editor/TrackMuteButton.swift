import SwiftUI

public struct TrackMuteButton: View {
    let name: String
    let muted: Bool?
    let action: () -> Void

    public init(name: String, muted: Bool?, action: @escaping () -> Void) {
        self.name = name; self.muted = muted; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: muted == true ? "speaker.slash.fill" : "speaker.wave.2")
                .font(.system(size: 11))
                .foregroundStyle(muted == true ? Color.orange : Color.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(muted == nil)
        .help("\(muted == true ? "Unmute" : "Mute") \(name)")
        .accessibilityLabel("\(muted == true ? "Unmute" : "Mute") \(name)")
        .accessibilityValue(muted == true ? "Muted" : "Unmuted")
    }
}
