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
    public let sampleRate: Double
    public let inputChannels: Int

    public init(id: DeviceID, name: String, transport: DeviceTransport,
                hasOutput: Bool, hasInput: Bool,
                sampleRate: Double = 0, inputChannels: Int = 0) {
        self.id = id
        self.name = name
        self.transport = transport
        self.hasOutput = hasOutput
        self.hasInput = hasInput
        self.sampleRate = sampleRate
        self.inputChannels = inputChannels
    }
}

public func isAirPods(_ name: String) -> Bool {
    name.range(of: "airpods", options: .caseInsensitive) != nil
}
