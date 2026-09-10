import AppKit
import IOKit.hidsystem

/// Recognizes standalone left/right modifier taps without firing on shortcuts.
@MainActor
final class PlayModeKeys {
    enum Action: Equatable { case all, deck(Int), cue(Int) }
    private var pending: UInt16?

    func reset() { pending = nil }

    func handle(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags, repeating: Bool = false) -> Action? {
        if type == .keyDown {
            pending = nil
            if keyCode == 49 && !repeating && flags.intersection([.command, .option, .control, .shift]).isEmpty { return .all }
            return nil
        }
        guard type == .flagsChanged else { return nil }
        let mask: UInt
        let action: Action
        switch keyCode {
        case 55: mask = UInt(NX_DEVICELCMDKEYMASK); action = .deck(0)
        case 54: mask = UInt(NX_DEVICERCMDKEYMASK); action = .deck(1)
        case 58: mask = UInt(NX_DEVICELALTKEYMASK); action = .cue(0)
        case 61: mask = UInt(NX_DEVICERALTKEYMASK); action = .cue(1)
        default: pending = nil; return nil
        }
        let sideMasks = UInt(NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK | NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK)
        if flags.rawValue & mask != 0 {
            pending = flags.rawValue & sideMasks == mask && flags.intersection([.control, .shift]).isEmpty ? keyCode : nil
            return nil
        }
        let accepted = pending == keyCode
        pending = nil
        return accepted ? action : nil
    }
}
