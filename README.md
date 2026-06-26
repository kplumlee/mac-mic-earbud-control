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
