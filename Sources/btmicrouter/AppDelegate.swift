import AppKit
import Carbon.HIToolbox
import os
import UserNotifications
import RoutingCore

private let appLog = Logger(subsystem: "com.kplumlee.btmicrouter", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = AudioDeviceManager()
    private let settings = Settings()
    private var model: AppModel!
    private var statusItemController: StatusItemController!
    private var debounceItem: DispatchWorkItem?

    // Meeting coordinator state
    private var meetingTimer: Timer?
    private var meetingActive = false
    private var meetingStartedAt: Date?
    private var didPauseMusic = false

    // Mute hotkey
    private var muteHotKey: GlobalHotKey?

    // Calendar pre-launch state
    private let calendar = CalendarService()
    private var lastPrelaunchedStart: Date?
    private var calendarAccessGranted = false

    // Output management state
    // Seeded in applicationDidFinishLaunching before the first apply() so the
    // "appeared" diff on the very first run is empty — preventing us from
    // hijacking the output at launch.
    private var previousDevices: [AudioDeviceInfo] = []
    private var previousDefaultOutputName: String?

    // Calendar throttle
    private var calendarTickCounter = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            model = AppModel(
                settings: settings,
                onChange: { [weak self] in self?.apply() },
                fixNow: { [weak self] in self?.apply() },
                muteAction: { [weak self] in self?.toggleMute() })
            statusItemController = StatusItemController(model: model)
        }
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
        // Seed previousDevices before the first apply() so the "appeared"
        // diff on launch is empty and we don't hijack the current output.
        previousDevices = manager.allDevices()
        previousDefaultOutputName = manager.defaultOutputDevice().flatMap { id in previousDevices.first { $0.id == id }?.name }
        updateMuteHotKeyRegistration()
        apply()

        meetingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.evaluateMeeting()
            self.pushState()
            // Throttle the synchronous EventKit query to ~30 s (every 15th tick).
            self.calendarTickCounter += 1
            if self.calendarTickCounter % 15 == 0 {
                self.checkCalendar()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if didPauseMusic { setMusicPlaying(true); didPauseMusic = false }
        meetingTimer?.invalidate()
        muteHotKey?.unregister()
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
        manageOutput(devices: devices)
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
        pushState()
        updateMuteHotKeyRegistration()
        requestCalendarAccessIfNeeded()
    }

    /// Diff the current device list against the previous one and apply output
    /// switching rules. Called on every debounced device-change via apply().
    ///
    /// Launch guard: previousDevices is seeded in applicationDidFinishLaunching
    /// before the first apply(), so the "appeared" set on the first run is empty
    /// and we never hijack output at startup.
    ///
    /// Tracking (previousDevices, previousDefaultOutputName) is always updated so
    /// diffs stay correct even while paused. Side-effecting switches and
    /// auto-manage are gated behind !settings.paused (Fix 5).
    private func manageOutput(devices: [AudioDeviceInfo]) {
        let currentNames = Set(devices.map { $0.name })
        let previousNames = Set(previousDevices.map { $0.name })
        let appeared = currentNames.subtracting(previousNames)
        let disappeared = previousNames.subtracting(currentNames)

        if !settings.paused {
            // Fix 3: Auto-manage newly-connected Bluetooth headsets with no stored
            // profile. Creates managed=true so mic routing works out of the box; a
            // later user-set unmanaged profile is never overwritten (we only create
            // when profiles[name] == nil).
            for dev in devices where appeared.contains(dev.name)
                    && dev.transport == .bluetooth
                    && dev.hasOutput
                    && !isAirPods(dev.name)
                    && settings.profiles[dev.name] == nil {
                settings.setProfile(DeviceProfile(managed: true, micPriority: []), for: dev.name)
                appLog.info("auto-managed new BT device: \(dev.name, privacy: .public)")
            }

            // A Bluetooth headphone connected -> make it the output.
            if settings.autoSwitchOutputToBluetooth,
               let dev = devices.first(where: {
                   appeared.contains($0.name) && $0.transport == .bluetooth && $0.hasOutput && !isAirPods($0.name)
               }) {
                _ = manager.setDefaultOutputDevice(dev.id)
                appLog.info("output → \(dev.name, privacy: .public) (BT connect)")
            }

            // Fix 4: Only fall back when the device we were ACTUALLY outputting to
            // (a BT output) just disconnected — not when any idle BT device leaves.
            if let prevOut = previousDefaultOutputName,
               disappeared.contains(prevOut),
               previousDevices.contains(where: {
                   $0.name == prevOut && $0.transport == .bluetooth && $0.hasOutput && !isAirPods($0.name)
               }),
               let preferred = settings.preferredOutputName,
               let target = devices.first(where: { $0.name == preferred && $0.hasOutput }),
               manager.defaultOutputDevice() != target.id {
                _ = manager.setDefaultOutputDevice(target.id)
                appLog.info("output → \(target.name, privacy: .public) (BT disconnect fallback)")
            }
        }

        // Always update tracking so diffs are correct on the next call.
        previousDevices = devices
        previousDefaultOutputName = manager.defaultOutputDevice().flatMap { id in devices.first { $0.id == id }?.name }
    }

    private func pushState() {
        let devices = manager.allDevices()
        let outName = manager.defaultOutputDevice().flatMap { id in devices.first { $0.id == id }?.name }
        let inID = manager.defaultInputDevice()
        let inName = inID.flatMap { id in devices.first { $0.id == id }?.name }
        let kHz = inID.flatMap { manager.nominalSampleRate(for: $0) }.map { Int(($0 / 1000).rounded()) }
        let activeOutput = manager.defaultOutputDevice().flatMap { id in devices.first { $0.id == id } }
        let decision = RoutingPolicy.decide(
            activeOutput: activeOutput,
            devices: devices,
            profiles: settings.profiles,
            paused: settings.paused,
            runningBundleIDs: RunningApps.bundleIDs(),
            callAppsOnly: settings.callAppsOnly,
            callApps: settings.callApps)
        var routing = false
        if case .setInput = decision { routing = true }
        let met = meetingActive
        let since = meetingStartedAt
        let paused = settings.paused
        let muted = manager.isInputMuted()
        let micHot = manager.isDefaultInputInUse()
        MainActor.assumeIsolated {
            model.refresh(
                devices: devices,
                activeOutputName: outName,
                activeInputName: inName,
                activeInputSampleRateKHz: kHz,
                routingActive: routing,
                meetingActive: met,
                meetingSince: since,
                inputMuted: muted,
                micInUse: micHot)
            statusItemController.updateIcon(meeting: met, routing: routing, paused: paused, muted: muted, micHot: micHot)
        }
    }

    // MARK: - Calendar

    private func requestCalendarAccessIfNeeded() {
        guard settings.calendarPrelaunchEnabled, !calendarAccessGranted else { return }
        calendar.requestAccess { [weak self] granted in
            DispatchQueue.main.async {
                self?.calendarAccessGranted = granted
                self?.pushState()
                // Query immediately so the next meeting shows up right away.
                if granted { self?.checkCalendar() }
            }
        }
    }

    private func checkCalendar() {
        guard settings.calendarPrelaunchEnabled, calendarAccessGranted else {
            MainActor.assumeIsolated {
                model.setNextMeeting(title: nil, start: nil, joinURL: nil)
            }
            return
        }
        let meeting = calendar.nextMeeting(within: 12)
        MainActor.assumeIsolated {
            model.setNextMeeting(
                title: meeting?.title,
                start: meeting?.start,
                joinURL: meeting?.joinURL)
        }
        guard let meeting = meeting else { return }
        let timeUntil = meeting.start.timeIntervalSinceNow
        guard timeUntil <= Double(settings.calendarLeadMinutes) * 60,
              timeUntil > -60,
              lastPrelaunchedStart != meeting.start else { return }
        lastPrelaunchedStart = meeting.start
        for name in settings.launchAppsOnMeeting {
            launchApp(name)
        }
        if let url = meeting.joinURL {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Mute

    private func toggleMute() {
        manager.setInputMuted(!manager.isInputMuted())
        pushState()
    }

    private func updateMuteHotKeyRegistration() {
        if settings.muteHotkeyEnabled && muteHotKey == nil {
            muteHotKey = GlobalHotKey(
                keyCode: 46,
                modifiers: UInt32(cmdKey | optionKey | controlKey)
            ) { [weak self] in self?.toggleMute() }
        } else if !settings.muteHotkeyEnabled && muteHotKey != nil {
            muteHotKey?.unregister()
            muteHotKey = nil
        }
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
        pushState()
        appLog.info("meeting started")
    }

    private func meetingDidEnd() {
        meetingActive = false
        meetingStartedAt = nil

        if didPauseMusic {
            setMusicPlaying(true)
            didPauseMusic = false
        }

        pushState()
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
