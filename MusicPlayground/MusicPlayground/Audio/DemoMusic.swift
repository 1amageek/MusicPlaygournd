import Foundation
import SwiftMusic

struct DemoMusic: Music {
    @SoundBuilder var body: some Sound {
        #sourceLocation(file: "Session.swift", line: 5)
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
        #sourceLocation()
    }

    static func resultLines(for loop: PreparedLoop) -> [Int: Int] {
        let lines = source.components(separatedBy: "\n")
        var result: [Int: Int] = [:]
        for row in loop.rows {
            guard let anchor = row.anchor, anchor.fileID.hasSuffix("Session.swift"), anchor.line > 0,
                  anchor.line <= lines.count, let pattern = row.patternText,
                  lines[anchor.line - 1].contains(pattern),
                  let end = (anchor.line..<lines.count).first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "}" }) else { continue }
            result[row.sourceID] = end
        }
        return result
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
