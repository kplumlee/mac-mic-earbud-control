# Profiles & Enhancements — Implementation Plan (Addendum)

> Extends the base app (`2026-06-25-bluetooth-mic-router.md`). REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Add per-Bluetooth-device profiles (saved settings per headset), a live mic-quality readout, a switch notification, and per-app (call-app-only) routing rules.

**Architecture:** Replace the global `managedNames` + single `micPriority` in `Settings` with a `profiles: [String: DeviceProfile]` map keyed by device name. `RoutingPolicy.decide` resolves the active output's profile and gains optional per-app gating. The executable gains a sensing layer (input sample-rate read + frontmost-app bundle id), per-device priority-editing UI, a quality readout, and `UNUserNotification` toasts.

**Tech Stack:** Swift, CoreAudio (`kAudioDevicePropertyNominalSampleRate`), AppKit/`NSWorkspace` (frontmost app + activation notifications), `UserNotifications`, `Codable`/JSON in `UserDefaults`.

## Global Constraints

- `RoutingCore` stays pure (Foundation only). `DeviceProfile` and the decision logic live there.
- Persistence: `Settings.profiles` is encoded as JSON `Data` under a single UserDefaults key. `paused`, `callAppsOnly: Bool`, `callApps: [String]` (bundle IDs) also persist.
- A device with no stored profile resolves to a default `DeviceProfile(managed: false, micPriority: Settings.defaultPriority)`.
- `defaultPriority` stays `["Lumina Camera - Raw", "PlumDog Microphone", "EarPods Microphone"]`.
- Default `callApps` bundle IDs: `["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.FaceTime", "com.google.Chrome", "com.cisco.webexmeetingsapp", "com.hnc.Discord", "com.tinyspeck.slackmacgap"]`.
- AirPods (name contains "airpods") are never managed and never get an editable profile.
- ENV: run swift with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

### Task 9: Per-device profiles + per-app gating in RoutingCore

**Files:**
- Modify: `Sources/RoutingCore/Settings.swift`
- Create: `Sources/RoutingCore/DeviceProfile.swift`
- Modify: `Sources/RoutingCore/RoutingPolicy.swift`
- Modify: `Tests/RoutingCoreTests/SettingsTests.swift`
- Modify: `Tests/RoutingCoreTests/RoutingPolicyTests.swift`

**Produces:**
- `public struct DeviceProfile: Codable, Equatable { public var managed: Bool; public var micPriority: [String]; public init(managed: Bool, micPriority: [String]) }`
- `Settings`:
  - `var profiles: [String: DeviceProfile]` (JSON-encoded under key `"profiles"`; getter decodes, returns `[:]` if absent/corrupt; setter encodes).
  - `func profile(for name: String) -> DeviceProfile` — returns stored profile or `DeviceProfile(managed: false, micPriority: Settings.defaultPriority)`.
  - `func setProfile(_ profile: DeviceProfile, for name: String)` — stores into the map.
  - `var callAppsOnly: Bool` (default false), `var callApps: [String]` (default the bundle-ID list above), `var paused: Bool` (unchanged).
  - Keep `static let defaultPriority`. REMOVE the old `managedNames` and `micPriority` stored properties.
- `RoutingPolicy.decide(activeOutput:devices:profiles:paused:frontmostBundleID:callAppsOnly:callApps:) -> RoutingDecision`:
  - `paused` → `.leaveAlone`.
  - if `callAppsOnly` and (`frontmostBundleID == nil` or not in `callApps`) → `.leaveAlone`.
  - guard `activeOutput` Bluetooth, not AirPods, and `profiles[name]?.managed == true` (use `profile(for:)`-equivalent default of managed=false when absent → not managed) → else `.leaveAlone`.
  - priority = the profile's `micPriority` (if empty, fall back to `Settings.defaultPriority`); first device whose `name` matches and `hasInput` → `.setInput(id)`; none → `.leaveAlone`.
- `managedCandidates(devices:)` unchanged.

- [ ] **Step 1: Write/adapt failing tests** — port existing RoutingPolicy tests to the new signature (build a `profiles` dict instead of `managedNames`/`micPriority`); add: per-app gating blocks when `callAppsOnly` and frontmost not in list; per-app gating allows when frontmost in list; per-device priority differs between two devices (device A → Lumina, device B → PlumDog) selects correctly. Adapt SettingsTests: profiles round-trip through JSON; `profile(for:)` returns default for unknown device; `callAppsOnly`/`callApps` round-trip and defaults.
- [ ] **Step 2: Run tests, verify fail.** `DEVELOPER_DIR=... swift test`
- [ ] **Step 3: Implement** `DeviceProfile.swift`, the `Settings` changes, and the `RoutingPolicy.decide` rewrite per the contract above.
- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** `feat: per-device profiles and per-app routing gate`.

