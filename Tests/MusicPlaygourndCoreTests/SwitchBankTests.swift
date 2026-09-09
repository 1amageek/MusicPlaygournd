import Foundation
import Testing
@testable import MusicPlaygourndCore

extension NativeHostTests {
    struct SwitchBankTests {
        @Test(.timeLimit(.minutes(6)))
        func retainedWorkerSelectsPreparedSwiftSwitchVariant() async throws {
            let package = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let workspace = FileManager.default.temporaryDirectory
                .appending(path: "SwiftMusic-switch-runtime-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            let runtimeSDK = package.appending(path: ".build/MusicPlaygournd.app/Contents/Resources/RuntimeSDK")
            guard FileManager.default.fileExists(atPath: runtimeSDK.appending(path: "environment.json").path) else {
                Issue.record("The prepared RuntimeSDK is required for the switch worker integration test.")
                return
            }
            let evaluator = SourceEvaluator(
                packageURL: package,
                workspace: workspace,
                swiftExecutable: "/usr/bin/swift",
                runtimeSDK: runtimeSDK
            )
            let source = """
            enum Beat { case steady, fill }
            enum Section { case intro, groove }

            struct Session: Music {
                @SwiftMusic.State private var beat: Beat = .steady
                @SwiftMusic.State private var section: Section = .groove

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
            """
            do {
                let revision: UInt64 = 70_701
                let retained = try await evaluator.evaluateRetained(
                    source: source, bpm: 120, beatsPerBar: 4, revision: revision
                )
                let bank = try #require(retained.switchBank)
                #expect(bank.controls.map(\.propertyName) == ["beat", "section"])
                #expect(bank.variants.count == 4)
                #expect(Set(bank.variants.map(\.selection)).count == 4)
                #expect(await evaluator.adopt(revision: revision))

                let selectedIndex = try #require(bank.variants.firstIndex { $0.selection == [1, 1] })
                let awayIndex = try #require(bank.variants.firstIndex { $0.selection == [0, 0] })
                #expect(try await evaluator.selectSwitchVariant(
                    index: selectedIndex, revision: revision, generation: 11
                ))
                let selected = try await evaluator.render(
                    overrides: [], revision: revision, generation: 12
                )
                #expect(selected == bank.variants[selectedIndex].loop)
                #expect(selected != bank.variants[bank.initialIndex].loop)
                let muteAddress = try #require(bank.variants[selectedIndex].catalog.descriptors.first {
                    $0.address.target == .track(0) && $0.address.parameter == .trackMute
                }?.address)
                let mute = LiveControlOverride(address: muteAddress, value: .number(1))
                let muted = try await evaluator.render(
                    overrides: [mute], revision: revision, generation: 13
                )
                #expect(muted != selected)
                #expect(try await evaluator.selectSwitchVariant(
                    index: awayIndex, revision: revision, generation: 14
                ))
                let away = try await evaluator.render(
                    overrides: [], revision: revision, generation: 15
                )
                #expect(away == bank.variants[awayIndex].loop)
                #expect(try await evaluator.selectSwitchVariant(
                    index: selectedIndex, revision: revision, generation: 16
                ))
                let selectedAgain = try await evaluator.render(
                    overrides: [mute], revision: revision, generation: 17
                )
                #expect(selectedAgain == muted)
                try await evaluator.shutdown()
            } catch {
                do { try await evaluator.shutdown() }
                catch { Issue.record(error) }
                if FileManager.default.fileExists(atPath: workspace.path) {
                    do { try FileManager.default.removeItem(at: workspace) }
                    catch { Issue.record(error) }
                }
                throw error
            }
        }
    }
}
