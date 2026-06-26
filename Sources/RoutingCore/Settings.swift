import Foundation

public final class Settings {
    private let defaults: UserDefaults

    private enum Key {
        static let profiles = "profiles"
        static let callAppsOnly = "callAppsOnly"
        static let callApps = "callApps"
        static let paused = "paused"
        static let meetingAutomationEnabled = "meetingAutomationEnabled"
        static let launchAppsOnMeeting = "launchAppsOnMeeting"
        static let pauseMusicOnMeeting = "pauseMusicOnMeeting"
    }

    public static let defaultPriority = [
        "Lumina Camera - Raw",
        "PlumDog Microphone",
        "EarPods Microphone",
    ]

    public static let defaultCallApps = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.apple.FaceTime",
        "com.google.Chrome",
        "com.cisco.webexmeetingsapp",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var profiles: [String: DeviceProfile] {
        get {
            guard let data = defaults.data(forKey: Key.profiles) else { return [:] }
            return (try? JSONDecoder().decode([String: DeviceProfile].self, from: data)) ?? [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.profiles)
            }
        }
    }

    public func profile(for name: String) -> DeviceProfile {
        profiles[name] ?? DeviceProfile(managed: false, micPriority: Settings.defaultPriority)
    }

    public func setProfile(_ profile: DeviceProfile, for name: String) {
        var current = profiles
        current[name] = profile
        profiles = current
    }

    public var callAppsOnly: Bool {
        get { defaults.bool(forKey: Key.callAppsOnly) }
        set { defaults.set(newValue, forKey: Key.callAppsOnly) }
    }

    public var callApps: [String] {
        get { defaults.stringArray(forKey: Key.callApps) ?? Settings.defaultCallApps }
        set { defaults.set(newValue, forKey: Key.callApps) }
    }

    public var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }

    public var meetingAutomationEnabled: Bool {
        get { defaults.object(forKey: Key.meetingAutomationEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.meetingAutomationEnabled) }
    }

    public var launchAppsOnMeeting: [String] {
        get { defaults.stringArray(forKey: Key.launchAppsOnMeeting) ?? ["Granola"] }
        set { defaults.set(newValue, forKey: Key.launchAppsOnMeeting) }
    }

    public var pauseMusicOnMeeting: Bool {
        get { defaults.object(forKey: Key.pauseMusicOnMeeting) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.pauseMusicOnMeeting) }
    }
}
