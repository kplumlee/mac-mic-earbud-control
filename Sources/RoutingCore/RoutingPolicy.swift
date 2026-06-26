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
        profiles: [String: DeviceProfile],
        paused: Bool,
        frontmostBundleID: String?,
        callAppsOnly: Bool,
        callApps: [String]
    ) -> RoutingDecision {
        // (1) paused → leave alone
        if paused { return .leaveAlone }

        // (2) per-app gate
        if callAppsOnly {
            guard let bundleID = frontmostBundleID, callApps.contains(bundleID) else {
                return .leaveAlone
            }
        }

        // (3) guard: Bluetooth, not AirPods, managed
        guard let output = activeOutput,
              output.transport == .bluetooth,
              !isAirPods(output.name),
              profiles[output.name]?.managed == true
        else { return .leaveAlone }

        // (4) pick mic by priority
        let micPriority = profiles[output.name]!.micPriority
        let priority = micPriority.isEmpty ? Settings.defaultPriority : micPriority
        for name in priority {
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
