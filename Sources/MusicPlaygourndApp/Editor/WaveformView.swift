import SwiftUI

struct WaveformView: View {
    let samples: [Float]

    var body: some View {
        Canvas { context, size in
            let frames = samples.count / 2
            let columns = max(1, min(512, Int(size.width)))
            for channel in 0..<2 {
                var wave = Path()
                for column in 0..<columns {
                    let start = column * frames / columns
                    let end = (column + 1) * frames / columns
                    guard start < end else { continue }
                    var low: Float = 0
                    var high: Float = 0
                    for frame in start..<end {
                        let value = samples[frame * 2 + channel]
                        if value.isFinite { low = min(low, value); high = max(high, value) }
                    }
                    let x = Double(column) / Double(columns) * size.width
                    let center = size.height * 0.5
                    wave.move(to: CGPoint(x: x, y: center - min(1, Double(high) * 4) * size.height * 0.47))
                    wave.addLine(to: CGPoint(x: x, y: center - max(-1, Double(low) * 4) * size.height * 0.47))
                }
                context.stroke(wave, with: .color(channel == 0 ? .mint : .cyan.opacity(0.65)), lineWidth: 1)
            }
        }.clipped()
        .accessibilityLabel("Stereo master output waveform")
        .help("Latest 8,192 stereo PCM frames. Display amplitude ×4; audio level is unchanged.")
    }
}
