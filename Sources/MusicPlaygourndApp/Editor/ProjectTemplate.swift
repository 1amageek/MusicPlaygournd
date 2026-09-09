import Foundation

enum ProjectTemplate: String, CaseIterable, Identifiable {
    case deepCurrent, basicBeat

    var id: Self { self }
    var title: String { self == .deepCurrent ? "Deep Current" : "Basic Beat" }
    var symbol: String { self == .deepCurrent ? "waveform" : "metronome" }
    var detail: String {
        self == .deepCurrent
            ? "Acid bass, drums and atmosphere. Inspired by Switch Angel."
            : "A single kick track. Start small and build your own session."
    }

    @MainActor var source: String {
        switch self {
        case .deepCurrent: SessionModel.initialSource
        case .basicBeat:
            """
            import SwiftMusic

            struct Session: Music {
                var body: some Sound {
                    Track("Kick") {
                        Sample("kick")
                            .rhythm("x*4")
                            .gain(0.8)
                    }
                }
            }

            """
        }
    }
}
