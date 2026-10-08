import SwiftUI

/// The editor's attached timeline gutter; row positions come from NSTextView, not a second layout.
public struct SourceTimelineView<Score: RhythmScore>: View {
    let loop: Score?
    let rowLines: [Int: Int]
    let lineRects: [Int: CGRect]
    let beatPosition: Double
    let isPlaying: Bool
    let onScroll: (CGFloat) -> Void
    var mutedTracks: [Int: Bool] = [:]
    var onToggleTrackMute: (Int) -> Void = { _ in }
    private let colors: [Color] = [.mint, .cyan, .orange, .purple, .pink, .yellow]

    public init(loop: Score?, rowLines: [Int: Int], lineRects: [Int: CGRect], beatPosition: Double, isPlaying: Bool,
                onScroll: @escaping (CGFloat) -> Void, mutedTracks: [Int: Bool] = [:], onToggleTrackMute: @escaping (Int) -> Void = { _ in }) {
        self.loop = loop; self.rowLines = rowLines; self.lineRects = lineRects; self.beatPosition = beatPosition
        self.isPlaying = isPlaying; self.onScroll = onScroll; self.mutedTracks = mutedTracks; self.onToggleTrackMute = onToggleTrackMute
    }
    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if let loop {
                    Canvas { context, size in
                        let inset: CGFloat = 34
                        let scale = max(1, size.width - inset - 21) / CGFloat(loop.beatCount)
                        for beat in 0...Int(ceil(loop.beatCount)) {
                            let x = inset + CGFloat(beat) * scale
                            var grid = Path()
                            grid.move(to: CGPoint(x: x, y: 0))
                            grid.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(grid, with: .color(.white.opacity(beat % loop.beatsPerBar == 0 ? 0.09 : 0.035)))
                        }
                        for row in loop.rows {
                            guard let line = rowLines[row.sourceID], let rect = lineRects[line],
                                  rect.maxY > 0, rect.minY < size.height else { continue }
                            let color = colors[row.sourceID % colors.count]
                            let center = rect.midY
                            let height = max(8, rect.height - 4)
                            if row.trackID == nil {
                                context.draw(Text("\(line)").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: 16, y: center))
                            }
                            for event in loop.events where event.sourceID == row.sourceID {
                                event.forEachBeatRange(in: loop.beatCount) { range in
                                    let startX = inset + CGFloat(range.lowerBound) * scale
                                    let eventWidth = max(CGFloat(2), CGFloat(range.upperBound - range.lowerBound) * scale - 1)
                                    let box = CGRect(x: startX, y: center - height / 2, width: eventWidth, height: height)
                                    let active = isPlaying && event.gain > 0 && event.isActive(at: beatPosition, in: loop.beatCount)
                                    context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(color.opacity(active ? 0.28 : 0.09)))
                                    if range.lowerBound == event.startBeat {
                                        var onset = Path()
                                        onset.move(to: CGPoint(x: box.minX, y: box.minY))
                                        onset.addLine(to: CGPoint(x: box.minX, y: box.maxY))
                                        context.stroke(onset, with: .color(color.opacity(0.7)))
                                    }
                                }
                            }
                            let peakScale = max(0.000001, row.peaks.max() ?? 0)
                            var wave = Path()
                            for (index, peak) in row.peaks.enumerated() {
                                let x = inset + (CGFloat(index) + 0.5) / CGFloat(row.peaks.count) * (size.width - inset - 21)
                                let amplitude = CGFloat(min(1, peak / peakScale)) * height / 2
                                wave.move(to: CGPoint(x: x, y: center - max(0.4, amplitude)))
                                wave.addLine(to: CGPoint(x: x, y: center + max(0.4, amplitude)))
                            }
                            context.stroke(wave, with: .color(color.opacity(0.8)), lineWidth: 1)
                        }
                        var cursor = Path()
                        let x = inset + CGFloat(beatPosition) * scale
                        cursor.move(to: CGPoint(x: x, y: 0))
                        cursor.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(cursor, with: .color(.mint.opacity(isPlaying ? 0.8 : 0.18)), lineWidth: 1)
                    }
                    .help(loop.events.map(\.eventDescription).joined(separator: "\n"))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Source wave timeline, \(rowLines.count) aligned sources, \(loop.events.count) note events")
                    .overlay(alignment: .bottomLeading) {
                        if loop.rows.count > rowLines.count {
                            Text("\(loop.rows.count - rowLines.count) sources without a current line anchor")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                .padding(13).background(.black.opacity(0.65))
                        }
                    }
                } else {
                    VStack(spacing: 13) {
                        Image(systemName: "waveform.path").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(.mint)
                        Text("Sound takes shape here").font(.system(size: 13, weight: .medium))
                        Text("Play your code to reveal its waveform.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }.clipped().overlay { TimelineScrollRelay(onScroll: onScroll) }
                .overlay(alignment: .topLeading) {
                    GeometryReader { geometry in
                        if let loop {
                            ForEach(loop.rows, id: \.sourceID) { row in
                                if let track = row.trackID, let line = rowLines[row.sourceID],
                                   let rect = lineRects[line], rect.maxY > 0, rect.minY < geometry.size.height {
                                    TrackMuteButton(name: row.label, muted: mutedTracks[track]) { onToggleTrackMute(track) }
                                        .position(x: 16, y: rect.midY)
                                }
                            }
                        }
                    }
                }.clipped()
        }.background(Color(red: 0.055, green: 0.075, blue: 0.085))
    }
}
