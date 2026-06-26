import XCTest
@testable import RoutingCore

final class RoutingPolicyTests: XCTestCase {
    let huawei = AudioDeviceInfo(id: 1, name: "HUAWEI FreeClip 2",
                                 transport: .bluetooth, hasOutput: true, hasInput: true)
    let airpods = AudioDeviceInfo(id: 2, name: "AirPods Pro",
                                  transport: .bluetooth, hasOutput: true, hasInput: true)
    let speakers = AudioDeviceInfo(id: 3, name: "Mac Studio Speakers",
                                   transport: .other, hasOutput: true, hasInput: false)
    let lumina = AudioDeviceInfo(id: 10, name: "Lumina Camera - Raw",
                                 transport: .other, hasOutput: false, hasInput: true)
    let plumdog = AudioDeviceInfo(id: 11, name: "PlumDog Microphone",
                                  transport: .other, hasOutput: false, hasInput: true)

    // Helper: build a profiles dict with the given names marked managed.
    // priority defaults to empty (the universal default), which enables auto-pick.
    private func profiles(managed names: [String],
                          priority: [String]? = nil) -> [String: DeviceProfile] {
        var map: [String: DeviceProfile] = [:]
        for name in names {
            map[name] = DeviceProfile(managed: true,
                                      micPriority: priority ?? Settings.defaultPriority)
        }
        return map
    }

    // MARK: - Ported existing tests
    // NOTE (task-23): defaultPriority is now []. The profiles(managed:) helper defaults to
    // that empty list, so these tests now exercise the auto-pick path rather than a named
    // priority list. The expected results are unchanged because auto-pick's alphabetical
    // tie-break picks Lumina before PlumDog, matching the old hardcoded order.

