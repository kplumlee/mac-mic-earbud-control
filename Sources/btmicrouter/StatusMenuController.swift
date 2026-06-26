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

        let header = disabledItem(statusLine(devices: devices))
        menu.addItem(header)
        menu.addItem(.separator())

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
                item.state = settings.managedNames.contains(dev.name) ? .on : .off
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        menu.addItem(disabledItem("Mic priority"))
        for (idx, mic) in settings.micPriority.enumerated() {
            let present = devices.contains { $0.name == mic && $0.hasInput }
            let mark = present ? "●" : "○"
            menu.addItem(disabledItem("  \(idx + 1). \(mark) \(mic)"))
        }
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

    private func updateIcon(devices: [AudioDeviceInfo]) {
        if settings.paused {
            statusItem.button?.title = "⏸"
        } else if isRoutingActive(devices: devices) {
            statusItem.button?.title = "🎙️✅"
        } else {
            statusItem.button?.title = "🎙️"
        }
    }

    private func isRoutingActive(devices: [AudioDeviceInfo]) -> Bool {
        guard let outID = manager.defaultOutputDevice(),
              let out = devices.first(where: { $0.id == outID }) else { return false }
        let decision = RoutingPolicy.decide(
            activeOutput: out, devices: devices,
            managedNames: settings.managedNames,
            micPriority: settings.micPriority, paused: settings.paused)
        if case .setInput = decision { return true }
        return false
    }

    private func statusLine(devices: [AudioDeviceInfo]) -> String {
        if settings.paused { return "⏸ Paused" }
        guard let outID = manager.defaultOutputDevice(),
              let out = devices.first(where: { $0.id == outID }) else { return "Idle" }
        guard out.transport == .bluetooth, !isAirPods(out.name),
              settings.managedNames.contains(out.name) else { return "Idle" }
        for mic in settings.micPriority where devices.contains(where: { $0.name == mic && $0.hasInput }) {
            return "✅ \(out.name) → \(mic)"
        }
        return "⚠️ \(out.name): no fallback mic available"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleManaged(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var managed = settings.managedNames
        if managed.contains(name) { managed.remove(name) } else { managed.insert(name) }
        settings.managedNames = managed
        onUserChange()
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
