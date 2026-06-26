import Foundation

public typealias DeviceID = UInt32

public enum DeviceTransport: Equatable {
    case bluetooth
    case other
}

public struct AudioDeviceInfo: Equatable {
    public let id: DeviceID
    public let name: String
    public let transport: DeviceTransport
    public let hasOutput: Bool
    public let hasInput: Bool

    public init(id: DeviceID, name: String, transport: DeviceTransport,
                hasOutput: Bool, hasInput: Bool) {
        self.id = id
        self.name = name
        self.transport = transport
        self.hasOutput = hasOutput
        self.hasInput = hasInput
    }
}

public func isAirPods(_ name: String) -> Bool {
    name.range(of: "airpods", options: .caseInsensitive) != nil
}
