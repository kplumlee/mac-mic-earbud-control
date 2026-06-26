import SwiftUI
import RoutingCore

// MARK: - Root View

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                StatusHeader(model: model)

                if model.meetingActive && model.recordReminderEnabled && !model.recordReminderDismissed {
                    RecordingReminderBanner(model: model)
                }

                DevicesSection(model: model)
                OutputSection(model: model)
                MeetingAutomationSection(model: model)
                CallAppsSection(model: model)
                FooterSection(model: model)
            }
            .padding(12)
        }
        .frame(width: 360)
        .frame(maxHeight: 560)
    }
}

// MARK: - Section Card

struct SectionCard<Content: View>: View {
    let title: String?
    let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Toggle Row

private struct ToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.accentColor)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Sample Rate Pill

private struct SampleRatePill: View {
    let khz: Int
    var isGood: Bool { khz >= 24 }

    var body: some View {
        HStack(spacing: 3) {
            if !isGood {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .symbolRenderingMode(.hierarchical)
            }
            Text("\(khz) kHz")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(isGood ? Color.green : Color.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill((isGood ? Color.green : Color.orange).opacity(0.12))
        )
    }
}

// MARK: - Status Header

private struct StatusHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard {
            HStack(alignment: .top, spacing: 12) {
                statusIcon
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    statusTitle
                    statusSubtitle
                }

                Spacer()

