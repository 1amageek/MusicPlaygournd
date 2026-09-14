import SwiftUI
import Testing
@testable import MusicPlaygourndCore
@testable import MusicPlaygourndApp

extension NativeHostTests {
    @MainActor struct DeckFXControlTests {
        @Test(.timeLimit(.minutes(1)))
        func beatSyncFreeRateResetAndPad() async throws {
            let model = SessionModel()
            #expect(model.fxSettings.mix == 0)
            model.bpm = 120
            model.setFXBeats(0.5)
            #expect(model.fxSettings.rate == 4 && model.fxBeats == 0.5)
            model.bpm = 240
            model.refresh()
            #expect(model.fxSettings.rate == 8)
            model.setFXBeats(0.25)
            #expect(model.fxSettings.rate == 16)
            model.setFXBeats(0)
            #expect(model.fxBeats == 0.25 && model.fxSettings.rate == 16)
            model.setFXBeats(nil)
            var settings = model.fxSettings
            settings.rate = 3; settings.feedback = 0.6
            model.setFX(settings)
            model.bpm = 100; model.refresh()
            #expect(model.fxSettings.rate == 3 && model.fxBeats == nil)
            let pad = DeckFXView(settings: model.fxSettings, beats: model.fxBeats,
                                onChange: model.setFX, onBeatsChange: model.setFXBeats,
                                onReset: model.resetFX, tint: .cyan, name: "A")
            pad.movePad(to: CGPoint(x: 158, y: 83), in: CGSize(width: 316, height: 166))
            #expect(model.fxSettings.mix == 0.5 && model.fxSettings.depth == 0.5)
            #expect(model.fxSettings.rate == 3 && model.fxSettings.feedback == 0.6)
            pad.movePad(to: CGPoint(x: -30, y: 220), in: CGSize(width: 316, height: 166))
            #expect(model.fxSettings.mix == 0 && model.fxSettings.depth == 0)
            pad.movePad(to: CGPoint(x: 400, y: -10), in: CGSize(width: 316, height: 166))
            #expect(model.fxSettings.mix == 1 && model.fxSettings.depth == 1)
            model.refresh()
            #expect(model.fxSettings.mix == 1 && model.fxSettings.depth == 1)
            model.resetFX()
            #expect(model.fxSettings.mix == 0 && model.fxBeats == 1)
            #expect(abs(model.fxSettings.rate - 100.0 / 60) < 0.000001)
            try await model.shutdown()
        }
    }
}
