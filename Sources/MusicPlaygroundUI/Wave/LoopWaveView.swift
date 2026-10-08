import SwiftUI

public struct LoopWaveView: View {
    private let peaks: [Float]
    private let position: Double
    private let color: Color

    public init(peaks: [Float], position: Double, color: Color) {
        self.peaks = peaks; self.position = position; self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width >= 1, size.height > 0 else { return }
            var wave = Path()
            let columns = max(1, min(2048, Int(size.width)))
            for column in 0..<columns {
                let x = CGFloat(column) * size.width / CGFloat(columns)
                let peak = Self.peak(peaks, at: position + Double(x / size.width) - 0.5)
                let height = min(1, CGFloat(peak) * 2) * size.height * 0.5
                wave.move(to: CGPoint(x: x, y: size.height / 2 - height))
                wave.addLine(to: CGPoint(x: x, y: size.height / 2 + height))
            }
            context.stroke(wave, with: .linearGradient(Gradient(colors: [color.opacity(0.5), color, color.opacity(0.5)]),
                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)), lineWidth: 1)
            context.fill(Path(CGRect(x: size.width / 2, y: 0, width: 1, height: size.height)), with: .color(.white))
        }
        .accessibilityLabel("Prepared loop waveform")
        .accessibilityValue(peaks.isEmpty ? "No prepared audio" : "\(peaks.count) PCM peak bins")
        .accessibilityIdentifier("loop-waveform")
    }

    public static func peak(_ peaks: [Float], at phase: Double) -> Float {
        guard !peaks.isEmpty, phase.isFinite else { return 0 }
        let offset = (phase - floor(phase)) * Double(peaks.count)
        let index = min(peaks.count - 1, Int(offset))
        let fraction = Float(offset - Double(index))
        return peaks[index] + (peaks[(index + 1) % peaks.count] - peaks[index]) * fraction
    }
}
