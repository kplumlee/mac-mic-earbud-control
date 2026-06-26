import Foundation

public struct DeviceProfile: Codable, Equatable {
    public var managed: Bool
    public var micPriority: [String]

    public init(managed: Bool, micPriority: [String]) {
        self.managed = managed
        self.micPriority = micPriority
    }
}
