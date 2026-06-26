# Bluetooth Mic Router — Design

**Date:** 2026-06-25
**Status:** Approved (pending spec review)
**Platform:** macOS (developed/tested on Mac Studio, macOS 26 Tahoe)

## Problem

When a non-Apple Bluetooth headset (e.g. HUAWEI FreeClip 2) is the active audio
device on macOS, any app that uses the headset microphone forces the Bluetooth
link into **HFP/HSP** (two-way) mode. The shared Bluetooth bandwidth then
collapses output and input to a low-quality wideband/narrowband codec
(CVSD ~8 kHz or mSBC ~16 kHz) — "telephone" quality. This was confirmed live:
the HUAWEI FreeClip 2 was the default input at **16000 Hz** while connected.

AirPods avoid this because Apple's H1/H2 chip negotiates a premium wideband
voice codec that macOS special-cases. Third-party headsets get the
lowest-common-denominator codec, and **no app can change which mic codec macOS
negotiates** — there is no public API for it.

## Goal

Route *around* the problem instead of trying to fix the codec: whenever a
**user-selected** Bluetooth output device is active, force the system microphone
**input** to a high-quality wired/USB mic (the Lumina camera), keeping the
headset in full-quality output-only (A2DP) mode. AirPods are excluded from
management because their mic is already good.

## Non-Goals

- Improving the Huawei (or any third-party) Bluetooth mic codec itself — not
  possible from an app; no public API.
- Managing AirPods — intentionally excluded.
- Per-application audio routing — system default input only.

## Solution Overview

A lightweight **menu-bar app** (Swift + AppKit + CoreAudio, no third-party
dependencies) that:

1. Listens for CoreAudio events (event-driven, no polling).
2. When the active **output** device is one of the user's **managed** Bluetooth
   devices, sets the default **input** to the first available mic in a
   user-defined priority list (Lumina first).
3. Re-asserts the input if macOS tries to switch it back to the headset mic
   while a managed device is active.
4. Stops asserting when the active output is not a managed device.

## Detection & Switching (CoreAudio)

- **Output-active detection:** listen on `kAudioHardwarePropertyDefaultOutputDevice`.
- **Device list changes:** listen on `kAudioHardwarePropertyDevices` (handles
  connect/disconnect of headphones and the Lumina).
- **Input enforcement:** listen on `kAudioHardwarePropertyDefaultInputDevice`;
  if it changes to a managed-device mic while a managed device is the active
  output, re-set it to the priority mic.
- **Bluetooth identification:** a device is "Bluetooth" when its
  `kAudioDevicePropertyTransportType` is `kAudioDeviceTransportTypeBluetooth`
  or `...BluetoothLE`.
- **AirPods exclusion:** any device whose name contains "AirPods"
  (case-insensitive) is excluded from the managed list and shown greyed-out.
- **Setting a device:** write `kAudioHardwarePropertyDefaultInputDevice` with
  the resolved `AudioDeviceID`.

Devices are matched/persisted **by name** (e.g. `Lumina Camera - Raw`,
`HUAWEI FreeClip 2`) and resolved to a live `AudioDeviceID` at switch time, so
config survives reconnects and ID changes.

## State Machine

```
            managed output becomes active
   Idle  ───────────────────────────────────►  Active(device)
    ▲                                              │
    │   active output no longer managed            │ on input change to headset mic
    └──────────────────────────────────────────────┘ → re-assert priority mic
```

- **Idle:** no managed device active; app does not touch input.
- **Active(device):** a managed device is the active output; input is held to
  the highest-priority available mic from the list.

When entering Active, the app records the previous input device. (Restore on
exit is best-effort; primary behavior is simply to stop enforcing.)

## Mic Priority / Fallback

Ordered list, default: `Lumina Camera - Raw` → `PlumDog Microphone` →
`EarPods Microphone`. At switch time, pick the first one currently present.
If none are present, leave input unchanged (do not fall back to the headset).
The list is user-editable and reorderable in the menu.

## Menu-bar UI

`NSStatusItem` menu:

- **Status line** — e.g. `✅ HUAWEI FreeClip 2 → Lumina Camera - Raw` / `Idle` /
  `⏸ Paused`.
- **Managed Bluetooth devices** — checklist of detected Bluetooth output
  devices; checked = managed. AirPods entries shown disabled with an
  "(auto-excluded)" note.
- **Mic priority** — ordered fallback list with reorder + add/remove.
- **Pause / Resume** — temporarily stop all switching.
- **Fix input now** — manually apply the current rule on demand.
- **Launch at login** — toggle via `SMAppService`.
- **Quit**.

## Persistence

All settings stored in `UserDefaults` and restored on launch:

- Managed device names (set).
- Mic priority list (ordered array).
- Paused state.
- Launch-at-login preference.

## Components / Boundaries

- **`AudioDeviceManager`** — wraps CoreAudio: enumerate devices, read
  transport type + name, get/set default input/output, and register property
  listeners. Knows nothing about UI or policy. Testable against CoreAudio.
- **`RoutingPolicy`** — pure logic: given (active output device, device list,
  managed set, priority list, paused) → decide the desired input device (or
  "leave alone"). No CoreAudio/UI dependency; unit-testable in isolation.
- **`Settings`** — typed wrapper over `UserDefaults` (managed set, priority,
  paused, login).
- **`StatusMenuController`** — builds/refreshes the `NSStatusItem` menu, binds
  user actions to `Settings` + `AudioDeviceManager`, renders status.
- **`AppDelegate`** — wires listeners → `RoutingPolicy` → `AudioDeviceManager`,
  owns lifecycle.

## Error Handling

- CoreAudio calls return `OSStatus`; non-zero is logged (os_log) and the
  operation is skipped — never crash on a transient device error.
- Target device disappeared between decision and switch → re-resolve; if gone,
  fall to next priority mic.
- Listener storms (rapid connect/disconnect) → coalesce via a short debounce
  before acting.

## Testing

- **`RoutingPolicy`** unit tests: managed active → Lumina; managed active but
  Lumina absent → PlumDog; no managed active → leave alone; paused → leave
  alone; AirPods active → leave alone.
- **`AudioDeviceManager`** integration test (manual/CI-optional): enumerate
  real devices, assert transport-type classification and name lookup.
- **Manual acceptance:** connect Huawei → confirm input flips to Lumina and
  output stays full-quality; disconnect Lumina → confirm fallback; switch
  output to speakers → confirm app goes Idle; AirPods → confirm untouched;
  relaunch → confirm settings restored.

## Distribution

- Local unsigned build run from `~/Developer/bluetooth-mic-router` is sufficient
  for personal use. Login-at-launch via `SMAppService`.
- Microphone/automation entitlements: setting the *default input device* does
  not require mic-content access, so no TCC microphone prompt is expected;
  verified during implementation.
