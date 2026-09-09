import SwiftMusic

struct Session: Music {
    var body: some Sound {
        Track("Kick") {
            Sample("kick")
                .rhythm("x ~ x ~")
                .gain("0.8 0.6")
        }

        Track("Hi-hat") {
            Sample("closedHat")
                .rhythm("x [x x] x [x x]")
                .gain("0.5 [0.2 0.4] 0.5 [0.2 0.3]")
                .pan(0.2)
        }

        Track("Bass") {
            Synthesizer(.sine)
                .notes("C2 ~ [Eb2 G2] G2")
                .gain(0.4)
        }
    }
}