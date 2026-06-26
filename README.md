# Bluetooth Mic Router

A macOS menu-bar app that keeps non-Apple Bluetooth headphones in full-quality
audio mode by routing your microphone input to the best available built-in or
USB mic whenever a managed Bluetooth device is the active output.

## Why

Non-AirPods Bluetooth headsets drop to telephone-quality audio (HFP/HSP codec)
the moment an app claims their microphone. There is no macOS API to fix the
codec. This app routes *around* the problem: your Bluetooth headset handles
output, and a good built-in or USB mic handles input. Zero configuration is
required — on first connect the app automatically picks the highest-quality
non-Bluetooth input available.

## Features

- **Auto best-mic (default, zero config)** — when a managed Bluetooth headset
  becomes the active output, the app automatically selects the best available
  non-Bluetooth input (ranked by sample rate, then channel count). No mic
  priority list is needed; the "Auto — best built-in/USB mic" mode is the
  default.
- **Manual mic priority (optional)** — open the per-device editor and add
  inputs in preferred order. The first connected mic in the list wins; remove
  all entries to return to Auto mode.
- **Output switching** — optionally have the app automatically switch output to
  the Bluetooth headphones on connect, and fall back to a chosen device
  (e.g., your studio monitors) on disconnect.
- **Global mute hotkey (⌃⌥⌘M)** — mute or unmute your mic from any app.
  The menu-bar icon turns red when muted or when you are in a detected meeting,
  and orange when your mic is live.
- **Calendar pre-launch** — reads your macOS calendars (iCloud, Google,
  Microsoft 365 — added via System Settings → Internet Accounts) and opens your
  notes app and the meeting join link a configurable number of minutes before
  each event.
- **Meeting automation** — detects active meetings (call app running + mic in
  use), launches configured apps, pauses Spotify/Music, and shows a recording
  reminder banner.
- **Per-device profiles** — each Bluetooth device independently remembers
  whether it is managed and its mic priority order (stored in `UserDefaults`).
- **Live quality readout** — the popover shows the current input sample rate
  with a green (≥ 24 kHz, high quality) or orange (degraded, telephone-quality)
  pill so you can confirm routing is working.
- **Switch notifications** — a macOS system notification fires when the input
  device changes (requires the app bundle).

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

The binary lands at `.build/release/btmicrouter`. Useful for quick iteration or
running `--list`, but **notifications will not work** without the app bundle.

## Install (bare binary, legacy path)

    mkdir -p ~/Applications/btmicrouter
    cp .build/release/btmicrouter ~/Applications/btmicrouter/btmicrouter
    ~/Applications/btmicrouter/btmicrouter &

Then enable **Launch at login** from the menu.

## One-time permission prompts

| Prompt | Trigger | Required for |
|---|---|---|
| Calendar access | First time "Calendar pre-launch" is enabled | Reading meeting titles and join links |
| Automation (Spotify / Music) | First time music pause is triggered | Pausing/resuming music during meetings |

## User Interface

The app runs in the macOS menu bar — click the mic icon to open the popover.

**Menu-bar icon states:**
- `mic` — idle
- `mic.fill` — routing active (input redirected)
- `record.circle` (red) — in a meeting
- `pause.circle` — paused / automation suspended

**Popover sections:**
- **Live status** — active mic, sample-rate quality pill, elapsed meeting time
- **Bluetooth Output Devices** — managed toggle + per-device mic-priority editor
  (shows "Auto — best built-in/USB mic" when no manual list is set, with the
  resolved mic name in secondary text; use "Add input" to build a manual list)
- **Output** — auto-switch on connect; fallback output on disconnect
- **Microphone** — mute toggle + hotkey enable/disable
- **Meeting Automation** — master toggle, launch apps, pause music, record reminder
- **Calendar** — pre-launch toggle, next meeting display, lead-time stepper
- **Per-App Rules** — restrict switching to configured call apps
- **Footer** — Launch at login toggle, version, Quit

## Meeting automation

When **Meeting automation** is enabled, the app watches for an active meeting
and automatically:

- **Detects the meeting** — a configured call app (Zoom, Teams, FaceTime, etc.)
  must be running *and* the microphone must be live.
- **Auto-launches apps** — apps in your launch list (e.g., Granola) are opened
  in the background at meeting start.
- **Pauses Spotify / Music** — if either app is currently *playing*, it is
  paused at meeting start and resumed at meeting end. Apps that are already
  paused are left untouched.
- **Shows meeting state** — the menu-bar icon updates and the popover shows
  elapsed time.

### Recording backstop

When a meeting is detected, the app sends a **"Meeting started — Recording?
Don't forget"** notification (toggle: "Remind me to record") and shows a
dismissible reminder banner in the popover.

The app **cannot reliably press "Record"** inside Zoom, Teams, or Google Meet.
The most reliable approaches:

1. **Zoom native auto-record** — enable "Automatically record meeting" in Zoom
   settings. The popover has a "Turn on Zoom auto-record…" link.
2. **Granola + Google Calendar** — link Granola to your calendar; it
   auto-transcribes scheduled meetings. Auto-launch Granola via the launch-apps
   list.

## Example: Lumina camera mic setup

The app works with any non-Bluetooth input — a built-in mic, a USB audio
interface, or a USB camera mic. As one example: a Lumina webcam has a high-
quality USB microphone. To pin it as the preferred mic for a specific headset,
open the per-device editor for that headset, click "Add input", and select
"Lumina". Drag it to the top if needed. With no manual list, the app picks the
Lumina automatically if it ranks highest by sample rate.

## Inspect detected devices

    ./.build/release/btmicrouter --list
