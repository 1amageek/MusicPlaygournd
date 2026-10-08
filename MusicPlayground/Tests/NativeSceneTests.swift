import UIKit
import XCTest
@testable import MusicPlayground

@MainActor
final class NativeSceneTests: XCTestCase {
    func testProductionSceneAdmitsOnlyLandscapeCompatibility() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while UIApplication.shared.connectedScenes.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(UIApplication.shared.connectedScenes.isEmpty)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIRequiresFullScreen") as? Bool, true)
        XCTAssertEqual(Set(Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations~ipad") as? [String] ?? []),
                       Set(["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]))
    }
}
