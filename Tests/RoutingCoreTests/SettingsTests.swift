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
        XCTAssertEqual(s.profiles, [:])
        XCTAssertFalse(s.callAppsOnly)
        XCTAssertEqual(s.callApps, [
            "us.zoom.xos",
            "com.microsoft.teams2",
            "com.microsoft.teams",
            "com.apple.FaceTime",
            "com.google.Chrome",
            "com.cisco.webexmeetingsapp",
            "com.hnc.Discord",
            "com.tinyspeck.slackmacgap",
        ])
        XCTAssertFalse(s.paused)
    }

    func testProfileForReturnsDefaultForUnknownDevice() {
        // Since task-23, defaultPriority is [] — unknown devices get an unmanaged
        // profile with an empty micPriority, triggering universal auto-pick in decide().
        let s = freshSettings()
        let p = s.profile(for: "SomeUnknownHeadset")
        XCTAssertEqual(p, DeviceProfile(managed: false, micPriority: []))
        XCTAssertEqual(Settings.defaultPriority, [])
    }

    func testSetProfileAndProfileFor() {
        let s = freshSettings()
        let profile = DeviceProfile(managed: true, micPriority: ["PlumDog Microphone"])
        s.setProfile(profile, for: "HUAWEI FreeClip 2")
        XCTAssertEqual(s.profile(for: "HUAWEI FreeClip 2"), profile)
    }

    func testProfilesJSONRoundTrip() {
        let s = freshSettings()
        let profile1 = DeviceProfile(managed: true, micPriority: ["Lumina Camera - Raw"])
        let profile2 = DeviceProfile(managed: false, micPriority: ["PlumDog Microphone", "EarPods Microphone"])
        s.setProfile(profile1, for: "HeadsetA")
        s.setProfile(profile2, for: "HeadsetB")

        XCTAssertEqual(s.profiles["HeadsetA"], profile1)
        XCTAssertEqual(s.profiles["HeadsetB"], profile2)
        XCTAssertEqual(s.profiles.count, 2)
    }

    func testCallAppsOnlyRoundTrip() {
        let s = freshSettings()
        XCTAssertFalse(s.callAppsOnly)
        s.callAppsOnly = true
        XCTAssertTrue(s.callAppsOnly)
    }

    func testCallAppsRoundTrip() {
        let s = freshSettings()
        let custom = ["com.custom.app1", "com.custom.app2"]
        s.callApps = custom
        XCTAssertEqual(s.callApps, custom)
    }

    func testPausedRoundTrip() {
        let s = freshSettings()
        s.paused = true
        XCTAssertTrue(s.paused)
    }

    // MARK: - Meeting automation settings

    func testMeetingAutomationDefaultsWhenUnset() {
        let s = freshSettings()
        XCTAssertTrue(s.meetingAutomationEnabled)
        XCTAssertEqual(s.launchAppsOnMeeting, ["Granola"])
        XCTAssertTrue(s.pauseMusicOnMeeting)
    }

    func testMeetingAutomationEnabledRoundTrip() {
        let s = freshSettings()
        XCTAssertTrue(s.meetingAutomationEnabled)
        s.meetingAutomationEnabled = false
        XCTAssertFalse(s.meetingAutomationEnabled)
        s.meetingAutomationEnabled = true
        XCTAssertTrue(s.meetingAutomationEnabled)
    }

    func testLaunchAppsOnMeetingRoundTrip() {
        let s = freshSettings()
        let custom = ["com.custom.noteapp", "com.custom.other"]
        s.launchAppsOnMeeting = custom
        XCTAssertEqual(s.launchAppsOnMeeting, custom)
    }

    func testPauseMusicOnMeetingRoundTrip() {
        let s = freshSettings()
        XCTAssertTrue(s.pauseMusicOnMeeting)
        s.pauseMusicOnMeeting = false
        XCTAssertFalse(s.pauseMusicOnMeeting)
        s.pauseMusicOnMeeting = true
        XCTAssertTrue(s.pauseMusicOnMeeting)
    }

    // MARK: - Record reminder setting

    func testRecordReminderEnabledDefaultWhenUnset() {
        let s = freshSettings()
        XCTAssertTrue(s.recordReminderEnabled)
    }

    func testRecordReminderEnabledRoundTrip() {
        let s = freshSettings()
        XCTAssertTrue(s.recordReminderEnabled)
        s.recordReminderEnabled = false
        XCTAssertFalse(s.recordReminderEnabled)
        s.recordReminderEnabled = true
        XCTAssertTrue(s.recordReminderEnabled)
    }
}
