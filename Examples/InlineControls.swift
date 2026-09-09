import SwiftMusic
import MusicPlayground

struct Session: Music {
    @State private var level = 0.2

    var body: some Sound {
        Track("Acid") {
            Synthesizer(.bandLimitedSaw)
                .notes("C2 C3 Eb2 G2 Bb2 G2 Eb3 G2")
                .lowPass("200", resonanceQ: 4)
                .acidEnvelope(slider(0.5, in: 0...1))
                .gain(slider($level, in: 0...0.5))
        }
    }
}
