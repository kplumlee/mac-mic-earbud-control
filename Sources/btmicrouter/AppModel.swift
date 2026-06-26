import Foundation
import Combine
import AppKit
import RoutingCore

@MainActor
final class AppModel: ObservableObject {

    // MARK: - Live state (pushed by AppDelegate via refresh)

    @Published var devices: [AudioDeviceInfo] = []
    @Published var activeOutputName: String?
    @Published var activeInputName: String?
    @Published var activeInputSampleRateKHz: Int?
    @Published var routingActive = false
    @Published var paused = false
    @Published var meetingActive = false
    @Published var meetingSince: Date?
    @Published var loginEnabled = false
    @Published var recordReminderDismissed = false
    @Published var inputMuted = false
    @Published var micInUse = false

    // MARK: - Calendar state (pushed by AppDelegate via setNextMeeting)

    @Published var nextMeetingTitle: String?
    @Published var nextMeetingStart: Date?
    @Published var nextMeetingHasLink: Bool = false
    private var nextMeetingJoinURL: URL?

    // MARK: - Dependencies

    private let settings: Settings
    private let onChange: () -> Void
    private let fixNowAction: () -> Void
    private let muteAction: () -> Void

    // MARK: - Init

    init(settings: Settings, onChange: @escaping () -> Void, fixNow: @escaping () -> Void, muteAction: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        self.fixNowAction = fixNow
        self.muteAction = muteAction
        self.loginEnabled = LoginItem.isEnabled
        self.paused = settings.paused
    }

    // MARK: - Refresh (called by AppDelegate to push fresh live state)

    func refresh(
        devices: [AudioDeviceInfo],
        activeOutputName: String?,
        activeInputName: String?,
        activeInputSampleRateKHz: Int?,
        routingActive: Bool,
        meetingActive: Bool,
        meetingSince: Date?,
        inputMuted: Bool,
        micInUse: Bool
    ) {
        self.devices = devices
        self.activeOutputName = activeOutputName
        self.activeInputName = activeInputName
        self.activeInputSampleRateKHz = activeInputSampleRateKHz
        self.routingActive = routingActive
        // Reset dismiss flag each time a new meeting starts (inactive → active).
        if meetingActive && !self.meetingActive {
            recordReminderDismissed = false
        }
        self.meetingActive = meetingActive
        self.meetingSince = meetingSince
        self.paused = settings.paused
        self.loginEnabled = LoginItem.isEnabled
        self.inputMuted = inputMuted
        self.micInUse = micInUse
    }

    // MARK: - Mute hotkey

    var muteHotkeyEnabled: Bool {
        get { settings.muteHotkeyEnabled }
        set { settings.muteHotkeyEnabled = newValue; onChange() }
    }

    func toggleMute() {
        muteAction()
    }

    // MARK: - Device helpers

    var bluetoothDevices: [AudioDeviceInfo] {
        devices.filter { $0.transport == .bluetooth && $0.hasOutput }
    }

    func isAirPodsDevice(_ name: String) -> Bool {
        isAirPods(name)
    }

    func isManaged(_ name: String) -> Bool {
        settings.profile(for: name).managed
    }

    func setManaged(_ name: String, _ on: Bool) {
        var profile = settings.profile(for: name)
        profile.managed = on
        settings.setProfile(profile, for: name)
        onChange()
    }

    func micPriority(for name: String) -> [String] {
        let p = settings.profile(for: name).micPriority
        return p.isEmpty ? Settings.defaultPriority : p
    }

    func moveMic(for name: String, fromOffsets: IndexSet, toOffset: Int) {
        var profile = settings.profile(for: name)
        var list = profile.micPriority.isEmpty ? Settings.defaultPriority : profile.micPriority
        // Replicate SwiftUI List.onMove semantics using only stdlib.
        let moving = fromOffsets.map { list[$0] }
        // Remove from highest index to lowest to keep indices stable.
        for idx in fromOffsets.reversed() { list.remove(at: idx) }
        let adjustedDestination = toOffset - fromOffsets.filter { $0 < toOffset }.count
        let insertAt = min(adjustedDestination, list.endIndex)
        list.insert(contentsOf: moving, at: insertAt)
        profile.micPriority = list
        settings.setProfile(profile, for: name)
        onChange()
    }

    func removeMic(for name: String, _ mic: String) {
        var profile = settings.profile(for: name)
        var list = profile.micPriority.isEmpty ? Settings.defaultPriority : profile.micPriority
        list.removeAll { $0 == mic }
        profile.micPriority = list
        settings.setProfile(profile, for: name)
        onChange()
    }

