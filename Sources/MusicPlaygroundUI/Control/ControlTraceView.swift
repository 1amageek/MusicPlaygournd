import SwiftUI

public struct ControlTraceView<Value: ControlTrajectory>: View {
    let value: Value
    let sourceID: Int?
    public init(value: Value, sourceID: Int? = nil) { self.value = value; self.sourceID = sourceID }
    public var body: some View {
        Canvas { context, size in
            let area = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            context.clip(to: Path(area))
            let traces = value.traces.lazy.filter { sourceID == nil || $0.sourceID == sourceID }
            let kinds = ["selectedValue", "amplitudeEnvelope", "pitchEnvelope", "filterEnvelope"]
            let colors: [Color] = [.mint, .cyan, .orange, .purple]
            for (index, kind) in kinds.enumerated() {
                let channels = traces.flatMap(\.channels).filter { $0.kindName == kind }
                let low = channels.lazy.flatMap(\.points).map(\.value).min() ?? 0
                let high = channels.lazy.flatMap(\.points).map(\.value).max() ?? 1
                let span = max(1e-9, high - low)
                var path = Path()
                for channel in channels {
                    for pair in zip(channel.points, channel.points.dropFirst()) {
                        let cycle = floor(pair.0.beat / value.beatCount)
                        let start = pair.0.beat - cycle * value.beatCount
                        let end = min(value.beatCount, pair.1.beat - cycle * value.beatCount)
                        let y1 = high == low ? area.midY : area.maxY - (pair.0.value - low) / span * area.height
                        let y2 = high == low ? area.midY : area.maxY - (pair.1.value - low) / span * area.height
                        path.move(to: .init(x: area.minX + start / value.beatCount * area.width, y: y1))
                        path.addLine(to: .init(x: area.minX + end / value.beatCount * area.width, y: y2))
                    }
                }
                context.stroke(path, with: .color(colors[index].opacity(0.8)), lineWidth: 1.2)
            }
        }.accessibilityLabel("\(value.traces.count) voices; selected value mint, amplitude cyan, pitch orange, filter purple; channels individually scaled")
    }
}
