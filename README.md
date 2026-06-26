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

## Usage

- Click the 🎙️ menu-bar icon.
- Check the Bluetooth devices to manage (AirPods are auto-excluded).
- Mic priority is `Lumina Camera - Raw` → `PlumDog Microphone` →
  `EarPods Microphone`; the first one present is used.
- Pause / Resume and Fix input now are in the menu.

## Inspect detected devices

    ./.build/release/btmicrouter --list
