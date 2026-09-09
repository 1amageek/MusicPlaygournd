import SwiftUI

struct VectorscopeView: View {
    let samples: [Float]

    /// Fixed display gain; the projection never changes playback amplitude.
    static func position(left: Float, right: Float) -> CGPoint? {
        guard left.isFinite, right.isFinite else { return nil }
        return CGPoint(x: (Double(left) - Double(right)) * 2,
                       y: -(Double(left) + Double(right)) * 2)
    }

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.46
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let frames = samples.count / 2
            var trace = Path()
            var connected = false
            for frame in max(0, frames - 2_048)..<frames {
                guard let point = Self.position(left: samples[frame * 2], right: samples[frame * 2 + 1]) else {
                    connected = false
                    continue
                }
                if point == .zero { connected = false; continue }
                let position = CGPoint(x: center.x + point.x * radius, y: center.y + point.y * radius)
                if connected { trace.addLine(to: position) } else { trace.move(to: position) }
                connected = true
            }
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 5))
                glow.stroke(trace, with: .color(.cyan.opacity(0.45)), lineWidth: 3)
            }
            context.stroke(trace, with: .color(.cyan.opacity(0.8)), lineWidth: 0.8)
        }
        .clipped()
        .accessibilityLabel("Stereo vectorscope, vertical mono and horizontal side signal")
        .help("Latest 2,048 stereo PCM frames. Vertical: mono; horizontal: stereo difference. Display gain ×4.")
    }
}
