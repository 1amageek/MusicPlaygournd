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
            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(red: 0.2, green: 1, blue: 0.65), .cyan,
                                  Color(red: 0.48, green: 0.38, blue: 1)]),
                startPoint: CGPoint(x: center.x - radius * 0.45, y: center.y - radius * 0.65),
                endPoint: CGPoint(x: center.x + radius * 0.45, y: center.y + radius * 0.65)
            )
            context.drawLayer { glow in
                glow.opacity = 0.35
                glow.addFilter(.blur(radius: 9))
                glow.stroke(trace, with: gradient, lineWidth: 5)
            }
            context.drawLayer { halo in
                halo.opacity = 0.75
                halo.addFilter(.blur(radius: 2))
                halo.stroke(trace, with: gradient, lineWidth: 2)
            }
            context.stroke(trace, with: gradient, style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
            context.stroke(trace, with: .color(.white.opacity(0.35)), lineWidth: 0.25)
        }
        .clipped()
        .accessibilityLabel("Stereo vectorscope, vertical mono and horizontal side signal")
        .help("Latest 2,048 stereo PCM frames. Vertical: mono; horizontal: stereo difference. Display gain ×4.")
    }
}
