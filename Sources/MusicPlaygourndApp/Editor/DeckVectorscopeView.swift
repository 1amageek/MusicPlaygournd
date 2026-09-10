import SwiftUI
import MusicPlaygourndCore

/// Overlays both pre-mix stereo signals in one shared Mid/Side coordinate system.
struct DeckVectorscopeView: View {
    let samplesA: [Float]
    let samplesB: [Float]
    let colorA: Color
    let colorB: Color

    var body: some View {
        ZStack {
            Canvas { context, size in
                let origin = VectorscopeView.project(.zero, age: 0, size: size)?.point
                if let origin {
                    for (point, age) in [(CGPoint(x: 0.25, y: 0), 0.0),
                                         (CGPoint(x: 0, y: -1), 0.0), (.zero, 0.2)] {
                        guard let end = VectorscopeView.project(point, age: age, size: size)?.point else { continue }
                        var axis = Path()
                        axis.move(to: origin); axis.addLine(to: end)
                        context.stroke(axis, with: .color(.white.opacity(0.18)),
                                       style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    }
                }
            }
            VectorscopeView(samples: samplesA, traceColor: colorA, horizontalExpansion: 4,
                            glowOpacity: 0.2, temporalSampleRate: PreparedLoop.requiredSampleRate,
                            secondarySamples: samplesB, secondaryColor: colorB)
            VStack {
                HStack {
                    Text("A").foregroundStyle(colorA)
                    Spacer()
                    Text("B").foregroundStyle(colorB)
                }.font(.system(size: 9, weight: .semibold))
                Spacer()
                Text("SIDE ×4 · MID · TIME → Z")
                    .font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A and B pre-mix vectorscopes, shared Side Mid Time axes, Side display times four")
        .help("A: solid trace. B: dashed trace. Shared 3D axes: Side, Mid, time. Older audio recedes and fades.")
    }
}
