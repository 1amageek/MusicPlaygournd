import AppKit
import IOKit.hidsystem

/// Recognizes command taps and independent Option press/release lifetimes.
@MainActor
final class PlayModeKeys {
    enum Action: Equatable { case all, deck(Int), cueDown(Int, Bool), cueUp(Int), cancelCue }
    private var pending: UInt16?
    private var heldOptions: Set<UInt16> = []
    func reset() { pending = nil; heldOptions.removeAll() }

    func handle(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags, repeating: Bool = false) -> Action? {
        if type == .keyDown {
            pending = nil
            if !heldOptions.isEmpty { heldOptions.removeAll(); return .cancelCue }
            if keyCode == 49 && !repeating && flags.intersection([.command, .option, .control, .shift]).isEmpty { return .all }
            return nil
        }
        guard type == .flagsChanged else { return nil }
        if keyCode == 58 || keyCode == 61 {
            pending = nil
            let mask = UInt(keyCode == 58 ? NX_DEVICELALTKEYMASK : NX_DEVICERALTKEYMASK)
            let index = keyCode == 58 ? 0 : 1
            if flags.rawValue & mask != 0 {
                guard flags.intersection([.command, .control]).isEmpty,
                      heldOptions.insert(keyCode).inserted else { return nil }
                return .cueDown(index, flags.contains(.shift))
            }
            return heldOptions.remove(keyCode) != nil ? .cueUp(index) : nil
        }
        if !heldOptions.isEmpty {
            heldOptions.removeAll()
            pending = nil
            return .cancelCue
        }
        let mask: UInt
        let index: Int
        switch keyCode {
        case 55: mask = UInt(NX_DEVICELCMDKEYMASK); index = 0
        case 54: mask = UInt(NX_DEVICERCMDKEYMASK); index = 1
        default: pending = nil; return nil
        }
        let sideMasks = UInt(NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK | NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK)
        if flags.rawValue & mask != 0 {
            pending = flags.rawValue & sideMasks == mask && flags.intersection([.control, .shift]).isEmpty ? keyCode : nil
            return nil
        }
        let accepted = pending == keyCode
        pending = nil
        return accepted ? .deck(index) : nil
    }
}
