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
        runningBundleIDs: Set<String>,
        callAppsOnly: Bool,
        callApps: [String]
    ) -> RoutingDecision {
        // (1) paused → leave alone
        if paused { return .leaveAlone }

        // (2) per-app gate
        if callAppsOnly && Set(callApps).isDisjoint(with: runningBundleIDs) {
            return .leaveAlone
        }

        // (3) guard: Bluetooth, not AirPods, managed
        guard let output = activeOutput,
              output.transport == .bluetooth,
              !isAirPods(output.name),
              let profile = profiles[output.name], profile.managed
        else { return .leaveAlone }

        // (4) pick mic by priority list first, then auto-pick
        let priority = profile.micPriority
        for name in priority {
            if let match = devices.first(where: { $0.name == name && $0.hasInput }) {
                return .setInput(match.id)
            }
        }
        // Auto-pick: best non-Bluetooth input, excluding the active output device
        if let auto = bestAutoMic(devices: devices, excludingOutput: output.name) {
            return .setInput(auto.id)
        }
        return .leaveAlone
    }

    /// Returns the best non-Bluetooth, non-AirPods input device, excluding the device named
    /// `outputName`. Ranks by highest sample rate, then highest input channel count, then
    /// name ascending. Returns nil if no eligible candidate exists.
    public static func bestAutoMic(devices: [AudioDeviceInfo],
                                   excludingOutput outputName: String) -> AudioDeviceInfo? {
        let candidates = devices.filter {
            $0.hasInput &&
            $0.transport != .bluetooth &&
            !isAirPods($0.name) &&
            $0.name != outputName
        }
        return candidates.sorted { a, b in
            if a.sampleRate != b.sampleRate { return a.sampleRate > b.sampleRate }
            if a.inputChannels != b.inputChannels { return a.inputChannels > b.inputChannels }
            return a.name < b.name
        }.first
    }

    /// Bluetooth output devices eligible to be managed (AirPods excluded).
    public static func managedCandidates(devices: [AudioDeviceInfo]) -> [AudioDeviceInfo] {
        devices.filter { $0.transport == .bluetooth && $0.hasOutput && !isAirPods($0.name) }
    }
}
