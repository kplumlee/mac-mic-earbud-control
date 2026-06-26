import XCTest
@testable import RoutingCore

final class SettingsTests: XCTestCase {
    private func freshSettings() -> Settings {
        let suite = "test.btmicrouter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return Settings(defaults: defaults)
    }

    func testDefaultsWhenUnset() {
        let s = freshSettings()
        XCTAssertEqual(s.managedNames, [])
        XCTAssertEqual(s.micPriority, Settings.defaultPriority)
        XCTAssertFalse(s.paused)
    }

    func testRoundTripsManagedNames() {
        let s = freshSettings()
        s.managedNames = ["HUAWEI FreeClip 2", "BoomAudio"]
        XCTAssertEqual(s.managedNames, ["HUAWEI FreeClip 2", "BoomAudio"])
    }

    func testRoundTripsPriorityAndPaused() {
        let s = freshSettings()
        s.micPriority = ["PlumDog Microphone", "Lumina Camera - Raw"]
        s.paused = true
        XCTAssertEqual(s.micPriority, ["PlumDog Microphone", "Lumina Camera - Raw"])
        XCTAssertTrue(s.paused)
    }
}