    func testManagedBluetoothOutputRoutesToLumina() {
        // Auto-pick: lumina & plumdog both sampleRate=0 channels=0; "Lumina…" < "PlumDog…" → lumina
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina, plumdog],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .setInput(10))
    }

    func testFallsBackWhenLuminaAbsent() {
        // Auto-pick: only plumdog is a non-BT input
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, plumdog],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .setInput(11))
    }

    func testLeavesAloneWhenNoNonBTInputPresent() {
        // Auto-pick finds nothing (only the BT headset itself is in devices)
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .leaveAlone)
    }

    func testUnmanagedBluetoothLeavesAlone() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina],
            profiles: [:], // empty = not managed
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .leaveAlone)
    }

    func testAirPodsLeftAloneEvenIfManaged() {
        let d = RoutingPolicy.decide(
            activeOutput: airpods, devices: [airpods, lumina],
            profiles: profiles(managed: ["AirPods Pro"]),
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .leaveAlone)
    }

    func testNonBluetoothOutputLeavesAlone() {
        let d = RoutingPolicy.decide(
            activeOutput: speakers, devices: [speakers, lumina],
            profiles: profiles(managed: ["Mac Studio Speakers"]),
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .leaveAlone)
    }

    func testPausedLeavesAlone() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: true, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .leaveAlone)
    }

    func testManagedCandidatesExcludeAirPodsAndNonBluetooth() {
        let c = RoutingPolicy.managedCandidates(devices: [huawei, airpods, speakers, lumina])
        XCTAssertEqual(c.map(\.name), ["HUAWEI FreeClip 2"])
    }

    // MARK: - Per-app gating tests

    func testCallAppsOnlyBlocksWhenNoCallAppRunning() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: [],
            callAppsOnly: true, callApps: ["us.zoom.xos"])
        XCTAssertEqual(d, .leaveAlone)
    }

    func testCallAppsOnlyBlocksWhenRunningAppsDisjointFromCallApps() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: ["com.apple.Finder"],
            callAppsOnly: true, callApps: ["us.zoom.xos"])
        XCTAssertEqual(d, .leaveAlone)
    }

    func testCallAppsOnlyAllowsWhenCallAppIsRunning() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: ["com.apple.Finder", "us.zoom.xos"],
            callAppsOnly: true, callApps: ["us.zoom.xos"])
        XCTAssertEqual(d, .setInput(10))
    }

    func testCallAppsOnlyFalseAllowsRegardlessOfRunningApps() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: [],
            callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .setInput(10))
    }

    // MARK: - Per-device profile micPriority tests

    func testPerDeviceProfileMicPriority() {
        // DeviceA prefers PlumDog first; DeviceB prefers Lumina first
        let deviceA = AudioDeviceInfo(id: 20, name: "DeviceA",
                                      transport: .bluetooth, hasOutput: true, hasInput: false)
        let deviceB = AudioDeviceInfo(id: 21, name: "DeviceB",
                                      transport: .bluetooth, hasOutput: true, hasInput: false)
        var p: [String: DeviceProfile] = [:]
        p["DeviceA"] = DeviceProfile(managed: true,
                                     micPriority: ["PlumDog Microphone", "Lumina Camera - Raw"])
        p["DeviceB"] = DeviceProfile(managed: true,
                                     micPriority: ["Lumina Camera - Raw", "PlumDog Microphone"])

        let dA = RoutingPolicy.decide(
            activeOutput: deviceA, devices: [deviceA, lumina, plumdog],
            profiles: p,
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(dA, .setInput(11)) // PlumDog wins for DeviceA

        let dB = RoutingPolicy.decide(
            activeOutput: deviceB, devices: [deviceB, lumina, plumdog],
            profiles: p,
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(dB, .setInput(10)) // Lumina wins for DeviceB
    }

    // MARK: - bestAutoMic unit tests

    func testBestAutoMicPicksHighestSampleRate() {
        let lowSR = AudioDeviceInfo(id: 20, name: "LowSR Mic", transport: .other,
                                    hasOutput: false, hasInput: true, sampleRate: 44100, inputChannels: 1)
        let highSR = AudioDeviceInfo(id: 21, name: "HighSR Mic", transport: .other,
                                     hasOutput: false, hasInput: true, sampleRate: 96000, inputChannels: 1)
        let result = RoutingPolicy.bestAutoMic(devices: [lowSR, highSR], excludingOutput: "Headset")
        XCTAssertEqual(result?.id, 21)
    }

    func testBestAutoMicExcludesBluetooth() {
        let btMic = AudioDeviceInfo(id: 30, name: "BT Mic", transport: .bluetooth,
                                    hasOutput: false, hasInput: true, sampleRate: 96000, inputChannels: 2)
        let wiredMic = AudioDeviceInfo(id: 31, name: "Wired Mic", transport: .other,
                                       hasOutput: false, hasInput: true, sampleRate: 44100, inputChannels: 1)
        let result = RoutingPolicy.bestAutoMic(devices: [btMic, wiredMic], excludingOutput: "Headset")
        XCTAssertEqual(result?.id, 31)
    }

    func testBestAutoMicExcludesAirPods() {
        let apMic = AudioDeviceInfo(id: 32, name: "AirPods Pro", transport: .bluetooth,
                                    hasOutput: true, hasInput: true, sampleRate: 48000, inputChannels: 1)
        let wiredMic = AudioDeviceInfo(id: 33, name: "Wired Mic", transport: .other,
                                       hasOutput: false, hasInput: true, sampleRate: 44100, inputChannels: 1)
        let result = RoutingPolicy.bestAutoMic(devices: [apMic, wiredMic], excludingOutput: "Headset")
        XCTAssertEqual(result?.id, 33)
    }

    func testBestAutoMicExcludesOutputName() {
        let combo = AudioDeviceInfo(id: 34, name: "USB Headset", transport: .other,
                                    hasOutput: true, hasInput: true, sampleRate: 48000, inputChannels: 1)
        let mic = AudioDeviceInfo(id: 35, name: "Built-in Mic", transport: .other,
                                  hasOutput: false, hasInput: true, sampleRate: 44100, inputChannels: 1)
        let result = RoutingPolicy.bestAutoMic(devices: [combo, mic], excludingOutput: "USB Headset")
        XCTAssertEqual(result?.id, 35)
    }

    func testBestAutoMicReturnsNilWhenOnlyBluetooth() {
        let btMic = AudioDeviceInfo(id: 40, name: "BT Mic", transport: .bluetooth,
                                    hasOutput: false, hasInput: true, sampleRate: 48000, inputChannels: 1)
        let result = RoutingPolicy.bestAutoMic(devices: [btMic], excludingOutput: "Headset")
        XCTAssertNil(result)
    }

    func testBestAutoMicTieBreakByChannelsThenNameAscending() {
        // Same sampleRate, different channels: more channels wins
        let a = AudioDeviceInfo(id: 50, name: "AAA Mic", transport: .other,
                                hasOutput: false, hasInput: true, sampleRate: 48000, inputChannels: 2)
        let b = AudioDeviceInfo(id: 51, name: "BBB Mic", transport: .other,
                                hasOutput: false, hasInput: true, sampleRate: 48000, inputChannels: 1)
        XCTAssertEqual(RoutingPolicy.bestAutoMic(devices: [a, b], excludingOutput: "X")?.id, 50)

        // Same sampleRate, same channels: name ascending (earlier alphabetically wins)
        let c = AudioDeviceInfo(id: 52, name: "AAA Mic2", transport: .other,
                                hasOutput: false, hasInput: true, sampleRate: 48000, inputChannels: 2)
        let d = AudioDeviceInfo(id: 53, name: "ZZZ Mic2", transport: .other,
                                hasOutput: false, hasInput: true, sampleRate: 48000, inputChannels: 2)
        XCTAssertEqual(RoutingPolicy.bestAutoMic(devices: [c, d], excludingOutput: "X")?.id, 52)
    }

    // MARK: - decide() universal auto-pick tests

    func testDecideWithEmptyPriorityUsesAutoMic() {
        let usb = AudioDeviceInfo(id: 60, name: "USB Microphone", transport: .other,
                                  hasOutput: false, hasInput: true, sampleRate: 48000, inputChannels: 1)
        let profilesDict: [String: DeviceProfile] = [
            "HUAWEI FreeClip 2": DeviceProfile(managed: true, micPriority: [])
        ]
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, usb],
            profiles: profilesDict,
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .setInput(60))
    }

    func testDecideManualPriorityWinsOverAutoMic() {
        // PlumDog is in the priority list; USB has higher sampleRate but manual wins
        let usb = AudioDeviceInfo(id: 61, name: "USB Microphone", transport: .other,
                                  hasOutput: false, hasInput: true, sampleRate: 96000, inputChannels: 2)
        let manual = AudioDeviceInfo(id: 62, name: "PlumDog Microphone", transport: .other,
                                     hasOutput: false, hasInput: true, sampleRate: 44100, inputChannels: 1)
        let profilesDict: [String: DeviceProfile] = [
            "HUAWEI FreeClip 2": DeviceProfile(managed: true, micPriority: ["PlumDog Microphone"])
        ]
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, usb, manual],
            profiles: profilesDict,
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .setInput(62))
    }

    func testDecideManualPriorityAbsentFallsBackToAutoMic() {
        // "Absent Mic" is named in priority but not in devices → auto-pick selects usb
        let usb = AudioDeviceInfo(id: 63, name: "USB Microphone", transport: .other,
                                  hasOutput: false, hasInput: true, sampleRate: 48000, inputChannels: 1)
        let profilesDict: [String: DeviceProfile] = [
            "HUAWEI FreeClip 2": DeviceProfile(managed: true, micPriority: ["Absent Mic"])
        ]
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, usb],
            profiles: profilesDict,
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .setInput(63))
    }

    func testDecideLeavesAloneWhenNoNonBTInputExistsAtAll() {
        let profilesDict: [String: DeviceProfile] = [
            "HUAWEI FreeClip 2": DeviceProfile(managed: true, micPriority: [])
        ]
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei],
            profiles: profilesDict,
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .leaveAlone)
    }
}
