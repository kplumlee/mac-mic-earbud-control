# Polished UI + Recording Backstop — Implementation Plan (Phase 4)

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** (1) A "recording backstop" so you never forget to record: when a meeting is detected, fire an unmissable reminder and surface it in the UI; plus in-app guidance to enable Zoom's native auto-record. (2) Replace the plain `NSMenu` with a polished **SwiftUI popover** (sections, SF Symbols, live status, real toggles) shown from the menu-bar item, and an SF-Symbol status icon.

**Architecture:** Introduce an `AppModel: ObservableObject` (executable target) that wraps `Settings` + live device/meeting state and exposes intents (toggle managed, edit priority, toggles, quit, etc.). SwiftUI views bind to it. `AppDelegate` keeps the CoreAudio/meeting logic and pushes state into `AppModel`; an `NSPopover` hosting the SwiftUI root replaces `StatusMenuController`'s menu. The pure `RoutingCore` is unchanged except a new setting.

**Tech Stack:** SwiftUI, AppKit (`NSStatusItem`, `NSPopover`, `NSHostingController`), Combine (`@Published`), SF Symbols, `UNUserNotifications`.

## Global Constraints

- `RoutingCore` stays pure (Foundation only).
- macOS 13+ (SwiftUI APIs used must be available on 13). Use `MenuBarExtra`? NO — keep `NSStatusItem` + `NSPopover` for control and macOS-13 compatibility.
- New setting: `recordReminderEnabled: Bool` (default true).
- The popover REPLACES the NSMenu; all existing capabilities must remain reachable: managed-device toggles, per-device mic priority (reorder/add/remove), per-app rules (callAppsOnly + callApps), meeting automation (enabled, launch apps, pause music), pause/resume, fix-now, launch-at-login, quit, plus the new recording reminder + Zoom auto-record help.
- SF Symbols for the menu-bar icon reflecting state: in-meeting (`record.circle`, red), routing-active (`mic.fill`/`waveform`), idle (`mic`), paused (`pause.circle`).
- ENV: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for all swift commands.

## File Structure (new/changed in `Sources/btmicrouter/`)

```
AppModel.swift            (new) ObservableObject: state + intents
PopoverView.swift         (new) SwiftUI root + section subviews
StatusItemController.swift (new) NSStatusItem + NSPopover host + SF Symbol icon  (replaces StatusMenuController)
AppDelegate.swift         (modify) own AppModel; push state; wire StatusItemController; recording reminder
Settings.swift (RoutingCore) (modify) add recordReminderEnabled
```
`StatusMenuController.swift` is deleted (superseded).

---

### Task 18: Recording-reminder setting + backstop logic

**Files:** modify `Sources/RoutingCore/Settings.swift` (+ its tests); modify `Sources/btmicrouter/AppDelegate.swift`.

- Add `Settings.recordReminderEnabled: Bool` default TRUE (`object(forKey:) as? Bool ?? true` pattern). Add a SettingsTests default + round-trip case.
- In `AppDelegate.meetingDidStart()`, after existing actions, if `settings.recordReminderEnabled`, post a prominent notification (reuse the guarded notification helper): title "🔴 Meeting started", body "Recording? Don't forget." — this is the backstop. Keep launch-apps + pause-music as-is.
- Expose the current meeting state for the UI: AppDelegate already tracks `meetingActive`/`meetingStartedAt`; ensure these are readable (they will be pushed into AppModel in Task 21).

TDD for the Settings part (`swift test`); the AppDelegate notification is build-verified. Commit `feat: record-reminder setting and meeting-start backstop notification`.

---

### Task 19: AppModel (ObservableObject view model)

**Files:** create `Sources/btmicrouter/AppModel.swift`.

`final class AppModel: ObservableObject` holding live state and intents. It is constructed with the `Settings` and `AudioDeviceManager` instances (injected from AppDelegate).

**@Published state** (updated by AppDelegate via a `refresh(...)` method):
- `devices: [AudioDeviceInfo]`
- `activeOutputName: String?`, `activeInputName: String?`, `activeInputSampleRateKHz: Int?`
- `routingActive: Bool`
- `paused: Bool`
- `meetingActive: Bool`, `meetingSince: Date?`
- `loginEnabled: Bool`

**Computed/helpers for the views:**
- `bluetoothDevices: [AudioDeviceInfo]` (transport == .bluetooth && hasOutput), with `isAirPods(name)` flag.
- `func isManaged(_ name: String) -> Bool` / `func setManaged(_ name: String, _ on: Bool)` (via Settings.profile/setProfile).
- `func micPriority(for name: String) -> [String]`, `func moveMic(for:from:to:)`, `func removeMic(for:name:)`, `func addMic(for:name:)`.
- per-app: `callAppsOnly: Bool { get set }`, `callApps: [String]`, `func removeCallApp(_:)`, `func addFrontmostCallApp()`.
- meeting automation: `meetingAutomationEnabled`, `launchAppsOnMeeting`, `pauseMusicOnMeeting`, `recordReminderEnabled` get/set; `func removeLaunchApp(_:)`, `func addLaunchApp(_:)`, `runningAppNames() -> [String]`.
- intents: `func togglePaused()`, `func fixNow()` (calls an injected closure), `func toggleLogin()` (LoginItem), `func quit()`.
- Setters write through to `Settings` and then call an injected `onChange` closure (so AppDelegate re-applies routing + re-pushes state). Each mutating method ends by calling `onChange()`.

