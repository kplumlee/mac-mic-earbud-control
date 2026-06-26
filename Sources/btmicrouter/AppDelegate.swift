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

    // Meeting coordinator state
    private var meetingTimer: Timer?
    private var meetingActive = false
    private var meetingStartedAt: Date?
    private var didPauseMusic = false

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

        meetingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.evaluateMeeting()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if didPauseMusic { setMusicPlaying(true); didPauseMusic = false }
        meetingTimer?.invalidate()
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

    // MARK: - Meeting Coordinator

    private func evaluateMeeting() {
        let active = settings.meetingAutomationEnabled
            && MeetingPolicy.isMeetingActive(
                runningBundleIDs: RunningApps.bundleIDs(),
                meetingApps: settings.callApps,
                micInUse: manager.isDefaultInputInUse())
        if active && !meetingActive {
            meetingDidStart()
        } else if !active && meetingActive {
            meetingDidEnd()
        }
    }

    private func meetingDidStart() {
        meetingActive = true
        meetingStartedAt = Date()

        for name in settings.launchAppsOnMeeting {
            launchApp(name)
        }

        if settings.pauseMusicOnMeeting {
            didPauseMusic = setMusicPlaying(false)
        }

        postMeetingNotification(launched: settings.launchAppsOnMeeting)
        if settings.recordReminderEnabled {
            postRecordReminder()
        }
        menuController.updateMeeting(active: true, since: meetingStartedAt)
        appLog.info("meeting started")
    }

    private func meetingDidEnd() {
        meetingActive = false
        meetingStartedAt = nil

        if didPauseMusic {
            setMusicPlaying(true)
            didPauseMusic = false
        }

        menuController.updateMeeting(active: false, since: nil)
        appLog.info("meeting ended")
    }

    private func launchApp(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-a", name]
        do {
            try process.run()
        } catch {
            appLog.error("launchApp failed for \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Execute an AppleScript snippet, logging any automation errors.
    private func runAppleScript(_ source: String) {
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err = err {
            appLog.error("AppleScript error: \(String(describing: err), privacy: .public)")
        }
    }

    /// Returns true iff the named music app reports its player state as "playing".
    private func musicIsPlaying(_ appName: String) -> Bool {
        let source = "tell application \"\(appName)\" to player state as string"
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err = err {
            appLog.error("AppleScript error: \(String(describing: err), privacy: .public)")
            return false
        }
        return result?.stringValue == "playing"
    }

    @discardableResult
    private func setMusicPlaying(_ playing: Bool) -> Bool {
        let apps: [(bundleID: String, appName: String)] = [
            ("com.spotify.client", "Spotify"),
            ("com.apple.Music", "Music")
        ]
        let running = RunningApps.bundleIDs()
        var dispatched = false
        for (bundleID, appName) in apps {
            guard running.contains(bundleID) else { continue }
            if playing {
                runAppleScript("tell application \"\(appName)\" to play")
                dispatched = true
            } else if musicIsPlaying(appName) {
                runAppleScript("tell application \"\(appName)\" to pause")
                dispatched = true
            }
        }
        return dispatched
    }

    private func postRecordReminder() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "🔴 Meeting started"
        content.body = "Recording? Don't forget to hit record."
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                appLog.error("record reminder notification error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func postMeetingNotification(launched: [String]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting detected"
        content.body = launched.isEmpty
            ? "In a meeting"
            : "Launched \(launched.joined(separator: ", "))"
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                appLog.error("meeting notification error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
