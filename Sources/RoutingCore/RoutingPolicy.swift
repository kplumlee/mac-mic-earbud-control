import Foundation

public enum RoutingDecision: Equatable {
    case leaveAlone
    case setInput(DeviceID)
}

public enum RoutingPolicy {
    /// Decide which input device should be active given the current audio state.
    public static func decide(
        activeOutput: AudioDeviceInfo?,
        devices: [AudioDeviceInfo],
        managedNames: Set<String>,
        micPriority: [String],
        paused: Bool
    ) -> RoutingDecision {
        if paused { return .leaveAlone }
        guard let output = activeOutput,
              output.transport == .bluetooth,
              !isAirPods(output.name),
              managedNames.contains(output.name)
        else { return .leaveAlone }

        for name in micPriority {
            if let match = devices.first(where: { $0.name == name && $0.hasInput }) {
                return .setInput(match.id)
            }
        }
        return .leaveAlone
    }

    /// Bluetooth output devices eligible to be managed (AirPods excluded).
    public static func managedCandidates(devices: [AudioDeviceInfo]) -> [AudioDeviceInfo] {
        devices.filter { $0.transport == .bluetooth && $0.hasOutput && !isAirPods($0.name) }
    }
}