All settings access goes through `Settings`; AppModel holds NO source-of-truth of its own for persisted values (reads them live), so the UI and routing never diverge. Mark `@Published` only the live device/meeting/status fields.

Build-verified (`swift build`); may be unreferenced until Task 21. Commit `feat: AppModel view model for SwiftUI UI`.

---

### Task 20: SwiftUI popover views

**Files:** create `Sources/btmicrouter/PopoverView.swift`.

A `PopoverView: View` (`@ObservedObject var model: AppModel`), ~360pt wide, scrollable, native macOS look (use `.formStyle(.grouped)` Form OR custom card `GroupBox`es; system materials; SF Symbols via `Image(systemName:)`; `.tint`). Sections, each a clear card with a header:

1. **Status header** — large: if `meetingActive` a red `record.circle` + "In a meeting" + elapsed (a `TimelineView(.periodic)` ticking the elapsed time from `meetingSince`); else if `routingActive` `mic.fill` + "<output> → <input> (<kHz> kHz)" with a green ✓ when ≥24kHz else an orange ⚠︎; else `mic` + "Idle". A `Pause/Resume` button.
2. **Recording reminder banner** — only when `meetingActive` AND `recordReminderEnabled`: a prominent red-tinted card "Recording? Don't forget to hit record." with a "Got it" button (sets a transient dismissed flag in the model for this meeting) and an "Open Granola" button (calls model intent to `open -a Granola`).
3. **Bluetooth devices** — each non-AirPods BT output device: a `Toggle` bound to `model.isManaged`/`setManaged`. AirPods row disabled with "auto-excluded". For each managed device, a disclosure/group with its **mic priority**: a reorderable `List` (`.onMove`) of mics with ● present/○ absent indicators, swipe/`-` to remove, and a `Menu` "Add input device" listing addable present inputs.
4. **Meeting automation** — `Toggle` "Enable meeting automation"; `Toggle` "Pause music in meetings"; `Toggle` "Remind me to record"; a "Launch on meeting" list (Granola etc.) with add (Menu of running apps) / remove; a help row "Enable Zoom auto-record…" that opens `https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067954` via the model.
5. **Per-app rules** — `Toggle` "Only switch for call apps"; a list of `callApps` (remove) + "Add frontmost app".
6. **Footer** — "Launch at login" `Toggle`, "Quit" button, small version text.

Keep the visual style cohesive: consistent padding (12–16), section headers in `.headline`, secondary text in `.secondary`, SF Symbols sized consistently, color only for state (green/orange/red). No emoji in the popover (SF Symbols instead).

Build-verified (`swift build`). Commit `feat: SwiftUI popover UI`.

---

### Task 21: NSPopover host + status item + wire-up (replace NSMenu)

**Files:** create `Sources/btmicrouter/StatusItemController.swift`; modify `Sources/btmicrouter/AppDelegate.swift`; delete `Sources/btmicrouter/StatusMenuController.swift`.

- `StatusItemController`: owns the `NSStatusItem`; its button uses an SF Symbol (`NSImage(systemSymbolName:accessibilityDescription:)`) that updates with state (idle/routing/meeting/paused); clicking the button toggles an `NSPopover` whose `contentViewController` is an `NSHostingController(rootView: PopoverView(model:))`. Handle accessory-app activation so the popover takes focus (`NSApp.activate(ignoringOtherApps: true)` on show; close on outside click via popover `behavior = .transient`). Expose `func updateIcon(state:)`.
- `AppDelegate`: construct `AppModel(settings:manager:onChange:fixNow:)`; build `StatusItemController(model:)`. Replace every former `menuController.refreshMenu(...)` / `updateMeeting(...)` call with `model.refresh(...)` (push live device + routing + meeting + login state into the model) and `statusItemController.updateIcon(state:)`. The model's `onChange` closure calls `apply()` (re-route) and then re-pushes state. Remove all references to `StatusMenuController`; delete the file.
- Keep all CoreAudio/meeting/timer logic intact.

Verify full: `DEVELOPER_DIR=... swift build -c release` clean; `DEVELOPER_DIR=... swift test` all pass. Commit `feat: SwiftUI popover replaces NSMenu; SF Symbol status icon`.

---

### Task 22: Docs + rebuild

**Files:** modify `README.md`.
- Document the recording backstop (reminder on meeting start; it does NOT press record inside Zoom/Meet — explain why and that the reliable path is Zoom's native auto-record + Granola calendar linking). Document the new popover UI.
- Note: run `./scripts/build-app.sh` and reinstall.

Commit `docs: recording backstop and new UI`. Then (controller, outside SDD) rebuild + reinstall + relaunch.

---

## Notes
- The SwiftUI popover needs the `.app` bundle (already produced by build-app.sh). Test by launching the installed app and clicking the menu-bar icon.
- macOS 13 SwiftUI: avoid APIs newer than Ventura (e.g. prefer `List`/`Form`/`GroupBox`; `TimelineView` is fine on 13).
