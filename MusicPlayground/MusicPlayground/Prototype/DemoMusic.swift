import SwiftMusic

struct DemoMusic: Music {
    @SoundBuilder var body: some Sound {
        Track("Melody") {
            Synthesizer(.sine).notes("C4 E4 G4 B4 G4 E4 D4 G4").gate(0.65).gain(0.22)
        }
        Track("Bass") {
            Synthesizer(.triangle).notes("C2 ~ G2 ~").gate(0.7).gain(0.16)
        }
        Track("Kick") {
            Sample("kick").rhythm("x ~ x ~").gain(0.24)
        }
        Track("Hat") {
            Sample("closedHat").rhythm("~ x ~ x").gain(0.08)
        }
    }

    static let source = """
    import SwiftMusic

    struct Session: Music {
        var body: some Sound {
            Track("Melody") {
                Synthesizer(.sine)
                    .notes("C4 E4 G4 B4 G4 E4 D4 G4")
                    .gate(0.65).gain(0.22)
            }
            Track("Bass") {
                Synthesizer(.triangle)
                    .notes("C2 ~ G2 ~")
                    .gate(0.7).gain(0.16)
            }
            Track("Kick") {
                Sample("kick").rhythm("x ~ x ~").gain(0.24)
            }
            Track("Hat") {
                Sample("closedHat").rhythm("~ x ~ x").gain(0.08)
            }
        }
    }
    """
}
