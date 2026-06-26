# Bluetooth Mic Router Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu-bar app that forces the system microphone to the Lumina camera (with fallbacks) whenever a user-selected Bluetooth headset is the active output, keeping the headset in full-quality output mode.

**Architecture:** A Swift Package Manager project with two layers: a pure, unit-tested `RoutingCore` library (device models, decision policy, settings) and an executable `btmicrouter` target that wraps CoreAudio (device enumeration, listeners, switching) and renders an `NSStatusItem` menu. The executable runs as a background accessory app (no Dock icon) and is event-driven via CoreAudio property listeners — no polling.

**Tech Stack:** Swift 5.9, Swift Package Manager, AppKit (`NSStatusItem`), CoreAudio (`AudioObjectGetPropertyData` / `AudioObjectAddPropertyListenerBlock`), `UserDefaults`, LaunchAgent plist for login-at-launch. No third-party dependencies.

## Global Constraints

- **Platform:** macOS 13+ (`.macOS(.v13)` in Package.swift).
- **No third-party dependencies.** CoreAudio + AppKit + Foundation only.
- **Device identity is by name** (e.g. `Lumina Camera - Raw`, `HUAWEI FreeClip 2`), resolved to a live `AudioDeviceID` at switch time.
- **Bluetooth** = CoreAudio transport type `kAudioDeviceTransportTypeBluetooth` or `...BluetoothLE`.
- **AirPods** (name contains "airpods", case-insensitive) are never managed.
- **Bundle/LaunchAgent label:** `com.kplumlee.btmicrouter`.
- **Default mic priority:** `Lumina Camera - Raw` → `PlumDog Microphone` → `EarPods Microphone`.
- **`RoutingCore` must not import CoreAudio or AppKit** — it stays pure and testable. Use the local `DeviceID = UInt32` typealias, not CoreAudio's `AudioDeviceID`.

## File Structure

```
Package.swift
Sources/
  RoutingCore/
    Models.swift              # DeviceID, DeviceTransport, AudioDeviceInfo, isAirPods
    RoutingPolicy.swift       # decide(...) -> RoutingDecision, managedCandidates(...)
    Settings.swift            # UserDefaults-backed config
  btmicrouter/
    main.swift                # entry point, --list CLI, accessory policy
    AudioDeviceManager.swift  # CoreAudio wrapper (read/write/listen)
    AppDelegate.swift         # wiring: listeners -> policy -> manager, debounce
    StatusMenuController.swift # NSStatusItem menu
    LoginItem.swift           # LaunchAgent install/remove
Tests/
  RoutingCoreTests/
    ModelsTests.swift
    RoutingPolicyTests.swift
    SettingsTests.swift
README.md
```

---

### Task 1: Package scaffold + core models

**Files:**
- Create: `Package.swift`
- Create: `Sources/RoutingCore/Models.swift`
- Test: `Tests/RoutingCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public typealias DeviceID = UInt32`
  - `public enum DeviceTransport { case bluetooth, other }`
  - `public struct AudioDeviceInfo { let id: DeviceID; let name: String; let transport: DeviceTransport; let hasOutput: Bool; let hasInput: Bool }` with a public memberwise `init`.
  - `public func isAirPods(_ name: String) -> Bool`

- [ ] **Step 1: Write the failing test**

`Tests/RoutingCoreTests/ModelsTests.swift`:
```swift
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
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "btmicrouter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "RoutingCore"),
        .executableTarget(
            name: "btmicrouter",
            dependencies: ["RoutingCore"]
        ),
        .testTarget(
            name: "RoutingCoreTests",
            dependencies: ["RoutingCore"]
        ),
    ]
)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/Developer/bluetooth-mic-router && swift test`
Expected: FAIL — compile error, `RoutingCore` has no `isAirPods` / `AudioDeviceInfo`. (An empty executable target also needs a file; create a placeholder `main.swift` with `// placeholder` if the build complains about the missing executable source, then it is replaced in Task 5.)

- [ ] **Step 4: Write minimal implementation**

`Sources/RoutingCore/Models.swift`:
```swift
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
```

