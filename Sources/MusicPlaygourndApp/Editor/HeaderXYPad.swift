import SwiftUI
import MusicPlaygroundUI

/// Controls the global filter and reverb without editing the score.
struct HeaderXYPad: View {
    @Bindable var model: SessionModel
    var bipolar = false
    var tint: Color = .mint
    var name = "Master"

    private var cutoff: Double {
        guard let descriptor = model.controlCatalog?.descriptors.first(where: { $0.address.target == .master && $0.address.parameter == .lowPassCutoff }) else { return model.lowPass }
        return model.controlValue(descriptor) ?? 20_000
    }
    private var space: Double { model.displayedReverbMix }
    private var x: Double { bipolar ? (model.djFilter + 1) / 2 : min(1, max(0, log(cutoff / 20) / log(1_000))) }
    private var y: Double { min(1, max(0, space)) }

    private func setFilter(_ value: Double) {
        if bipolar { model.setDJFilter(value * 2 - 1) }
        else { model.lowPass = 20 * Foundation.pow(1_000, value) }
    }

    private func reset() {
        setFilter(bipolar ? 0.5 : 1)
        model.reverbMix = 0
    }

    var body: some View {
        FilterSpacePad(x: x, y: y, bipolar: bipolar, tint: tint, name: name,
            onFilterChange: setFilter, onSpaceChange: { model.reverbMix = $0 })
    }
}
