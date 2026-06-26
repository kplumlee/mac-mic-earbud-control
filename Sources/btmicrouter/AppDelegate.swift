import AppKit
import os
import UserNotifications
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
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(runningAppsChanged(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(runningAppsChanged(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil)
        setupNotifications()
        apply()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopListening()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func runningAppsChanged(_ note: Notification) {
        scheduleApply()
    }

    /// Coalesce listener storms (rapid connect/disconnect) before acting.
    private func scheduleApply() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.apply() }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func setupNotifications() {
        guard Bundle.main.bundleIdentifier != nil else {
            appLog.info("switch notifications disabled — no bundle identifier (run as .app to enable)")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                appLog.error("notification auth error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func notifySwitch(to micName: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Bluetooth Mic Router"
        content.body = "Mic → \(micName)"
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                appLog.error("notification post error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func apply() {
        let devices = manager.allDevices()
        let activeOutput = manager.defaultOutputDevice().flatMap { id in
            devices.first { $0.id == id }
        }
        let decision = RoutingPolicy.decide(
            activeOutput: activeOutput,
            devices: devices,
            profiles: settings.profiles,
            paused: settings.paused,
            runningBundleIDs: RunningApps.bundleIDs(),
            callAppsOnly: settings.callAppsOnly,
            callApps: settings.callApps)

        switch decision {
        case .leaveAlone:
            break
        case .setInput(let id):
            if manager.defaultInputDevice() != id {
                let success = manager.setDefaultInputDevice(id)
                if success {
                    let name = devices.first { $0.id == id }?.name ?? "unknown"
                    notifySwitch(to: name)
                } else {
                    appLog.error("Failed to set default input device id=\(id, privacy: .public)")
                }
            }
        }
        menuController.refreshMenu(devices: devices)
    }
}
