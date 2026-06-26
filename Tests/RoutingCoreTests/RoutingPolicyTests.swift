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

    let priority = ["Lumina Camera - Raw", "PlumDog Microphone", "EarPods Microphone"]

    func testManagedBluetoothOutputRoutesToLumina() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina, plumdog],
            managedNames: ["HUAWEI FreeClip 2"], micPriority: priority, paused: false)
        XCTAssertEqual(d, .setInput(10))
    }

    func testFallsBackWhenLuminaAbsent() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, plumdog],
            managedNames: ["HUAWEI FreeClip 2"], micPriority: priority, paused: false)
        XCTAssertEqual(d, .setInput(11))
    }

    func testLeavesAloneWhenNoPriorityMicPresent() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei],
            managedNames: ["HUAWEI FreeClip 2"], micPriority: priority, paused: false)
        XCTAssertEqual(d, .leaveAlone)
    }

    func testUnmanagedBluetoothLeavesAlone() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina],
            managedNames: [], micPriority: priority, paused: false)
        XCTAssertEqual(d, .leaveAlone)
    }

    func testAirPodsLeftAloneEvenIfManaged() {
        let d = RoutingPolicy.decide(
            activeOutput: airpods, devices: [airpods, lumina],
            managedNames: ["AirPods Pro"], micPriority: priority, paused: false)
        XCTAssertEqual(d, .leaveAlone)
    }

    func testNonBluetoothOutputLeavesAlone() {
        let d = RoutingPolicy.decide(
            activeOutput: speakers, devices: [speakers, lumina],
            managedNames: ["Mac Studio Speakers"], micPriority: priority, paused: false)
        XCTAssertEqual(d, .leaveAlone)
    }

    func testPausedLeavesAlone() {
        let d = RoutingPolicy.decide(
            activeOutput: huawei, devices: [huawei, lumina],
            managedNames: ["HUAWEI FreeClip 2"], micPriority: priority, paused: true)
        XCTAssertEqual(d, .leaveAlone)
    }

    func testManagedCandidatesExcludeAirPodsAndNonBluetooth() {
        let c = RoutingPolicy.managedCandidates(devices: [huawei, airpods, speakers, lumina])
        XCTAssertEqual(c.map(\.name), ["HUAWEI FreeClip 2"])
    }
}
