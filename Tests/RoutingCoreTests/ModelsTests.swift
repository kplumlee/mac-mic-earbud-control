import XCTest
@testable import RoutingCore

final class ModelsTests: XCTestCase {
    func testIsAirPodsMatchesCaseInsensitively() {
        XCTAssertTrue(isAirPods("AirPods Pro"))
        XCTAssertTrue(isAirPods("kevin's airpods max"))
        XCTAssertFalse(isAirPods("HUAWEI FreeClip 2"))
        XCTAssertFalse(isAirPods("Lumina Camera - Raw"))
    }

    func testAudioDeviceInfoStoresFields() {
        let d = AudioDeviceInfo(id: 42, name: "Mic", transport: .bluetooth,
                                hasOutput: false, hasInput: true)
        XCTAssertEqual(d.id, 42)
        XCTAssertEqual(d.transport, .bluetooth)
        XCTAssertTrue(d.hasInput)
    }
}