    func addMic(for name: String, _ mic: String) {
        var profile = settings.profile(for: name)
        var list = profile.micPriority.isEmpty ? Settings.defaultPriority : profile.micPriority
        if !list.contains(mic) {
            list.append(mic)
        }
        profile.micPriority = list
        settings.setProfile(profile, for: name)
        onChange()
    }

    /// Input device names not already in the given device's priority list.
    func addableInputs(for name: String) -> [String] {
        let current = Set(micPriority(for: name))
        var seen = Set<String>()
        var result: [String] = []
        for device in devices where device.hasInput {
            let n = device.name
            guard !current.contains(n), seen.insert(n).inserted else { continue }
            result.append(n)
        }
        return result.sorted()
    }

    // MARK: - Output settings

    var autoSwitchOutputToBluetooth: Bool {
        get { settings.autoSwitchOutputToBluetooth }
        set { settings.autoSwitchOutputToBluetooth = newValue; onChange() }
    }

    var preferredOutputName: String? {
        get { settings.preferredOutputName }
        set { settings.preferredOutputName = newValue; onChange() }
    }

    /// Deduped, sorted names of all current devices that have an output stream.
    func outputDeviceNames() -> [String] {
        var seen = Set<String>()
        return devices.filter { $0.hasOutput }.compactMap { device in
            seen.insert(device.name).inserted ? device.name : nil
        }.sorted()
    }

    // MARK: - Call-app settings

    var callAppsOnly: Bool {
        get { settings.callAppsOnly }
        set { settings.callAppsOnly = newValue; onChange() }
    }

    var callApps: [String] {
        settings.callApps
    }

    func removeCallApp(_ id: String) {
        settings.callApps = settings.callApps.filter { $0 != id }
        onChange()
    }

    func addFrontmostCallApp() {
        guard let id = FrontmostApp.bundleID() else { return }
        guard !settings.callApps.contains(id) else { return }
        settings.callApps = settings.callApps + [id]
        onChange()
    }

    // MARK: - Meeting automation

    var meetingAutomationEnabled: Bool {
        get { settings.meetingAutomationEnabled }
        set { settings.meetingAutomationEnabled = newValue; onChange() }
    }

    var pauseMusicOnMeeting: Bool {
        get { settings.pauseMusicOnMeeting }
        set { settings.pauseMusicOnMeeting = newValue; onChange() }
    }

    var recordReminderEnabled: Bool {
        get { settings.recordReminderEnabled }
        set { settings.recordReminderEnabled = newValue; onChange() }
    }

    var launchAppsOnMeeting: [String] {
        settings.launchAppsOnMeeting
    }

    func removeLaunchApp(_ app: String) {
        settings.launchAppsOnMeeting = settings.launchAppsOnMeeting.filter { $0 != app }
        onChange()
    }

    func addLaunchApp(_ app: String) {
        guard !settings.launchAppsOnMeeting.contains(app) else { return }
        settings.launchAppsOnMeeting = settings.launchAppsOnMeeting + [app]
        onChange()
    }

    // MARK: - Calendar pre-launch settings

    var calendarPrelaunchEnabled: Bool {
        get { settings.calendarPrelaunchEnabled }
        set { settings.calendarPrelaunchEnabled = newValue; onChange() }
    }

    var calendarLeadMinutes: Int {
        get { settings.calendarLeadMinutes }
        set { settings.calendarLeadMinutes = max(0, newValue); onChange() }
    }

    func setNextMeeting(title: String?, start: Date?, joinURL: URL?) {
        nextMeetingTitle = title
        nextMeetingStart = start
        nextMeetingHasLink = (joinURL != nil)
        nextMeetingJoinURL = joinURL
    }

    func openNextMeeting() {
        guard let url = nextMeetingJoinURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Deduped, sorted localized names of all running applications.
    func runningAppNames() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName,
                  seen.insert(name).inserted else { continue }
            result.append(name)
        }
        return result.sorted()
    }

    // MARK: - Intents

    func togglePaused() {
        settings.paused.toggle()
        self.paused = settings.paused
        onChange()
    }

    func fixNow() {
        fixNowAction()
    }

    func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        loginEnabled = LoginItem.isEnabled
        onChange()
    }

    func dismissRecordReminder() {
        recordReminderDismissed = true
    }

    // MARK: - Display helpers

    /// Returns a human-readable application name for the given bundle ID.
    /// Resolves via NSWorkspace → FileManager displayName; falls back to the raw ID.
    func displayName(forBundleID id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return id
        }
        let raw = FileManager.default.displayName(atPath: url.path)
        // Strip the ".app" suffix that displayName sometimes returns.
        return raw.hasSuffix(".app") ? String(raw.dropLast(4)) : raw
    }

    func openGranola() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Granola"]
        try? proc.run()
    }

    func openZoomAutoRecordHelp() {
        NSWorkspace.shared.open(
            URL(string: "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067954")!
        )
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
