import SwiftUI
import MusicPlaygroundUI

struct DeckGainControl: View {
    @Binding var value: Double
    let color: Color
    let name: String
    var label = "GAIN"
    var resetValue = 1.0
    var valueLabel: String? = nil
    var body: some View {
        MusicPlaygroundUI.DeckGainControl(value: $value, color: color, name: name, label: label,
            resetValue: resetValue, valueLabel: valueLabel,
            gesture: AnyView(MultiFingerGestureView(onChange: { value = min(1, max(0, value + $0 * 0.01)) })))
    }
}
