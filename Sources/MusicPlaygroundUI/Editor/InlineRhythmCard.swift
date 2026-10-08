import SwiftUI

public struct InlineRhythmCard<Event: RhythmEvent>: View {
    let label: String
    let events: [Event]
    let beats: Double
    let meter: Int
    let beat: Double
    let playing: Bool
    let muted: Bool?
    let hasTrack: Bool
    let toggle: () -> Void
    public init(label: String, events: [Event], beats: Double, meter: Int, beat: Double, playing: Bool,
                muted: Bool?, hasTrack: Bool, toggle: @escaping () -> Void) {
        self.label = label; self.events = events; self.beats = beats; self.meter = meter
        self.beat = beat; self.playing = playing; self.muted = muted; self.hasTrack = hasTrack; self.toggle = toggle
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if hasTrack { TrackMuteButton(name: label, muted: muted, action: toggle) }
                Text(label).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
            }.frame(height: 22)
            Canvas { context, size in
                let area = CGRect(x: 32, y: 2, width: max(1, size.width - 32), height: 18)
                let scale = area.width / max(1, beats)
                let notes = events.compactMap(\.displayedMIDINote)
                let low = notes.min() ?? 0, high = notes.max() ?? low
                let laneHeight = area.height / CGFloat(max(1, high - low + 1))
                let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
                if !notes.isEmpty {
                    context.draw(Text("\(names[low % 12])\(low / 12 - 1)").font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: 14, y: area.maxY - 3))
                    if high != low { context.draw(Text("\(names[high % 12])\(high / 12 - 1)").font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: 14, y: area.minY + 3)) }
                }
                for index in 0...Int(ceil(beats)) {
                    let x = area.minX + CGFloat(index) * scale
                    var path = Path(); path.move(to: CGPoint(x: x, y: area.minY)); path.addLine(to: CGPoint(x: x, y: area.maxY))
                    context.stroke(path, with: .color(.white.opacity(index % meter == 0 ? 0.16 : 0.06)))
                }
                for event in events {
                    let active = playing && event.gain > 0 && event.isActive(at: beat, in: beats)
                    let y = area.minY + CGFloat(high - (event.displayedMIDINote ?? high)) * laneHeight
                    event.forEachBeatRange(in: beats) { range in
                        let rect = CGRect(x: area.minX + range.lowerBound * scale, y: y + 1,
                            width: max(2, (range.upperBound - range.lowerBound) * scale - 2), height: max(2, laneHeight - 2))
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.mint.opacity(active ? 1 : (event.gain > 0 ? 0.45 : 0.12))))
                    }
                }
                let x = area.minX + beat * scale
                var cursor = Path(); cursor.move(to: CGPoint(x: x, y: area.minY - 3)); cursor.addLine(to: CGPoint(x: x, y: area.maxY + 3))
                context.stroke(cursor, with: .color(.white.opacity(playing ? 0.9 : 0.2)))
            }.frame(height: 22)
        }.padding(.horizontal, 12).frame(height: 48)
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.07)))
            .accessibilityElement(children: .contain).accessibilityLabel("Inline rhythm, \(label), \(events.count) events, \(Int(beats)) beats")
    }
}
