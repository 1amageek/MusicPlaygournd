import SwiftMusic

enum Beat { case steady, fill }
enum Section { case intro, groove }

struct Session: Music {
    @State private var beat: Beat = .steady
    @State private var section: Section = .groove

    var body: some Sound {
        Track("Drums") {
            switch beat {
            case .steady:
                Sample("kick").rhythm("x ~ x ~").gain(0.7)
            case .fill:
                Sample("kick").rhythm("x x [x x] x").gain(0.7)
            }
        }

        switch section {
        case .intro:
            Track("Pad") {
                Synthesizer(.sine).notes("C3 ~ G3 ~").gain(0.15)
            }
        case .groove:
            Track("Bass") {
                Synthesizer(.saw).notes("C2 ~ [Eb2 G2] G2").gain(0.15)
            }
            Track("Hi-hat") {
                Sample("closedHat").rhythm("x*8").gain(0.2)
            }
        }
    }
}
