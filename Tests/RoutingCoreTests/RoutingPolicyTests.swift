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

    // Helper: build a profiles dict with the given names marked managed, using defaultPriority
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

    func testManagedBluetoothOutputRoutesToLumina() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina, plumdog],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .setInput(10))
    }

    func testFallsBackWhenLuminaAbsent() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, plumdog],
            profiles: profiles(managed: ["HUAWEI FreeClip 2"]),
            paused: false, runningBundleIDs: [], callAppsOnly: false, callApps: [])
        XCTAssertEqual(d, .setInput(11))
    }

    func testLeavesAloneWhenNoPriorityMicPresent() {
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
}
