import Foundation

public final class Settings {
    private let defaults: UserDefaults

    private enum Key {
        static let managed = "managedDeviceNames"
        static let priority = "micPriority"
        static let paused = "paused"
    }

    public static let defaultPriority = [
        "Lumina Camera - Raw",
        "PlumDog Microphone",
        "EarPods Microphone",
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var managedNames: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.managed) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.managed) }
    }

    public var micPriority: [String] {
        get { defaults.stringArray(forKey: Key.priority) ?? Settings.defaultPriority }
        set { defaults.set(newValue, forKey: Key.priority) }
    }

    public var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }
}
