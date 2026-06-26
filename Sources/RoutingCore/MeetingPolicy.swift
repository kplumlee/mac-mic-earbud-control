import Foundation

public enum MeetingPolicy {
    public static func isMeetingActive(
        runningBundleIDs: Set<String>,
        meetingApps: [String],
        micInUse: Bool
    ) -> Bool {
        micInUse && !Set(meetingApps).isDisjoint(with: runningBundleIDs)
    }
}
