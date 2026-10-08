import SwiftUI

public struct FilterSpacePad: View {
    let x: Double
    let y: Double
    let bipolar: Bool
    let tint: Color
    let name: String
    let onFilterChange: (Double) -> Void
    let onSpaceChange: (Double) -> Void
    public init(x: Double, y: Double, bipolar: Bool = true, tint: Color, name: String,
                onFilterChange: @escaping (Double) -> Void, onSpaceChange: @escaping (Double) -> Void) {
        self.x = x; self.y = y; self.bipolar = bipolar; self.tint = tint; self.name = name
        self.onFilterChange = onFilterChange; self.onSpaceChange = onSpaceChange
    }
    private func reset() { onFilterChange(bipolar ? 0.5 : 1); onSpaceChange(0) }
    public var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.025))
                    Path { path in
                        for index in 1..<8 {
                            let fraction = Double(index) / 8
                            path.move(to: CGPoint(x: geometry.size.width * fraction, y: 0))
                            path.addLine(to: CGPoint(x: geometry.size.width * fraction, y: geometry.size.height))
                        }
                        for fraction in [0.25, 0.5, 0.75] {
                            path.move(to: CGPoint(x: 0, y: geometry.size.height * fraction))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * fraction))
                        }
                    }.stroke(.white.opacity(0.05), lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: x * geometry.size.width, y: 0))
                        path.addLine(to: CGPoint(x: x * geometry.size.width, y: geometry.size.height))
                        path.move(to: CGPoint(x: 0, y: (1 - y) * geometry.size.height))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: (1 - y) * geometry.size.height))
                    }.stroke(tint.opacity(0.35), lineWidth: 0.5)
                    Circle().fill(tint).frame(width: 7, height: 7)
                        .position(x: x * geometry.size.width, y: (1 - y) * geometry.size.height)
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.12)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    onFilterChange(min(1, max(0, event.location.x / max(1, geometry.size.width))))
                    onSpaceChange(min(1, max(0, 1 - event.location.y / max(1, geometry.size.height))))
                })
                .onTapGesture(count: 2) { reset() }
                .contextMenu { Button("Reset Filter and Space", action: reset) }
                .accessibilityRepresentation {
                    VStack {
                        Slider(value: Binding(get: { x }, set: { onFilterChange($0) }), in: 0...1).accessibilityLabel("\(name) filter")
                        Slider(value: Binding(get: { y }, set: { onSpaceChange($0) }), in: 0...1).accessibilityLabel("\(name) space")
                    }
                }
                .accessibilityIdentifier("\(name)-xy-pad")
                .help(bipolar ? "X: low-pass / bypass / high-pass. Y: reverb 0–100%. Double-click to reset." : "X: low-pass 20 Hz–20 kHz. Y: reverb 0–100%. Double-click to reset.")
            }
            HStack {
                Text("FILTER →").fixedSize()
                Spacer()
                Text("SPACE ↑").fixedSize()
                Button(action: reset) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain).contentShape(Rectangle()).accessibilityLabel("Reset \(name) filter and space")
            }.font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
