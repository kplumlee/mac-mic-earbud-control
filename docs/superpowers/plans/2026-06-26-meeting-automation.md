# Meeting Automation — Implementation Plan (Addendum, Phase 3)

> Extends the app. REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Detect when a meeting starts (a configured call app is running AND the mic is live), and on that transition auto-launch Granola (and any configured apps), pause music, and show a 🔴 "in a meeting" state in the menu; restore on meeting end.

**Architecture:** A pure meeting predicate + new settings in `RoutingCore`; a CoreAudio "is the input in use" read in `AudioDeviceManager`; a polling meeting coordinator in `AppDelegate` (2 s timer) that detects transitions and runs actions; menu UI for the in-meeting state and automation settings.

**Tech Stack:** CoreAudio (`kAudioDevicePropertyDeviceIsRunningSomewhere`), `NSWorkspace.runningApplications`, `Process` (`/usr/bin/open -g -a`), `NSAppleScript` (pause/resume Spotify/Music), `UserNotifications`.

## Global Constraints

- `RoutingCore` stays pure (Foundation only).
- Meeting apps = the existing `Settings.callApps` bundle-id list (reused; not a new list).
- New persisted settings: `meetingAutomationEnabled: Bool` (default true), `launchAppsOnMeeting: [String]` (default `["Granola"]`, these are app NAMES for `open -a`), `pauseMusicOnMeeting: Bool` (default true).
- Detection is poll-based (2 s timer) — simple and robust. The *predicate* is pure and unit-tested.
- Launch apps with `open -g -a <name>` (background, no focus steal, idempotent).
- Pause/resume music ONLY for Spotify (`com.spotify.client`) / Music (`com.apple.Music`) when they are already running — never launch them. Uses AppleScript; expect a one-time macOS automation prompt.
- ENV: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for all swift commands.

---

### Task 14: Meeting predicate + settings (RoutingCore)

**Files:** Create `Sources/RoutingCore/MeetingPolicy.swift`; modify `Sources/RoutingCore/Settings.swift`; modify `Tests/RoutingCoreTests/SettingsTests.swift`; create `Tests/RoutingCoreTests/MeetingPolicyTests.swift`.

**Produces:**
- `enum MeetingPolicy { static func isMeetingActive(runningBundleIDs: Set<String>, meetingApps: [String], micInUse: Bool) -> Bool }` = `micInUse && !Set(meetingApps).isDisjoint(with: runningBundleIDs)`.
- `Settings`: `var meetingAutomationEnabled: Bool` (default true — use a presence check so default is true when unset, e.g. store as object and default true), `var launchAppsOnMeeting: [String]` (default `["Granola"]`), `var pauseMusicOnMeeting: Bool` (default true). All JSON/array/bool persisted like existing settings.

**Tests:** isMeetingActive — false when micInUse false (even with meeting app running); false when mic in use but no meeting app running; true when mic in use AND a meeting app running. Settings — defaults (enabled true, launch `["Granola"]`, pause true) and round-trip.

Steps: write failing tests → run (`swift test`) fail → implement → run pass → commit `feat: meeting predicate and automation settings`.

NOTE for default-true bools: `UserDefaults.bool` defaults to false. For `meetingAutomationEnabled` and `pauseMusicOnMeeting` (default true), store/read via `object(forKey:) as? Bool ?? true`.

---

### Task 15: Input-in-use read (AudioDeviceManager)

**Files:** modify `Sources/btmicrouter/AudioDeviceManager.swift`.

**Produces:** `func isDefaultInputInUse() -> Bool` — resolve the default input device id; read `kAudioDevicePropertyDeviceIsRunningSomewhere` (global scope, main element) into a `UInt32`; return `value != 0`. Return false on no-device/error. Follow the file's existing property-read idiom.

Verify: `swift build` clean (may be unreferenced until Task 16). Commit `feat: detect whether the input device is in use`.

---

### Task 16: Meeting coordinator (AppDelegate)

