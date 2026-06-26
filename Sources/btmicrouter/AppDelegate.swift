import AppKit
import os
import RoutingCore

private let appLog = Logger(subsystem: "com.kplumlee.btmicrouter", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = AudioDeviceManager()
    private let settings = Settings()
    private var menuController: StatusMenuController!
    private var debounceItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = StatusMenuController(
            settings: settings,
            manager: manager,
            onUserChange: { [weak self] in self?.apply() },
            onFixNow: { [weak self] in self?.apply() })
        manager.startListening { [weak self] in self?.scheduleApply() }
        apply()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopListening()
    }

    /// Coalesce listener storms (rapid connect/disconnect) before acting.
    private func scheduleApply() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.apply() }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func apply() {
        let devices = manager.allDevices()
        let activeOutput = manager.defaultOutputDevice().flatMap { id in
            devices.first { $0.id == id }
        }
        let decision = RoutingPolicy.decide(
            activeOutput: activeOutput,
            devices: devices,
            managedNames: settings.managedNames,
            micPriority: settings.micPriority,
            paused: settings.paused)

        switch decision {
        case .leaveAlone:
            break
        case .setInput(let id):
            if manager.defaultInputDevice() != id {
                let success = manager.setDefaultInputDevice(id)
                if !success {
                    appLog.error("Failed to set default input device id=\(id, privacy: .public)")
                }
            }
        }
        menuController.refreshMenu(devices: devices)
    }
}
