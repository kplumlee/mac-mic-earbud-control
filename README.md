# Bluetooth Mic Router

A macOS menu-bar app that keeps non-Apple Bluetooth headsets in full-quality
output mode by routing the microphone to a wired/USB mic (the Lumina camera,
with fallbacks) whenever a managed Bluetooth device is the active output.

## Why

Non-AirPods Bluetooth headsets drop to telephone-quality audio the moment an app
uses their mic (HFP/HSP). There is no API to fix the mic codec, so this app
routes *around* it: headset for output, a good mic for input.

## Install (recommended: app bundle)

Building as a `.app` bundle is the recommended installation path. It enables:

- **Switch notifications** — `UNUserNotificationCenter` requires a bundle
  identifier; the bare binary cannot send system notifications.
- **Stable launch-at-login path** — "Launch at login" from the menu writes a
  LaunchAgent that points at `BTMicRouter.app/Contents/MacOS/btmicrouter`,
  which survives rebuilds as long as the app stays in the same location.

```
./scripts/build-app.sh
mv BTMicRouter.app ~/Applications/
open ~/Applications/BTMicRouter.app
```

After pulling changes, rebuild and reinstall:
```
./scripts/build-app.sh
mv BTMicRouter.app ~/Applications/
```
then quit and reopen the app.

The app lives in the menu bar (🎙️). There is no Dock icon (`LSUIElement=true`).

> **Note on signing:** the script uses ad-hoc code signing (`codesign -s -`),
> which is sufficient for running on your own Mac. If macOS Gatekeeper blocks
> the first launch, right-click → Open, or run:
> `xattr -dr com.apple.quarantine ~/Applications/BTMicRouter.app`

## Build (bare binary, advanced)

    swift build -c release

The binary lands at `.build/release/btmicrouter`. This is useful for quick
iteration or running `--list`, but **notifications will not work** without the
app bundle.

## Install (bare binary, legacy path)

    mkdir -p ~/Applications/btmicrouter
    cp .build/release/btmicrouter ~/Applications/btmicrouter/btmicrouter
    ~/Applications/btmicrouter/btmicrouter &

Then enable **Launch at login** from the menu (writes a LaunchAgent pointing at
that stable path; effective next login).

## Features

- **Per-device profiles** — each Bluetooth headset independently remembers
  whether it is managed and which mic priority order to use. Profiles are
  stored in `UserDefaults` keyed by device name.
- **Live quality readout** — the menu shows the current input sample rate with
  a ✅ (high quality, ≥ 24 kHz) or ⚠️ (degraded, telephone-quality) indicator
  so you can confirm routing is working at a glance.
- **Switch notifications** — when the app changes the input device a macOS
  system notification is delivered (requires the app bundle; grant permission
  on first launch).
- **Per-app rules ("Only switch for call apps")** — enable this option per
  device to restrict automatic switching to a configurable list of call
  applications (Zoom, Teams, FaceTime, etc.), leaving other apps undisturbed.
  Per-app rules trigger when a configured call app is running (not necessarily frontmost).

## User Interface

The app runs in the macOS menu bar with a polished **SwiftUI popover** — click the menu-bar mic icon to open it.

**Menu-bar icon states** (SF Symbols):
- `mic` — idle (no routing active)
- `mic.fill` — routing active (input redirected to priority mic)
- `record.circle` (red) — in a meeting
- `pause.circle` — paused / automation suspended

**Popover sections:**
- **Live status** — current microphone and sample-rate quality (✅ high quality ≥24 kHz, or ⚠️ degraded)
- **Output devices** — each managed Bluetooth headset with per-device mic-priority editor
- **Meeting automation** — enable/disable, launch apps, pause music
- **Per-app rules** — restrict switching to call apps (Zoom, Teams, FaceTime, etc.)
- **Footer** — Launch at login toggle, Quit button

## Meeting automation

When **Meeting automation** is enabled (toggle in the menu), the app watches for
an active meeting and automatically:

- **Detects the meeting** — a configured call app (Zoom, Teams, FaceTime, etc.)
  must be running *and* the microphone must be live. Browser meetings (e.g.
  Google Meet in Chrome) are detected only if the browser is in your call-apps
  list and the mic is in use.
- **Auto-launches apps** — any apps in your launch list (e.g. Granola) are
  opened in the background at meeting start.
- **Pauses Spotify / Music** — if either app is currently *playing*, it is
  paused when the meeting starts and automatically resumed when the meeting ends
  (or when the app quits mid-meeting). Apps that are already paused are left
  untouched so music that was manually stopped is never unexpectedly restarted.
- **Shows meeting state** — the menu-bar icon updates and the menu shows a
  🔴 "In a meeting" entry with the elapsed time.

### Configuring meeting automation

| Menu item | What it does |
|---|---|
| Meeting automation | Master toggle — enable/disable all automation |
| Launch apps on meeting | Comma-separated list of app names to open at start |
| Pause music on meeting | Toggle music pause/resume behaviour |

### Recording backstop

When a meeting is detected, the app sends a **🔴 "Meeting started — Recording? Don't forget"** notification (toggle: "Remind me to record" in the menu) and shows a dismissible reminder banner in the popover during the meeting.

**Important:** The app **cannot reliably press "Record"** in Zoom, Teams, or Google Meet — those record buttons are inside the app and permission-gated. The **reliable ways to never miss a recording** are:

1. **Zoom's native auto-record** — Enable "Automatically record meeting" in Zoom's settings. The popover has a "Turn on Zoom auto-record…" link that opens Zoom's help page for this setting.
2. **Granola + Google Calendar** — Link Granola to your Google Calendar; it auto-transcribes scheduled meetings and auto-launches when you join.

You can auto-launch Granola (or other apps) on meeting start via the **Launch apps on meeting** list, but launching the app ≠ recording — Granola only starts capturing when you open a note or join a calendar-linked meeting.

### First-run permission prompt

The first time the app pauses Spotify or Music, macOS shows a one-time
automation prompt: *"btmicrouter wants to control Spotify."* Click **Allow**.
Without it the pause/resume commands are silently ignored.

## Inspect detected devices

    ./.build/release/btmicrouter --list