---

### Task 10: Sensing layer (sample rate + frontmost app)

**Files:**
- Modify: `Sources/btmicrouter/AudioDeviceManager.swift`
- Create: `Sources/btmicrouter/FrontmostApp.swift`

**Produces:**
- `AudioDeviceManager.nominalSampleRate(for id: DeviceID) -> Double?` — reads `kAudioDevicePropertyNominalSampleRate` (global scope) as `Float64`; nil on error.
- `enum FrontmostApp { static func bundleID() -> String? }` — `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`.

- [ ] **Step 1: Implement both** following the existing CoreAudio property-read pattern in the file (two-call not needed; sample rate is a fixed-size `Float64`).
- [ ] **Step 2: Build** `DEVELOPER_DIR=... swift build` — must compile (these may be unreferenced until Task 12; that's fine).
- [ ] **Step 3: Commit** `feat: sample-rate read and frontmost-app helper`.

---

### Task 11: Per-device UI + quality readout + per-app rules menu

**Files:**
- Modify: `Sources/btmicrouter/StatusMenuController.swift`

**Behavior:**
- "Managed Bluetooth devices": each non-AirPods BT output device is a checkbox toggling `settings.profile(for: name).managed` (read-modify-write via `setProfile`). AirPods stay disabled/auto-excluded.
- For each MANAGED device, attach a submenu "⚙︎ <name> mic priority" containing that device's `micPriority` with per-entry Move Up / Move Down (omit when at an end) / Remove, plus an "Add input device" submenu of currently-detected `hasInput` devices not already in that device's list. All edits read-modify-write that device's `DeviceProfile.micPriority` via `setProfile` and call `onUserChange`.
- Status line / quality readout: when routing is active, show the resolved input mic and its sample rate from `manager.nominalSampleRate(for:)`, with `⚠️` if `< 24000` (HFP-ish) else `✅`, e.g. `✅ HUAWEI FreeClip 2 → Lumina Camera - Raw (48 kHz)`.
- Per-app rules section: a "Only switch for call apps" checkbox bound to `settings.callAppsOnly`; a submenu listing `settings.callApps` with checkmarks (toggle remove) and an "Add frontmost app" item that appends `FrontmostApp.bundleID()` if not present.
- Keep Pause/Resume, Fix input now, Launch at login, Quit.
- Icon logic uses `RoutingPolicy.decide` with the new params (pass `frontmostBundleID: FrontmostApp.bundleID()`, `callAppsOnly`, `callApps`).

- [ ] **Step 1: Implement** the menu rebuild against the new `Settings`/`RoutingPolicy` API. Replace all references to the removed `managedNames`/`micPriority`.
- [ ] **Step 2: Build** (full build needs Task 12 wiring updated too; if AppDelegate still uses old API, this task's build may fail on AppDelegate only — confirm errors are confined to AppDelegate.swift). Commit `feat: per-device priority UI, quality readout, per-app rules menu`.

---

### Task 12: AppDelegate wiring + notifications + frontmost observer

**Files:**
- Modify: `Sources/btmicrouter/AppDelegate.swift`
- Modify: `Sources/btmicrouter/main.swift` (only if `--list` should also print sample rate — optional)

**Behavior:**
- `apply()` calls `RoutingPolicy.decide` with `profiles: settings.profiles, paused:, frontmostBundleID: FrontmostApp.bundleID(), callAppsOnly:, callApps:`.
- On an actual switch (`.setInput(id)` AND the input changed), post a `UNUserNotification` "Mic → <name>" (request authorization once at launch; if denied, silently skip — never crash).
- Observe `NSWorkspace.shared.notificationCenter` `didActivateApplicationNotification` → `scheduleApply()` so per-app rules re-evaluate when you switch apps.
- Full `DEVELOPER_DIR=... swift build -c release` must succeed; `swift test` green.

- [ ] **Step 1: Implement** wiring + notifications + observer.
- [ ] **Step 2: Build release + test**, both green.
- [ ] **Step 3: Commit** `feat: per-app gating, switch notifications, frontmost-app re-evaluation`.

---

## Notes
- Tasks 9 is pure/tested. Tasks 10–12 are CoreAudio/AppKit (build-verified + manual). Tasks 11–12 share the new API; the full build is green only after Task 12.
- README update for the new features happens after Task 12 (fold into the finishing step).