                VStack(spacing: 6) {
                    Button(model.paused ? "Resume" : "Pause") {
                        model.togglePaused()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if model.routingActive || model.meetingActive {
                        Button("Fix now") {
                            model.fixNow()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if model.meetingActive {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red)
                .symbolRenderingMode(.hierarchical)
        } else if model.routingActive {
            Image(systemName: "mic.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
        } else {
            Image(systemName: "mic.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
    }

    @ViewBuilder
    private var statusTitle: some View {
        if model.meetingActive {
            Text("In a meeting")
                .font(.headline)
                .foregroundStyle(.red)
        } else if model.routingActive {
            Text(model.activeInputName ?? "Unknown mic")
                .font(.headline)
        } else {
            Text("Idle")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        if model.meetingActive {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(elapsedString(since: model.meetingSince))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        } else if model.routingActive {
            HStack(spacing: 6) {
                if let output = model.activeOutputName {
                    Text("from \(output)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let khz = model.activeInputSampleRateKHz {
                    SampleRatePill(khz: khz)
                }
            }
        }
    }

    private func elapsedString(since date: Date?) -> String {
        let total = Int(max(0, Date().timeIntervalSince(date ?? .now)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Recording Reminder Banner

private struct RecordingReminderBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .symbolRenderingMode(.hierarchical)

            Text("Recording? Don't forget to hit record.")
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Open Granola") {
                model.openGranola()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)

            Button("Got it") {
                model.dismissRecordReminder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Devices Section

private struct DevicesSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard(title: "Bluetooth Output Devices") {
            let devices = model.bluetoothDevices
            if devices.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .foregroundStyle(.tertiary)
                    Text("No Bluetooth devices connected")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.name) { idx, device in
                        DeviceRow(model: model, device: device)
                        if idx < devices.count - 1 {
                            Divider().padding(.leading, 28)
                        }
                    }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    @ObservedObject var model: AppModel
    let device: AudioDeviceInfo

    private var isAirPods: Bool { model.isAirPodsDevice(device.name) }
    private var isManaged: Bool { model.isManaged(device.name) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.subheadline)
                    .foregroundStyle(isAirPods ? .tertiary : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.subheadline)
                        .foregroundStyle(isAirPods ? .tertiary : .primary)
                        .lineLimit(1)
                    if isAirPods {
                        Text("auto-excluded")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if !isAirPods {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.isManaged(device.name) },
                            set: { model.setManaged(device.name, $0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(.accentColor)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 6)

            if !isAirPods && isManaged {
                MicPriorityEditor(model: model, deviceName: device.name)
                    .padding(.leading, 28)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Mic Priority Editor

private struct MicPriorityEditor: View {
    @ObservedObject var model: AppModel
    let deviceName: String

    private var mics: [String] { model.micPriority(for: deviceName) }
    private var addable: [String] { model.addableInputs(for: deviceName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mic priority")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 2) {
                ForEach(Array(mics.enumerated()), id: \.element) { index, mic in
                    MicPriorityRow(
                        model: model,
                        deviceName: deviceName,
                        mic: mic,
                        index: index,
                        total: mics.count
                    )
                }
            }

            if !addable.isEmpty {
                Menu {
                    ForEach(addable, id: \.self) { input in
                        Button(input) {
                            model.addMic(for: deviceName, input)
                        }
                    }
                } label: {
                    Label("Add input", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .fixedSize()
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct MicPriorityRow: View {
    @ObservedObject var model: AppModel
    let deviceName: String
    let mic: String
    let index: Int
    let total: Int

    private var isPresent: Bool {
        model.devices.contains { $0.name == mic && $0.hasInput }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isPresent ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(isPresent ? Color.green : Color.secondary)

            Text("\(index + 1).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
                .monospacedDigit()

            Text(mic)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    model.moveMic(for: deviceName,
                                  fromOffsets: IndexSet([index]),
                                  toOffset: index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    model.moveMic(for: deviceName,
                                  fromOffsets: IndexSet([index]),
                                  toOffset: index + 2)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(index == total - 1)

                Button {
                    model.removeMic(for: deviceName, mic)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Output Section

private struct OutputSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard(title: "Output") {
            VStack(spacing: 0) {
                ToggleRow(
                    icon: "hifispeaker",
                    label: "Always switch output to Bluetooth headphones on connect",
                    isOn: Binding(
                        get: { model.autoSwitchOutputToBluetooth },
                        set: { model.autoSwitchOutputToBluetooth = $0 }
                    )
                )

                Divider().padding(.leading, 28)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Text("When disconnected, switch back to:")
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Picker(
                        "",
                        selection: Binding<String?>(
                            get: { model.preferredOutputName },
                            set: { model.preferredOutputName = $0 }
                        )
                    ) {
                        Text("Leave to macOS").tag(String?(nil))
                        ForEach(model.outputDeviceNames(), id: \.self) { name in
                            Text(name).tag(String?(name))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Meeting Automation Section

private struct MeetingAutomationSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard(title: "Meeting Automation") {
            VStack(spacing: 0) {
                ToggleRow(
                    icon: "person.2.fill",
                    label: "Enable meeting automation",
                    isOn: Binding(
                        get: { model.meetingAutomationEnabled },
                        set: { model.meetingAutomationEnabled = $0 }
                    )
                )

                if model.meetingAutomationEnabled {
                    Divider().padding(.leading, 28)

                    ToggleRow(
                        icon: "music.note",
                        label: "Pause music in meetings",
                        isOn: Binding(
                            get: { model.pauseMusicOnMeeting },
                            set: { model.pauseMusicOnMeeting = $0 }
                        )
                    )

                    Divider().padding(.leading, 28)

                    ToggleRow(
                        icon: "bell.badge",
                        label: "Remind me to record",
                        isOn: Binding(
                            get: { model.recordReminderEnabled },
                            set: { model.recordReminderEnabled = $0 }
                        )
                    )

                    Divider().padding(.leading, 28)

                    LaunchAppsSubsection(model: model)

                    Divider().padding(.leading, 28)

                    ZoomHelpRow(model: model)
                }
            }
        }
    }
}

private struct LaunchAppsSubsection: View {
    @ObservedObject var model: AppModel

    private var addableApps: [String] {
        let current = Set(model.launchAppsOnMeeting)
        return model.runningAppNames().filter { !current.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text("Launch on meeting")
                    .font(.subheadline)

                Spacer()

                Menu {
                    if addableApps.isEmpty {
                        Text("No running apps to add")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(addableApps, id: \.self) { app in
                            Button(app) {
                                model.addLaunchApp(app)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .fixedSize()
            }
            .padding(.vertical, 6)

            ForEach(model.launchAppsOnMeeting, id: \.self) { app in
                HStack(spacing: 8) {
                    Spacer().frame(width: 28)
                    Text(app)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.removeLaunchApp(app)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ZoomHelpRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.right.square")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Button("Turn on Zoom auto-record\u{2026}") {
                    model.openZoomAutoRecordHelp()
                }
                .buttonStyle(.borderless)
                .font(.subheadline)

                Text("Opens Zoom\u{2019}s auto-record setting in your browser")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Call Apps Section

private struct CallAppsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard(title: "Per-App Rules") {
            VStack(spacing: 0) {
                ToggleRow(
                    icon: "app.badge",
                    label: "Only switch for call apps",
                    isOn: Binding(
                        get: { model.callAppsOnly },
                        set: { model.callAppsOnly = $0 }
                    )
                )

                if model.callAppsOnly {
                    Divider().padding(.leading, 28)

                    VStack(spacing: 0) {
                        ForEach(model.callApps, id: \.self) { app in
                            HStack(spacing: 8) {
                                Image(systemName: "app")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                Text(model.displayName(forBundleID: app))
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Button {
                                    model.removeCallApp(app)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            model.addFrontmostCallApp()
                        } label: {
                            Label("Add frontmost app", systemImage: "plus.circle")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

// MARK: - Footer Section

private struct FooterSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard {
            VStack(spacing: 0) {
                ToggleRow(
                    icon: "gearshape",
                    label: "Launch at login",
                    isOn: Binding(
                        get: { model.loginEnabled },
                        set: { _ in model.toggleLogin() }
                    )
                )

                Divider().padding(.leading, 28)

                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Button("Quit") {
                        model.quit()
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)

                    Spacer()

                    Text("Bluetooth Mic Router \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
    }
}