Also create `Sources/btmicrouter/main.swift` with a single line so the executable target compiles:
```swift
// Replaced in Task 5.
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test`
Expected: PASS (ModelsTests, 2 tests).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/RoutingCore/Models.swift Sources/btmicrouter/main.swift Tests/RoutingCoreTests/ModelsTests.swift
git commit -m "feat: package scaffold and core device models"
```

---

### Task 2: Routing decision policy

**Files:**
- Create: `Sources/RoutingCore/RoutingPolicy.swift`
- Test: `Tests/RoutingCoreTests/RoutingPolicyTests.swift`

**Interfaces:**
- Consumes: `AudioDeviceInfo`, `DeviceTransport`, `isAirPods` from Task 1.
- Produces:
  - `public enum RoutingDecision: Equatable { case leaveAlone; case setInput(DeviceID) }`
  - `public enum RoutingPolicy` with:
    - `static func decide(activeOutput: AudioDeviceInfo?, devices: [AudioDeviceInfo], managedNames: Set<String>, micPriority: [String], paused: Bool) -> RoutingDecision`
    - `static func managedCandidates(devices: [AudioDeviceInfo]) -> [AudioDeviceInfo]`

- [ ] **Step 1: Write the failing test**

`Tests/RoutingCoreTests/RoutingPolicyTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RoutingPolicyTests`
Expected: FAIL — `RoutingPolicy` / `RoutingDecision` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/RoutingCore/RoutingPolicy.swift`:
```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RoutingPolicyTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/RoutingCore/RoutingPolicy.swift Tests/RoutingCoreTests/RoutingPolicyTests.swift
git commit -m "feat: routing decision policy with fallback and exclusions"
```

---

### Task 3: Settings (UserDefaults persistence)

**Files:**
- Create: `Sources/RoutingCore/Settings.swift`
- Test: `Tests/RoutingCoreTests/SettingsTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `public final class Settings` with `init(defaults: UserDefaults = .standard)`, and mutable properties `managedNames: Set<String>`, `micPriority: [String]`, `paused: Bool`.
  - `public static let defaultPriority: [String]`

- [ ] **Step 1: Write the failing test**

`Tests/RoutingCoreTests/SettingsTests.swift`:
```swift
import XCTest
@testable import RoutingCore

final class SettingsTests: XCTestCase {
    private func freshSettings() -> Settings {
        let suite = "test.btmicrouter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return Settings(defaults: defaults)
    }

    func testDefaultsWhenUnset() {
        let s = freshSettings()
        XCTAssertEqual(s.managedNames, [])
        XCTAssertEqual(s.micPriority, Settings.defaultPriority)
        XCTAssertFalse(s.paused)
    }

    func testRoundTripsManagedNames() {
        let s = freshSettings()
        s.managedNames = ["HUAWEI FreeClip 2", "BoomAudio"]
        XCTAssertEqual(s.managedNames, ["HUAWEI FreeClip 2", "BoomAudio"])
    }

