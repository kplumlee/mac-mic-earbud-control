import XCTest
@testable import RoutingCore

final class MeetingPolicyTests: XCTestCase {
    func testReturnsFalseWhenMicNotInUse() {
        // Even when a meeting app is running, no meeting without mic
        let result = MeetingPolicy.isMeetingActive(
            runningBundleIDs: ["us.zoom.xos"],
            meetingApps: ["us.zoom.xos"],
            micInUse: false
        )
        XCTAssertFalse(result)
    }

    func testReturnsFalseWhenMicInUseButNoMeetingApp() {
        // Mic in use but none of the running apps is a meeting app
        let result = MeetingPolicy.isMeetingActive(
            runningBundleIDs: ["com.apple.safari", "com.apple.finder"],
            meetingApps: ["us.zoom.xos", "com.microsoft.teams2"],
            micInUse: true
        )
        XCTAssertFalse(result)
    }

    func testReturnsTrueWhenMicInUseAndMeetingAppRunning() {
        // Mic in use AND one of the meeting apps is running
        let result = MeetingPolicy.isMeetingActive(
            runningBundleIDs: ["com.apple.safari", "us.zoom.xos"],
            meetingApps: ["us.zoom.xos", "com.microsoft.teams2"],
            micInUse: true
        )
        XCTAssertTrue(result)
    }
}
