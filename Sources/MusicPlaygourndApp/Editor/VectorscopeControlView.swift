import SwiftUI

/// A stereo balance and reverb surface over the unmodified Mid/Side trace.
struct VectorscopeControlView: View {
  let samples: [Float]
  let balance: Float
  let space: Double
  let onBalanceChange: (Float) -> Void
  let onSpaceChange: (Double) -> Void

  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { geometry in
        let width = max(1, geometry.size.width - 32)
        let height = max(1, geometry.size.height - 32)
        ZStack {
          VectorscopeView(samples: samples).allowsHitTesting(false)
          Circle().fill(.cyan.opacity(0.3)).frame(width: 24, height: 24).blur(radius: 5)
            .position(x: 16 + Double(balance + 1) / 2 * width, y: 16 + (1 - space) * height)
            .allowsHitTesting(false)
          Circle().fill(.cyan).frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 1))
            .position(x: 16 + Double(balance + 1) / 2 * width, y: 16 + (1 - space) * height)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0).onChanged { event in
            onBalanceChange(Float(min(1, max(0, (event.location.x - 16) / width)) * 2 - 1))
            onSpaceChange(min(1, max(0, 1 - (event.location.y - 16) / height)))
          }
        )
        .accessibilityRepresentation {
          VStack {
            Slider(
              value: Binding(get: { Double(balance) }, set: { onBalanceChange(Float($0)) }),
              in: -1...1
            )
            .accessibilityLabel("Master balance")
            Slider(value: Binding(get: { space }, set: onSpaceChange), in: 0...1)
              .accessibilityLabel("Master reverb distance")
          }
        }
      }
      HStack {
        Text(String(format: "L/R %+.0f%%   SPACE %.0f%%", balance * 100, space * 100))
          .foregroundStyle(.secondary)
        Spacer()
        Button("Reset") {
          onBalanceChange(0)
          onSpaceChange(0.5)
        }
        .buttonStyle(.plain).accessibilityLabel("Reset balance and distance to center")
      }.font(.system(size: 10, design: .monospaced)).padding(12)
        .help(
          "Drag left/right for stereo balance, up/down for reverb distance. Reset centers balance and sets reverb to 50%."
        )
    }
  }
}
