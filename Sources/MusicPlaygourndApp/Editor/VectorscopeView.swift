import SwiftUI

struct VectorscopeView: View {
    let samples: [Float]
    var leftColor: Color = Color(red: 0.2, green: 1, blue: 0.65)
    var rightColor: Color = Color(red: 0.48, green: 0.38, blue: 1)

    var traceColor: Color?
    var horizontalExpansion: CGFloat = 1
    var dashed = false
    var glowOpacity: Double = 1
    var temporalSampleRate: Double?
    var secondarySamples: [Float]?
    var secondaryColor: Color = .clear

    /// Fixed display gain; the projection never changes playback amplitude.
    static func position(left: Float, right: Float) -> CGPoint? {
        guard left.isFinite, right.isFinite else { return nil }
        return CGPoint(x: (Double(left) - Double(right)) * 2,
                       y: -(Double(left) + Double(right)) * 2)
    }

    /// The phosphor-like trail loses half its brightness every 35 ms of audio.
    static func trailOpacity(framesAgo: Int, sampleRate: Double) -> Double {
        guard framesAgo >= 0, sampleRate.isFinite, sampleRate > 0 else { return 0 }
        return pow(0.5, Double(framesAgo) / sampleRate / 0.035)
    }

    /// Projects Side/Mid/time through a shared camera; negative Z is older audio.
    static func project(_ point: CGPoint, age: Double, size: CGSize,
                        horizontalExpansion: CGFloat = 4) -> (point: CGPoint, depth: Double)? {
        guard point.x.isFinite, point.y.isFinite, age.isFinite, age >= 0 else { return nil }
        let x = Double(point.x * horizontalExpansion)
        let y = -Double(point.y)
        let z = -age / 0.2 * 1.4
        let yaw = 0.42, pitch = 0.24
        let rotatedX = x * cos(yaw) + z * sin(yaw)
        let rotatedZ = -x * sin(yaw) + z * cos(yaw)
        let rotatedY = y * cos(pitch) - rotatedZ * sin(pitch)
        let depth = y * sin(pitch) + rotatedZ * cos(pitch)
        guard 4 - depth > 0.1 else { return nil }
        let perspective = 4 / (4 - depth)
        let horizontalScale = size.width * 0.36
        let verticalScale = size.height * 0.36
        return (CGPoint(x: size.width * 0.52 + rotatedX * perspective * horizontalScale,
                        y: size.height * 0.58 - rotatedY * perspective * verticalScale), depth)
    }

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.46
            let horizontalRadius = horizontalExpansion == 1 ? radius : size.width * 0.46 * horizontalExpansion
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var traces: [(path: Path, opacity: Double, color: Color?, dashed: Bool, depth: Double)] = []
            traces.reserveCapacity(32)
            for (values, color, dashed) in [(samples, traceColor, dashed),
                                            (secondarySamples ?? [], Optional(secondaryColor), true)] {
                let frames = values.count / 2
                let first = max(0, frames - 8_192)
                let chunkSize = temporalSampleRate == nil ? max(1, frames - first) : 512
                for start in stride(from: first, to: frames, by: chunkSize) {
                    let end = min(frames, start + chunkSize)
                    var trace = Path()
                    var connected = false
                    var depth = 0.0
                    var count = 0
                    for frame in max(first, start - 1)..<end {
                        guard let point = Self.position(left: values[frame * 2], right: values[frame * 2 + 1]) else {
                            connected = false
                            continue
                        }
                        if point == .zero { connected = false; continue }
                        let position: CGPoint
                        if let rate = temporalSampleRate {
                            guard let projected = Self.project(point, age: Double(frames - 1 - frame) / rate,
                                size: size, horizontalExpansion: horizontalExpansion) else {
                                connected = false
                                continue
                            }
                            position = projected.point
                            depth += projected.depth
                            count += 1
                        } else {
                            position = CGPoint(x: center.x + point.x * horizontalRadius, y: center.y + point.y * radius)
                        }
                        if connected { trace.addLine(to: position) } else { trace.move(to: position) }
                        connected = true
                    }
                    let opacity = temporalSampleRate.map { Self.trailOpacity(framesAgo: frames - end, sampleRate: $0) } ?? 1
                    traces.append((trace, opacity, color, dashed, count > 0 ? depth / Double(count) : 0))
                }
            }
            // Both decks share back-to-front ordering instead of painting all of B over A.
            traces.sort { $0.depth < $1.depth }
            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: traceColor.map { [$0.opacity(0.65), $0, $0.opacity(0.9)] } ?? [leftColor, .cyan, rightColor]),
                startPoint: CGPoint(x: center.x - radius * 0.45, y: center.y),
                endPoint: CGPoint(x: center.x + radius * 0.45, y: center.y)
            )
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 9))
                for trace in traces {
                    glow.opacity = 0.35 * glowOpacity * trace.opacity
                    glow.stroke(trace.path, with: trace.color.map { .color($0) } ?? gradient, lineWidth: 5)
                }
            }
            context.drawLayer { halo in
                halo.addFilter(.blur(radius: 2))
                for trace in traces {
                    halo.opacity = 0.75 * glowOpacity * trace.opacity
                    halo.stroke(trace.path, with: trace.color.map { .color($0) } ?? gradient, lineWidth: 2)
                }
            }
            context.drawLayer { line in
                for trace in traces {
                    line.opacity = trace.opacity
                    line.stroke(trace.path, with: trace.color.map { .color($0) } ?? gradient, style: StrokeStyle(lineWidth: 0.9, lineCap: .round,
                        lineJoin: .round, dash: trace.dashed ? [4, 3] : []))
                    if trace.color == nil {
                        line.stroke(trace.path, with: .color(.white.opacity(0.35)), lineWidth: 0.25)
                    }
                }
            }
        }
        .clipped()
        .accessibilityLabel("Stereo vectorscope, vertical mono and horizontal side signal")
        .help("Latest 8,192 stereo PCM frames. Vertical: mono; horizontal: stereo difference. Display gain ×4. Side expansion ×\(Int(horizontalExpansion)).")
    }
}