**Files:** modify `Sources/btmicrouter/AppDelegate.swift`.

**Behavior:**
- Add a 2 s repeating `Timer` started in `applicationDidFinishLaunching`, invalidated in `applicationWillTerminate`. Each tick → `evaluateMeeting()`.
- State: `private var meetingActive = false`, `private var meetingStartedAt: Date?`, `private var didPauseMusic = false`.
- `evaluateMeeting()`:
  - `let active = settings.meetingAutomationEnabled && MeetingPolicy.isMeetingActive(runningBundleIDs: RunningApps.bundleIDs(), meetingApps: settings.callApps, micInUse: manager.isDefaultInputInUse())`.
  - Transition false→true: set state, `meetingStartedAt = Date()`; for each name in `settings.launchAppsOnMeeting` run `open -g -a <name>` via `Process`; if `settings.pauseMusicOnMeeting` pause Spotify/Music (only if running) and set `didPauseMusic = true`; post a guarded notification ("Meeting detected", body listing launched apps); `menuController.updateMeeting(active: true, since: meetingStartedAt)`.
  - Transition true→false: clear state; if `didPauseMusic` resume Spotify/Music (only if running), reset `didPauseMusic=false`; `menuController.updateMeeting(active: false, since: nil)`.
  - If automation just disabled while active, treat as a false transition (cleanup).
- Helpers: `launchApp(_ name:)` (Process `/usr/bin/open` args `["-g","-a",name]`, `try?`); `musicCommand(_ verb:)` where verb is "pause"/"play" — for each of (`com.spotify.client`→"Spotify", `com.apple.Music`→"Music") only if that bundle id is in `RunningApps.bundleIDs()`, run `NSAppleScript(source: "tell application \"<App>\" to <verb>")?.executeAndReturnError(nil)`; `postNotification(title:body:)` (guarded by `Bundle.main.bundleIdentifier != nil`, reuse the existing notification pattern).
- Do NOT disturb the existing `apply()` routing logic; meeting evaluation is independent.

Verify: `swift build -c release` clean; `swift test` (22+new) green. Requires Task 17's `updateMeeting` on StatusMenuController — if building before Task 17, add a temporary no-op `updateMeeting` or implement 17 first. Commit `feat: meeting coordinator — launch apps, pause music, notify`.

---

### Task 17: In-meeting menu state + automation settings UI (StatusMenuController)

**Files:** modify `Sources/btmicrouter/StatusMenuController.swift`.

**Behavior:**
- Add `private var meetingActive = false`, `private var meetingSince: Date?`, and `func updateMeeting(active: Bool, since: Date?)` that stores them and calls `refreshMenu(devices: manager.allDevices())`.
- Icon: if `meetingActive` show "🔴"; else existing ⏸ / 🎙️✅ / 🎙️ logic.
- Status: when `meetingActive`, FIRST line "🔴 In a meeting (since HH:MM)" (format `meetingSince` with a `DateFormatter`, "HH:mm"); keep the routing status line below it.
- New "Meeting automation" section (above Pause/Resume): checkbox "Meeting automation" → `settings.meetingAutomationEnabled` (toggle persists + onUserChange); submenu "Launch on meeting" listing `settings.launchAppsOnMeeting` (each clickable to REMOVE), separator, "Add running app" submenu of currently-running app `localizedName`s (`NSWorkspace.shared.runningApplications`) not already in the list (click to ADD); checkbox "Pause music in meetings" → `settings.pauseMusicOnMeeting`.
- Carry app name through `@objc` actions via `representedObject` (a String).

Verify: `swift build -c release` clean; `swift test` green. Commit `feat: in-meeting menu state and meeting automation settings UI`.

---

## Notes
- After Task 17, run `./scripts/build-app.sh`, reinstall to `~/Applications`, relaunch.
- Detection limitation (document in README later): browser meetings rely on the browser being in `callApps` + mic live; "in use" is the default input device.
