import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: SessionModel?
    private var discardConfirmed = false
    private var playbackKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.windows.first?.delegate = self
        playbackKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, let model = self.model,
                      model.hasOpenDocument || model.isPlaying,
                      Self.handlesPlaybackSpace(event) else { return false }
                if !event.isARepeat { model.togglePlayback() }
                return true
            }
            return consumed ? nil : event
        }
    }

    static func handlesPlaybackSpace(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              let window = event.window, window.sheetParent == nil,
              !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField) else { return false }
        var owner = window
        while let parent = owner.parent { owner = parent }
        return owner.identifier?.rawValue == "editor" && owner.attachedSheet == nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let playbackKeyMonitor { NSEvent.removeMonitor(playbackKeyMonitor) }
        playbackKeyMonitor = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model?.confirmAllDocuments() != false else { return false }
        discardConfirmed = true
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard discardConfirmed || model?.confirmAllDocuments() != false else { return .terminateCancel }
        Task {
            do { try await model?.shutdown() }
            catch { NSLog("MusicPlaygournd scratch cleanup failed: %@", error.localizedDescription) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
