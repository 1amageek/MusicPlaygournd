import SwiftMusic

public extension Sound {
    /// Applies a per-note exponential filter sweep. Amount 1 spans six octaves.
    func acidEnvelope(_ amount: Double, decay: Duration = .milliseconds(180),
                      fileID: String = #fileID, line: Int = #line, column: Int = #column) -> ModifiedSound {
        filterEnvelope(attack: .milliseconds(1), decay: decay, sustainLevel: 0,
                       release: .milliseconds(40), depth: amount * 72,
                       decayCurve: .exponential(exponent: 3),
                       fileID: fileID, line: line, column: column)
    }
}
