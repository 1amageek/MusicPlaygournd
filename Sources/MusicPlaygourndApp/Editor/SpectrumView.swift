import SwiftUI

struct SpectrumView: View {
    let bands: [Float]
    let isPlaying: Bool
    var tint: Color? = nil

    var body: some View {
        Canvas { context, size in
            let plotHeight = size.height
            for db in [-18, -48, -78] {
                let y = Double(-db) / 90 * plotHeight
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.white.opacity(0.055)))
            }
            let width = size.width / Double(max(1, bands.count))
            for (index, db) in bands.enumerated() {
                let height = max(0, Double(db + 90) / 90 * plotHeight)
                let rect = CGRect(x: Double(index) * width, y: plotHeight - height, width: max(1, width - 2), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .linearGradient(
                    Gradient(colors: [(tint ?? .cyan).opacity(0.25), tint ?? .mint]), startPoint: CGPoint(x: 0, y: plotHeight), endPoint: .zero))
            }

        }
        .accessibilityLabel("Master output spectrum, 20 hertz to 20 kilohertz, \(isPlaying ? "playing" : "paused")")
    }
}
