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

    // MARK: - Dependencies

    private let settings: Settings
    private let onChange: () -> Void
    private let fixNowAction: () -> Void

    // MARK: - Init

    init(settings: Settings, onChange: @escaping () -> Void, fixNow: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        self.fixNowAction = fixNow
        self.loginEnabled = LoginItem.isEnabled
    }

    // MARK: - Refresh (called by AppDelegate to push fresh live state)

    func refresh(
        devices: [AudioDeviceInfo],
        activeOutputName: String?,
        activeInputName: String?,
        activeInputSampleRateKHz: Int?,
        routingActive: Bool,
        meetingActive: Bool,
        meetingSince: Date?
    ) {
        self.devices = devices
        self.activeOutputName = activeOutputName
        self.activeInputName = activeInputName
        self.activeInputSampleRateKHz = activeInputSampleRateKHz
        self.routingActive = routingActive
        self.meetingActive = meetingActive
        self.meetingSince = meetingSince
        self.paused = settings.paused
        self.loginEnabled = LoginItem.isEnabled
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