    func testRoundTripsPriorityAndPaused() {
        let s = freshSettings()
        s.micPriority = ["PlumDog Microphone", "Lumina Camera - Raw"]
        s.paused = true
        XCTAssertEqual(s.micPriority, ["PlumDog Microphone", "Lumina Camera - Raw"])
        XCTAssertTrue(s.paused)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsTests`
Expected: FAIL — `Settings` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/RoutingCore/Settings.swift`:
```swift
import Foundation

public final class Settings {
    private let defaults: UserDefaults

    private enum Key {
        static let managed = "managedDeviceNames"
        static let priority = "micPriority"
        static let paused = "paused"
    }

    public static let defaultPriority = [
        "Lumina Camera - Raw",
        "PlumDog Microphone",
        "EarPods Microphone",
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var managedNames: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.managed) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.managed) }
    }

    public var micPriority: [String] {
        get { defaults.stringArray(forKey: Key.priority) ?? Settings.defaultPriority }
        set { defaults.set(newValue, forKey: Key.priority) }
    }

    public var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/RoutingCore/Settings.swift Tests/RoutingCoreTests/SettingsTests.swift
git commit -m "feat: UserDefaults-backed settings with defaults"
```

---

### Task 4: CoreAudio device manager

**Files:**
- Create: `Sources/btmicrouter/AudioDeviceManager.swift`

**Interfaces:**
- Consumes: `AudioDeviceInfo`, `DeviceID`, `DeviceTransport` from RoutingCore.
- Produces (`final class AudioDeviceManager`):
  - `func defaultOutputDevice() -> DeviceID?`
  - `func defaultInputDevice() -> DeviceID?`
  - `func allDevices() -> [AudioDeviceInfo]`
  - `@discardableResult func setDefaultInputDevice(_ id: DeviceID) -> Bool`
  - `func startListening(onChange: @escaping () -> Void)`
  - `func stopListening()`

This task wraps CoreAudio and is verified by a manual smoke test (`--list`, wired up in Task 5), not unit tests — CoreAudio talks to real hardware.

- [ ] **Step 1: Write the implementation**

`Sources/btmicrouter/AudioDeviceManager.swift`:
```swift
import Foundation
import CoreAudio
import RoutingCore

final class AudioDeviceManager {
    private let system = AudioObjectID(kAudioObjectSystemObject)

    // MARK: - Reading defaults

    func defaultOutputDevice() -> DeviceID? {
        readSystemDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func defaultInputDevice() -> DeviceID? {
        readSystemDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    private func readSystemDeviceID(selector: AudioObjectPropertySelector) -> DeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &dev)
        guard status == noErr, dev != 0 else { return nil }
        return DeviceID(dev)
    }

    // MARK: - Enumerating devices

    func allDevices() -> [AudioDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { info(for: $0) }
    }

    private func info(for id: AudioDeviceID) -> AudioDeviceInfo {
        AudioDeviceInfo(
            id: DeviceID(id),
            name: deviceName(id) ?? "Unknown",
            transport: deviceTransport(id),
            hasOutput: streamCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
            hasInput: streamCount(id, scope: kAudioObjectPropertyScopeInput) > 0)
    }

    private func deviceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfName)
        guard status == noErr, let cf = cfName?.takeRetainedValue() else { return nil }
        return cf as String
    }

    private func deviceTransport(_ id: AudioDeviceID) -> DeviceTransport {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr else {
            return .other
        }
        if transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE {
            return .bluetooth
        }
        return .other
    }

    private func streamCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    // MARK: - Writing

    @discardableResult
    func setDefaultInputDevice(_ id: DeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(id)
        let status = AudioObjectSetPropertyData(
            system, &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
        return status == noErr
    }

    // MARK: - Listening

    private var listenerAddresses: [AudioObjectPropertyAddress] = []
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    func startListening(onChange: @escaping () -> Void) {
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDevices,
        ]
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { onChange() }
        }
        listenerBlock = block
        for selector in selectors {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main, block)
            listenerAddresses.append(addr)
        }
    }

    func stopListening() {
        guard let block = listenerBlock else { return }
        for var addr in listenerAddresses {
            AudioObjectRemovePropertyListenerBlock(system, &addr, DispatchQueue.main, block)
        }
        listenerAddresses.removeAll()
        listenerBlock = nil
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds (manager is not yet referenced; that is fine — confirm no compile errors in this file). Manual functional verification happens in Task 5 via `--list`.

- [ ] **Step 3: Commit**

```bash
git add Sources/btmicrouter/AudioDeviceManager.swift
git commit -m "feat: CoreAudio device manager (enumerate, switch, listen)"
```

---

### Task 5: App entry point, wiring, and `--list` smoke test

**Files:**
- Modify: `Sources/btmicrouter/main.swift` (replace placeholder)
- Create: `Sources/btmicrouter/AppDelegate.swift`

This task wires CoreAudio listeners → `RoutingPolicy.decide` → `AudioDeviceManager`, with a 0.3s debounce. `StatusMenuController` and `LoginItem` are referenced here but implemented in Tasks 6–7; implement those before the final build/run, or temporarily stub the two `menuController` calls. To keep tasks independently testable, this task's verification is the **`--list`** CLI path, which does not need the menu.

- [ ] **Step 1: Replace `Sources/btmicrouter/main.swift`**

```swift
import AppKit
import RoutingCore

// Hidden CLI: print detected audio devices and exit (manual verification).
if CommandLine.arguments.contains("--list") {
    let manager = AudioDeviceManager()
    let outID = manager.defaultOutputDevice()
    let inID = manager.defaultInputDevice()
    for d in manager.allDevices() {
        var flags: [String] = []
        flags.append(d.transport == .bluetooth ? "BT " : "   ")
        flags.append(d.hasOutput ? "out" : "   ")
        flags.append(d.hasInput ? "in" : "  ")
        if d.id == outID { flags.append("[default-out]") }
        if d.id == inID { flags.append("[default-in]") }
        print("\(d.id)\t\(flags.joined(separator: " "))\t\(d.name)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
```

- [ ] **Step 2: Create `Sources/btmicrouter/AppDelegate.swift`**

```swift
import AppKit
import RoutingCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = AudioDeviceManager()
    private let settings = Settings()
    private var menuController: StatusMenuController!
    private var debounceItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = StatusMenuController(
            settings: settings,
            manager: manager,
            onUserChange: { [weak self] in self?.apply() },
            onFixNow: { [weak self] in self?.apply() })
        manager.startListening { [weak self] in self?.scheduleApply() }
        apply()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopListening()
    }

    /// Coalesce listener storms (rapid connect/disconnect) before acting.
    private func scheduleApply() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.apply() }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func apply() {
        let devices = manager.allDevices()
        let activeOutput = manager.defaultOutputDevice().flatMap { id in
            devices.first { $0.id == id }
        }
        let decision = RoutingPolicy.decide(
            activeOutput: activeOutput,
            devices: devices,
            managedNames: settings.managedNames,
            micPriority: settings.micPriority,
            paused: settings.paused)

        switch decision {
        case .leaveAlone:
            break
        case .setInput(let id):
            if manager.defaultInputDevice() != id {
                manager.setDefaultInputDevice(id)
            }
        }
        menuController.refreshMenu(devices: devices)
    }
}
```

- [ ] **Step 3: Build and run the smoke test**

Run: `swift build && ./.build/debug/btmicrouter --list`
Expected: A list of your real devices, e.g. a line containing `BT  out` and `HUAWEI FreeClip 2`, a line with `in` and `Lumina Camera - Raw`, and `[default-out]` / `[default-in]` markers. This proves CoreAudio enumeration, naming, transport classification, and stream detection all work on your machine.

(The full `swift build` will fail until Tasks 6–7 exist because `AppDelegate` references `StatusMenuController`. If running this task in isolation, temporarily comment out the `menuController` lines to exercise `--list`, then restore them. Subagent-driven execution should implement Tasks 6–7 before the final build.)

- [ ] **Step 4: Commit**

```bash
git add Sources/btmicrouter/main.swift Sources/btmicrouter/AppDelegate.swift
git commit -m "feat: app entry point, listener wiring, and --list smoke test"
```

---

### Task 6: Menu-bar UI

**Files:**
- Create: `Sources/btmicrouter/StatusMenuController.swift`

**Interfaces:**
- Consumes: `Settings`, `AudioDeviceManager`, `RoutingPolicy`, `isAirPods`, `AudioDeviceInfo`, and `LoginItem` (Task 7).
- Produces (`final class StatusMenuController`):
  - `init(settings: Settings, manager: AudioDeviceManager, onUserChange: @escaping () -> Void, onFixNow: @escaping () -> Void)`
  - `func refreshMenu(devices: [AudioDeviceInfo])`

- [ ] **Step 1: Create `Sources/btmicrouter/StatusMenuController.swift`**

```swift
import AppKit
import RoutingCore

final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings: Settings
    private let manager: AudioDeviceManager
    private let onUserChange: () -> Void
    private let onFixNow: () -> Void

    init(settings: Settings, manager: AudioDeviceManager,
         onUserChange: @escaping () -> Void, onFixNow: @escaping () -> Void) {
        self.settings = settings
        self.manager = manager
        self.onUserChange = onUserChange
        self.onFixNow = onFixNow
        super.init()
        statusItem.button?.title = "🎙️"
        refreshMenu(devices: manager.allDevices())
    }

    func refreshMenu(devices: [AudioDeviceInfo]) {
        updateIcon(devices: devices)

        let menu = NSMenu()

        let header = disabledItem(statusLine(devices: devices))
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(disabledItem("Managed Bluetooth devices"))
        let bluetooth = devices.filter { $0.transport == .bluetooth && $0.hasOutput }
        if bluetooth.isEmpty {
            menu.addItem(disabledItem("  (no Bluetooth devices connected)"))
        }
        for dev in bluetooth {
            if isAirPods(dev.name) {
                menu.addItem(disabledItem("  \(dev.name)  (auto-excluded)"))
            } else {
                let item = NSMenuItem(title: dev.name,
                                      action: #selector(toggleManaged(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = dev.name
                item.state = settings.managedNames.contains(dev.name) ? .on : .off
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        menu.addItem(disabledItem("Mic priority"))
        for (idx, mic) in settings.micPriority.enumerated() {
            let present = devices.contains { $0.name == mic && $0.hasInput }
            let mark = present ? "●" : "○"
            menu.addItem(disabledItem("  \(idx + 1). \(mark) \(mic)"))
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: settings.paused ? "Resume" : "Pause",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let fix = NSMenuItem(title: "Fix input now", action: #selector(fixNow), keyEquivalent: "")
        fix.target = self
        menu.addItem(fix)

        let login = NSMenuItem(title: "Launch at login",
                               action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func updateIcon(devices: [AudioDeviceInfo]) {
        if settings.paused {
            statusItem.button?.title = "⏸"
        } else if isRoutingActive(devices: devices) {
            statusItem.button?.title = "🎙️✅"
        } else {
            statusItem.button?.title = "🎙️"
        }
    }

    private func isRoutingActive(devices: [AudioDeviceInfo]) -> Bool {
        guard let outID = manager.defaultOutputDevice(),
              let out = devices.first(where: { $0.id == outID }) else { return false }
        let decision = RoutingPolicy.decide(
            activeOutput: out, devices: devices,
            managedNames: settings.managedNames,
            micPriority: settings.micPriority, paused: settings.paused)
        if case .setInput = decision { return true }
        return false
    }

    private func statusLine(devices: [AudioDeviceInfo]) -> String {
        if settings.paused { return "⏸ Paused" }
        guard let outID = manager.defaultOutputDevice(),
              let out = devices.first(where: { $0.id == outID }) else { return "Idle" }
        guard out.transport == .bluetooth, !isAirPods(out.name),
              settings.managedNames.contains(out.name) else { return "Idle" }
        for mic in settings.micPriority where devices.contains(where: { $0.name == mic && $0.hasInput }) {
            return "✅ \(out.name) → \(mic)"
        }
        return "⚠️ \(out.name): no fallback mic available"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleManaged(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var managed = settings.managedNames
        if managed.contains(name) { managed.remove(name) } else { managed.insert(name) }
        settings.managedNames = managed
        onUserChange()
    }

    @objc private func togglePause() {
        settings.paused.toggle()
        onUserChange()
    }

    @objc private func fixNow() { onFixNow() }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        onUserChange()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/btmicrouter/StatusMenuController.swift
git commit -m "feat: menu-bar UI with managed devices, priority, and controls"
```

---

### Task 7: Launch at login (LaunchAgent)

**Files:**
- Create: `Sources/btmicrouter/LoginItem.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (`enum LoginItem`):
  - `static var isEnabled: Bool`
  - `static func setEnabled(_ enabled: Bool)`

Login-at-launch is implemented by writing a per-user LaunchAgent plist (works for a bare SPM binary, no app bundle or code signing required). Installing/removing the plist takes effect at the **next login**; we do not `launchctl load` immediately to avoid a duplicate running instance.

- [ ] **Step 1: Create `Sources/btmicrouter/LoginItem.swift`**

```swift
import Foundation

enum LoginItem {
    static let label = "com.kplumlee.btmicrouter"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            install()
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func install() {
        let binaryPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binaryPath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL)
        }
    }
}
```

- [ ] **Step 2: Build the whole app**

Run: `swift build -c release`
Expected: Build succeeds — all targets compile, `StatusMenuController` and `LoginItem` references in `AppDelegate` now resolve.

- [ ] **Step 3: Commit**

```bash
git add Sources/btmicrouter/LoginItem.swift
git commit -m "feat: launch-at-login via per-user LaunchAgent plist"
```

---

### Task 8: README, install, and manual acceptance

**Files:**
- Create: `README.md`

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: PASS — ModelsTests, RoutingPolicyTests, SettingsTests all green.

- [ ] **Step 2: Create `README.md`**

```markdown
# Bluetooth Mic Router

A macOS menu-bar app that keeps non-Apple Bluetooth headsets in full-quality
output mode by routing the microphone to a wired/USB mic (the Lumina camera,
with fallbacks) whenever a managed Bluetooth device is the active output.

## Why

Non-AirPods Bluetooth headsets drop to telephone-quality audio the moment an app
uses their mic (HFP/HSP). There is no API to fix the mic codec, so this app
routes *around* it: headset for output, a good mic for input.

## Build

    swift build -c release

The binary lands at `.build/release/btmicrouter`.

## Install (stable path for login item)

    mkdir -p ~/Applications/btmicrouter
    cp .build/release/btmicrouter ~/Applications/btmicrouter/btmicrouter
    ~/Applications/btmicrouter/btmicrouter &

Then enable **Launch at login** from the menu (writes a LaunchAgent pointing at
that stable path; effective next login).

## Usage

- Click the 🎙️ menu-bar icon.
- Check the Bluetooth devices to manage (AirPods are auto-excluded).
- Mic priority is `Lumina Camera - Raw` → `PlumDog Microphone` →
  `EarPods Microphone`; the first one present is used.
- Pause / Resume and Fix input now are in the menu.

## Inspect detected devices

    ./.build/release/btmicrouter --list
```

- [ ] **Step 3: Manual acceptance checklist**

Run the app: `swift build -c release && ./.build/release/btmicrouter &`

Verify each:
1. 🎙️ icon appears in the menu bar.
2. With Huawei connected, open the menu, check **HUAWEI FreeClip 2** under Managed Bluetooth devices.
3. Confirm input switches to `Lumina Camera - Raw` (System Settings → Sound → Input, or `./.build/release/btmicrouter --list` shows `[default-in]` on the Lumina). Status line reads `✅ HUAWEI FreeClip 2 → Lumina Camera - Raw`.
4. Unplug the Lumina → input falls to `PlumDog Microphone` (next present priority).
5. Switch system output to **Mac Studio Speakers** → status goes `Idle`, input is left alone.
6. Connect AirPods (if available) → they appear greyed/auto-excluded; input untouched.
7. Toggle **Pause** → icon shows ⏸, no switching occurs.
8. Quit and relaunch → managed devices, priority, and pause state are all restored.
9. Toggle **Launch at login** → `~/Library/LaunchAgents/com.kplumlee.btmicrouter.plist` is created/removed.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README and manual acceptance checklist"
```

---

## Notes for the Implementer

- **Task ordering:** Tasks 1–3 are pure TDD and independently testable with `swift test`. Task 4 builds in isolation. Task 5's `AppDelegate` references types from Tasks 6–7, so the *full* `swift build` only succeeds once Tasks 6–7 land; until then verify Task 5 via the `--list` path (commenting the two `menuController` lines if running strictly in isolation). Subagent-driven execution should treat Tasks 5–7 as a group for the final build.
- **No CoreAudio in RoutingCore:** keep the library pure so `swift test` runs without hardware.
- **CoreAudio constants** (`kAudioHardwarePropertyDefaultInputDevice`, `kAudioDeviceTransportTypeBluetooth`, etc.) come from `import CoreAudio`.
