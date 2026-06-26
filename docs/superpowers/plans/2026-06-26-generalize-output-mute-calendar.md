# Generalize + Output + Mute + Calendar — Implementation Plan (Phase 5)

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Make the app usable by anyone (not hardcoded to one user's mics) via auto-best-mic selection, then add: output-device management, a global mute hotkey + mic-in-use indicator, and calendar-aware meeting pre-launch.

**Architecture:** Extend pure `RoutingCore` (auto-mic selection, settings). Extend `AudioDeviceManager` (output switching, input mute, sample-rate/channels in the device model). Add a Carbon global-hotkey wrapper, an EventKit calendar service, and corresponding `AppModel`/`PopoverView`/`AppDelegate` wiring.

**Tech Stack:** CoreAudio, Carbon (`RegisterEventHotKey`), EventKit, SwiftUI, AppKit.

## Global Constraints

- `RoutingCore` stays pure (Foundation only).
- **Universal default:** no hardcoded device names in defaults. `Settings.defaultPriority` becomes `[]`. Selection falls back to "best non-Bluetooth input."
- `AudioDeviceInfo` gains `sampleRate: Double` and `inputChannels: Int` (so "best mic" = highest sample rate, then most input channels). Update ALL constructors + tests.
- New settings (all persisted): global `autoSwitchOutputToBluetooth: Bool` (default TRUE — always set a connecting Bluetooth headphone as the default output); `preferredOutputName: String?` (the device to switch the output BACK to when the Bluetooth headphone disconnects; nil = leave as macOS chooses); `muteHotkeyEnabled: Bool` (default true); `calendarPrelaunchEnabled: Bool` (default false); `calendarLeadMinutes: Int` (default 1).
- ENV: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for all swift commands.

---

### Task 23: Auto-best-mic (universal default) + sample-rate in the model

**Files:** `Sources/RoutingCore/Models.swift`, `Sources/RoutingCore/RoutingPolicy.swift`, `Sources/RoutingCore/Settings.swift`, `Sources/btmicrouter/AudioDeviceManager.swift`, tests.

- `AudioDeviceInfo`: add `public let sampleRate: Double` and `public let inputChannels: Int` to the struct + memberwise init. Update every existing constructor call in tests + `AudioDeviceManager.info(for:)` (populate `sampleRate` from `nominalSampleRate` logic and `inputChannels` from the input-scope stream/channel count — reuse existing stream reads; channels can be approximated by input stream count if a true channel count is hard, but prefer the device's input channel count via `kAudioDevicePropertyStreamConfiguration` if straightforward, else input stream count).
- `Settings.defaultPriority` → `[]` (empty). 
- `RoutingPolicy.decide(...)`: change the input-selection step to:
  1. Resolve `priority = profile.micPriority` (NO longer fall back to defaultPriority).
  2. For each name in `priority`, if a present device matches (name + hasInput) → `.setInput(id)`.
  3. If none matched (empty list or none present) → **auto-pick**: among `devices` where `hasInput && transport != .bluetooth && !isAirPods(name)` and `name != activeOutput.name`, pick the best by (highest `sampleRate`, then highest `inputChannels`, then name ascending) → `.setInput(id)`.
  4. If still none → `.leaveAlone`.
- Add a `RoutingPolicy.bestAutoMic(devices:excludingOutput:) -> AudioDeviceInfo?` helper (pure, tested).
- Tests: auto-pick chooses highest-sample-rate non-BT input; ignores Bluetooth + AirPods + the headset itself; manual priority still wins when its mic is present; auto-pick used when manual list present but none of its mics connected; `.leaveAlone` when no non-BT input exists.

Commit `feat: universal auto-best-mic selection; sample rate/channels in device model`.

---

### Task 24: Settings for output/mute/calendar (+ graceful DeviceProfile decode)

**Files:** `Sources/RoutingCore/Settings.swift`, tests. (No `DeviceProfile` change — output switching is GLOBAL, not per-device.)

- `Settings`: add `var autoSwitchOutputToBluetooth: Bool` (DEFAULT TRUE — use `object(forKey:) as? Bool ?? true`); `var preferredOutputName: String?` (the device to switch output back to on disconnect; nil = leave as-is); `var muteHotkeyEnabled: Bool` (default true, `?? true` pattern); `var calendarPrelaunchEnabled: Bool` (default false); `var calendarLeadMinutes: Int` (default 1; `object(forKey:) as? Int ?? 1`). Add keys to the Key enum.
- Tests: each new setting's default-when-unset + round-trip (fresh `UserDefaults(suiteName:)` per test). For `preferredOutputName`: nil when unset, round-trips a string, and can be cleared back to nil.

Commit `feat: settings for output switching, mute hotkey, calendar`.

---

### Task 25: AudioDeviceManager — output switch + input mute

**Files:** `Sources/btmicrouter/AudioDeviceManager.swift`.

- `@discardableResult func setDefaultOutputDevice(_ id: DeviceID) -> Bool` — write `kAudioHardwarePropertyDefaultOutputDevice` (mirror `setDefaultInputDevice`).
- `func isInputMuted() -> Bool` / `@discardableResult func setInputMuted(_ muted: Bool) -> Bool` — operate on the default input device's `kAudioDevicePropertyMute` (scope input, element 0/main). If the device doesn't support `Mute` (status != noErr on get), fall back to `kAudioDevicePropertyVolumeScalar` (set 0.0 to mute / restore — for restore, set to 1.0; keep it simple). Return whether the operation applied.
- Build-verified (may be unreferenced until later tasks). Commit `feat: output-device switch and input mute`.

---

### Task 26: Output management (logic + UI)

**Files:** `Sources/btmicrouter/AppDelegate.swift`, `Sources/btmicrouter/AppModel.swift`, `Sources/btmicrouter/PopoverView.swift`.

- AppDelegate: keep a `previousDeviceNames: Set<String>`. On each `apply()` (driven by the device-list listener, already debounced), diff against the new device set:
  - **Appeared** Bluetooth output devices (`transport == .bluetooth && hasOutput && !isAirPods`): if `settings.autoSwitchOutputToBluetooth`, call `manager.setDefaultOutputDevice(thatID)` (set the connecting headphone as output). If several appeared, pick the first.
  - **Disappeared** Bluetooth output device that was the current default output (i.e. the active output is now gone): if `settings.preferredOutputName` resolves to a present device, `manager.setDefaultOutputDevice(thatID)`; else leave macOS to choose.
  Update `previousDeviceNames` at the end. This is purely additive to the existing input-routing in `apply()`.
- AppModel: `var autoSwitchOutputToBluetooth: Bool { get set }` (write-through + onChange); `var preferredOutputName: String? { get set }`; `func outputDeviceNames() -> [String]` (current devices with `hasOutput`, deduped).
- PopoverView: add an "Output" section (near the devices section): a toggle "Always switch output to Bluetooth headphones on connect" bound to `autoSwitchOutputToBluetooth`, and a `Picker` "When disconnected, switch back to:" bound to `preferredOutputName` over `outputDeviceNames()` with a leading "Leave to macOS" (nil) option.
- Verify build + tests. Commit `feat: global output switching to Bluetooth with chosen fallback`.

---

### Task 27: Mute hotkey + mic-in-use indicator

**Files:** create `Sources/btmicrouter/GlobalHotKey.swift`; modify `AppDelegate.swift`, `StatusItemController.swift`, `AppModel.swift`, `PopoverView.swift`.

- `GlobalHotKey`: a small Carbon `RegisterEventHotKey` wrapper (`import Carbon`). Register a default chord (⌃⌥⌘M) with a callback; `unregister()` on teardown. No Accessibility permission needed.
- AppDelegate: if `settings.muteHotkeyEnabled`, register the hotkey → toggles `manager.setInputMuted(!manager.isInputMuted())`; push state after. Unregister on terminate / when disabled.
- Icon (`StatusItemController.updateIcon`): add `muted` and `micHot` inputs. Priority: muted → `mic.slash` (red), in-meeting → `record.circle` (red), micHot (mic in use, not muted) → `mic.fill` (red/orange tint), routing → `mic.fill`, paused → `pause.circle`, idle → `mic`. AppDelegate computes `muted = manager.isInputMuted()` and `micHot = manager.isDefaultInputInUse()` in `pushState()`, and also refresh the icon on the existing 2 s timer tick so the indicator is responsive.
- AppModel: `@Published var inputMuted`, `@Published var micInUse`; `func toggleMute()` (calls injected action). PopoverView: a "Microphone" row showing mute state + a Mute/Unmute button, and a caption showing the hotkey (⌃⌥⌘M) with a toggle "Mute hotkey" bound to `muteHotkeyEnabled`.
- Verify build + tests. Commit `feat: global mute hotkey and mic-in-use indicator`.

---

### Task 28: Calendar service (EventKit) + Info.plist

**Files:** create `Sources/btmicrouter/CalendarService.swift`; modify `scripts/build-app.sh`.

- `build-app.sh`: add `NSCalendarsUsageDescription` (string explaining "shows your next meeting and can pre-launch your notes app") to the generated Info.plist.
- `CalendarService`: `func requestAccess(_ completion: @escaping (Bool) -> Void)` (`EKEventStore.requestAccess(to: .event)`); `struct UpcomingMeeting { let title: String; let start: Date; let joinURL: URL? }`; `func nextMeeting(within hours: Int) -> UpcomingMeeting?` — build the predicate with `predicateForEvents(withStart:end:calendars: nil)` so it spans **ALL connected calendars across ALL accounts** (iCloud, Google, Microsoft 365/Exchange — whatever the user added in System Settings → Internet Accounts), NOT just the default calendar; return the soonest; parse a join URL from the event's `url`, `location`, or `notes` (regex for `https://[^ ]*(zoom.us|meet.google.com|teams.microsoft.com|webex.com)[^ ]*`). Handle "no access" gracefully (returns nil). The app does NOT do any provider OAuth — it relies on macOS Calendar's synced accounts, which is the whole point (Google + Microsoft 365 work automatically).
- Build-verified. Commit `feat: EventKit calendar service for next meeting`.

---

### Task 29: Calendar integration (pre-launch + UI)

**Files:** `Sources/btmicrouter/AppDelegate.swift`, `Sources/btmicrouter/AppModel.swift`, `Sources/btmicrouter/PopoverView.swift`.

- AppDelegate: hold a `CalendarService`; if `settings.calendarPrelaunchEnabled`, request access once; on the existing 2 s timer (or a 30 s coarser tick), fetch `nextMeeting(within: 12)`, push it to the model; when a meeting's start is within `calendarLeadMinutes` and not already handled, launch `settings.launchAppsOnMeeting` (reuse `launchApp`) and open the join URL (`NSWorkspace.shared.open`). Guard so each meeting only pre-launches once (track last-handled event start).
- AppModel: `@Published var nextMeetingTitle: String?`, `nextMeetingStart: Date?`, `nextMeetingHasLink: Bool`; `var calendarPrelaunchEnabled: Bool { get set }` (setter requests access via injected action); `func openNextMeeting()`.
- PopoverView: a "Next meeting" card (only when calendar enabled + a meeting exists): title + relative time ("in 6 min") via TimelineView, a "Join" button if a link exists. A toggle "Calendar pre-launch" (enables + triggers the permission prompt) and a small stepper/menu for lead minutes.
- Verify full `swift build -c release` + `swift test`. Commit `feat: calendar-aware next-meeting display and pre-launch`.

---

### Task 30: Empty-state/“Auto” UI polish + README + rebuild

**Files:** `Sources/btmicrouter/PopoverView.swift`, `README.md`.

- In the mic-priority editor, when a managed device has an empty manual list, show a clear "Auto — best built-in/USB mic" row (with the resolved auto mic name if available) and a "Customize" affordance to add manual entries. Make it obvious the app works with zero config.
- README: rewrite the intro so it's for ANY user (not Lumina-specific): explain auto-best-mic, output management, mute hotkey, calendar; keep build/install steps. Remove Lumina-specific defaults from the docs (mention it as an example only).
- Commit `docs: generalize README; auto-mic empty state`. Then (controller) rebuild + reinstall + relaunch.

---

## Notes
- Calendar + mute touch TCC: EventKit shows a calendar prompt on first enable; the mute uses CoreAudio (no prompt). Document both.
- Keep every per-task build green; the full app build is green from Task 26 onward (earlier executable-only tasks may be unreferenced but must compile).
