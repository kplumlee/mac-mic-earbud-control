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

        // Status line / quality readout (no action — disabled header)
        menu.addItem(disabledItem(statusLine(devices: devices)))
        menu.addItem(.separator())

        // Managed Bluetooth devices section
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
                item.state = settings.profile(for: dev.name).managed ? .on : .off
                menu.addItem(item)
            }
        }

        // Per-device priority editor — one submenu per managed non-AirPods BT device
        for dev in bluetooth where !isAirPods(dev.name) && settings.profile(for: dev.name).managed {
            let profile = settings.profile(for: dev.name)
            let subMenuItem = NSMenuItem(title: "  ⚙︎ \(dev.name) — mic priority",
                                          action: nil, keyEquivalent: "")
            let subMenu = NSMenu(title: "")

            let priority = profile.micPriority
            for (idx, mic) in priority.enumerated() {
                let present = devices.contains { $0.name == mic && $0.hasInput }
                let mark = present ? "●" : "○"
                // Disabled label item — submenu still appears on hover
                let micItem = NSMenuItem(title: "\(idx + 1). \(mark) \(mic)",
                                          action: nil, keyEquivalent: "")
                let micSubMenu = NSMenu(title: "")

                if idx > 0 {
                    let moveUp = NSMenuItem(title: "Move Up",
                                            action: #selector(moveMicUp(_:)), keyEquivalent: "")
                    moveUp.target = self
                    moveUp.representedObject = ["device": dev.name, "mic": mic] as [String: String]
                    micSubMenu.addItem(moveUp)
                }

                if idx < priority.count - 1 {
                    let moveDown = NSMenuItem(title: "Move Down",
                                              action: #selector(moveMicDown(_:)), keyEquivalent: "")
                    moveDown.target = self
                    moveDown.representedObject = ["device": dev.name, "mic": mic] as [String: String]
                    micSubMenu.addItem(moveDown)
                }

                // Separator before Remove only when there is at least one Move item
                if idx > 0 || idx < priority.count - 1 {
                    micSubMenu.addItem(.separator())
                }

                let remove = NSMenuItem(title: "Remove",
                                         action: #selector(removeMic(_:)), keyEquivalent: "")
                remove.target = self
                remove.representedObject = ["device": dev.name, "mic": mic] as [String: String]
                micSubMenu.addItem(remove)

                micItem.submenu = micSubMenu
                subMenu.addItem(micItem)
            }

            // "Add input device" submenu — lists present inputs not already in this device's priority
            let addParent = NSMenuItem(title: "Add input device", action: nil, keyEquivalent: "")
            let addSubMenu = NSMenu(title: "")

            let existingMics = Set(priority)
            var seen = Set<String>()
            let availableInputs = devices
                .filter { $0.hasInput && !existingMics.contains($0.name) }
                .compactMap { d -> String? in
                    guard !seen.contains(d.name) else { return nil }
                    seen.insert(d.name)
                    return d.name
                }
                .sorted()

            if availableInputs.isEmpty {
                addSubMenu.addItem(disabledItem("  (none available)"))
            } else {
                for inputName in availableInputs {
                    let addMicItem = NSMenuItem(title: inputName,
                                                action: #selector(addMic(_:)), keyEquivalent: "")
                    addMicItem.target = self
                    addMicItem.representedObject = ["device": dev.name, "mic": inputName] as [String: String]
                    addSubMenu.addItem(addMicItem)
                }
            }
            addParent.submenu = addSubMenu
            subMenu.addItem(.separator())
            subMenu.addItem(addParent)

            subMenuItem.submenu = subMenu
            menu.addItem(subMenuItem)
        }

        menu.addItem(.separator())

        // Per-app rules section
        let callAppsOnlyItem = NSMenuItem(title: "Only switch for call apps",
                                           action: #selector(toggleCallAppsOnly), keyEquivalent: "")
        callAppsOnlyItem.target = self
        callAppsOnlyItem.state = settings.callAppsOnly ? .on : .off
        menu.addItem(callAppsOnlyItem)

        let callAppsParent = NSMenuItem(title: "Call apps", action: nil, keyEquivalent: "")
        let callAppsSubMenu = NSMenu(title: "")

        for bundleID in settings.callApps {
            let appItem = NSMenuItem(title: bundleID,
                                     action: #selector(removeCallApp(_:)), keyEquivalent: "")
            appItem.target = self
            appItem.representedObject = bundleID
            appItem.state = .on
            callAppsSubMenu.addItem(appItem)
        }

        callAppsSubMenu.addItem(.separator())
        let addFrontmost = NSMenuItem(title: "Add frontmost app",
                                      action: #selector(addFrontmostApp), keyEquivalent: "")
        addFrontmost.target = self
        callAppsSubMenu.addItem(addFrontmost)

        callAppsParent.submenu = callAppsSubMenu
        menu.addItem(callAppsParent)

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

    // MARK: - Icon + status line

    private func updateIcon(devices: [AudioDeviceInfo]) {
        if settings.paused {
            statusItem.button?.title = "⏸"
        } else if isRoutingActive(devices: devices) {
            statusItem.button?.title = "🎙️✅"
        } else {
            statusItem.button?.title = "🎙️"
        }
    }

    /// Build a profiles dictionary from the currently-visible devices, deduping by first-seen name.
    private func buildProfiles(devices: [AudioDeviceInfo]) -> [String: DeviceProfile] {
        Dictionary(devices.map { ($0.name, settings.profile(for: $0.name)) },
                   uniquingKeysWith: { a, _ in a })
    }

    private func isRoutingActive(devices: [AudioDeviceInfo]) -> Bool {
        guard let outID = manager.defaultOutputDevice(),
              let out = devices.first(where: { $0.id == outID }) else { return false }
        let decision = RoutingPolicy.decide(
            activeOutput: out, devices: devices,
            profiles: buildProfiles(devices: devices),
            paused: settings.paused,
            frontmostBundleID: FrontmostApp.bundleID(),
            callAppsOnly: settings.callAppsOnly,
            callApps: settings.callApps)
        if case .setInput = decision { return true }
        return false
    }

    private func statusLine(devices: [AudioDeviceInfo]) -> String {
        if settings.paused { return "⏸ Paused" }
        guard let outID = manager.defaultOutputDevice(),
              let out = devices.first(where: { $0.id == outID }) else { return "Idle" }
        let decision = RoutingPolicy.decide(
            activeOutput: out, devices: devices,
            profiles: buildProfiles(devices: devices),
            paused: settings.paused,
            frontmostBundleID: FrontmostApp.bundleID(),
            callAppsOnly: settings.callAppsOnly,
            callApps: settings.callApps)
        switch decision {
        case .leaveAlone:
            return "Idle"
        case .setInput(let inputID):
            guard let inputDev = devices.first(where: { $0.id == inputID }) else { return "Idle" }
            if let rate = manager.nominalSampleRate(for: inputID) {
                let kHz = Int((rate / 1000).rounded())
                let icon = rate < 24000 ? "⚠️" : "✅"
                return "\(icon) \(out.name) → \(inputDev.name) (\(kHz) kHz)"
            }
            return "✅ \(out.name) → \(inputDev.name)"
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func toggleManaged(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var profile = settings.profile(for: name)
        profile.managed.toggle()
        settings.setProfile(profile, for: name)
        onUserChange()
    }

    @objc private func moveMicUp(_ sender: NSMenuItem) {
        guard let rep = sender.representedObject as? [String: String],
              let deviceName = rep["device"], let mic = rep["mic"] else { return }
        var profile = settings.profile(for: deviceName)
        guard let idx = profile.micPriority.firstIndex(of: mic), idx > 0 else { return }
        profile.micPriority.swapAt(idx, idx - 1)
        settings.setProfile(profile, for: deviceName)
        onUserChange()
    }

    @objc private func moveMicDown(_ sender: NSMenuItem) {
        guard let rep = sender.representedObject as? [String: String],
              let deviceName = rep["device"], let mic = rep["mic"] else { return }
        var profile = settings.profile(for: deviceName)
        guard let idx = profile.micPriority.firstIndex(of: mic),
              idx < profile.micPriority.count - 1 else { return }
        profile.micPriority.swapAt(idx, idx + 1)
        settings.setProfile(profile, for: deviceName)
        onUserChange()
    }

    @objc private func removeMic(_ sender: NSMenuItem) {
        guard let rep = sender.representedObject as? [String: String],
              let deviceName = rep["device"], let mic = rep["mic"] else { return }
        var profile = settings.profile(for: deviceName)
        profile.micPriority.removeAll { $0 == mic }
        settings.setProfile(profile, for: deviceName)
        onUserChange()
    }

    @objc private func addMic(_ sender: NSMenuItem) {
        guard let rep = sender.representedObject as? [String: String],
              let deviceName = rep["device"], let mic = rep["mic"] else { return }
        var profile = settings.profile(for: deviceName)
        if !profile.micPriority.contains(mic) {
            profile.micPriority.append(mic)
        }
        settings.setProfile(profile, for: deviceName)
        onUserChange()
    }

    @objc private func toggleCallAppsOnly() {
        settings.callAppsOnly.toggle()
        onUserChange()
    }

    @objc private func removeCallApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        var apps = settings.callApps
        apps.removeAll { $0 == bundleID }
        settings.callApps = apps
        onUserChange()
    }

    @objc private func addFrontmostApp() {
        guard let bundleID = FrontmostApp.bundleID() else { return }
        var apps = settings.callApps
        if !apps.contains(bundleID) {
            apps.append(bundleID)
            settings.callApps = apps
            onUserChange()
        }
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
