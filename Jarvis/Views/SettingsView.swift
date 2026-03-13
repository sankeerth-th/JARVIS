import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel

    @State private var selectedModel: String = ""
    @State private var selectedTone: ToneStyle = .professional
    @State private var disableLogging: Bool = false
    @State private var clipboardWatcher: Bool = false
    @State private var priorityAppsText: String = ""
    @State private var focusModeEnabled: Bool = false
    @State private var allowUrgentInQuietHours: Bool = true
    @State private var quietStartHour: Int = 22
    @State private var quietEndHour: Int = 7
    @State private var privacyGuardianEnabled: Bool = false
    @State private var privacyClipboardMonitorEnabled: Bool = false
    @State private var privacySensitiveDetectionEnabled: Bool = true
    @State private var privacyNetworkMonitorEnabled: Bool = true

    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var screenCaptureGranted: Bool = CGPreflightScreenCaptureAccess()
    @State private var notificationsGranted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.small) {
            JarvisSectionHeader(
                title: "Jarvis settings",
                subtitle: "Local-first defaults, privacy controls, and permission access"
            )
            Form {
                Section("Model") {
                    Picker("Ollama model", selection: $selectedModel) {
                        ForEach(modelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .disabled(modelOptions.isEmpty)
                    Picker("Default tone", selection: $selectedTone) {
                        ForEach(ToneStyle.allCases, id: \.self) { tone in
                            Text(tone.rawValue.capitalized).tag(tone)
                        }
                    }
                    HStack {
                        Button("Refresh models", action: settingsVM.refreshModels)
                            .buttonStyle(JarvisButtonStyle(tone: .secondary))
                        Spacer(minLength: 0)
                        Text("Applies to all Jarvis text generation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Privacy") {
                    Toggle("Disable logs", isOn: $disableLogging)
                    Toggle("Clipboard watcher", isOn: $clipboardWatcher)
                    Toggle("Privacy guardian", isOn: $privacyGuardianEnabled)
                    Toggle("Guardian clipboard monitor", isOn: $privacyClipboardMonitorEnabled)
                    Toggle("Sensitive pattern detection", isOn: $privacySensitiveDetectionEnabled)
                    Toggle("Network monitor (Jarvis only)", isOn: $privacyNetworkMonitorEnabled)
                    Button("Clear conversation history", action: settingsVM.clearHistory)
                        .buttonStyle(JarvisButtonStyle(tone: .danger))
                    JarvisStatusRow(
                        tone: .info,
                        message: "Jarvis runs locally by default. Enable only the monitors you need."
                    )
                }

                Section("Permissions") {
                    JarvisPermissionRow(
                        title: "Accessibility",
                        subtitle: "Required for global hotkey and foreground automation.",
                        status: accessibilityGranted ? "Enabled" : "Not enabled",
                        isGranted: accessibilityGranted,
                        primaryActionTitle: "Request",
                        primaryAction: requestAccessibility,
                        secondaryActionTitle: "Open Settings",
                        secondaryAction: settingsVM.openAccessibilitySettings
                    )
                    JarvisPermissionRow(
                        title: "Screen recording",
                        subtitle: "Needed for capture and OCR workflows.",
                        status: screenCaptureGranted ? "Enabled" : "Not enabled",
                        isGranted: screenCaptureGranted,
                        primaryActionTitle: "Request",
                        primaryAction: requestScreenCapture,
                        secondaryActionTitle: "Open Settings",
                        secondaryAction: settingsVM.openScreenRecordingSettings
                    )
                    JarvisPermissionRow(
                        title: "Notifications",
                        subtitle: "Needed for focus mode and digest alerts.",
                        status: notificationsGranted ? "Enabled" : "Not enabled",
                        isGranted: notificationsGranted,
                        primaryActionTitle: "Request",
                        primaryAction: requestNotifications,
                        secondaryActionTitle: "Open Settings",
                        secondaryAction: settingsVM.openNotificationSettings
                    )
                }

                Section("Notifications") {
                    Toggle("Focus mode", isOn: $focusModeEnabled)
                    Toggle("Allow urgent during quiet hours", isOn: $allowUrgentInQuietHours)
                    HStack {
                        TextField("Priority apps (comma separated bundle IDs)", text: $priorityAppsText)
                        Button("Save", action: applyPriorityApps)
                            .buttonStyle(JarvisButtonStyle(tone: .secondary))
                    }
                    HStack {
                        Stepper("Quiet start: \(quietStartHour):00", value: $quietStartHour, in: 0...23)
                        Stepper("Quiet end: \(quietEndHour):00", value: $quietEndHour, in: 0...23)
                    }
                    Button("Send test notification", action: notificationVM.sendTestNotification)
                        .buttonStyle(JarvisButtonStyle(tone: .secondary))
                }

                Section("Indexed folders") {
                    HStack {
                        Button("Add folder", action: pickFolderForIndex)
                            .buttonStyle(JarvisButtonStyle(tone: .secondary))
                        Button("Re-index configured folders", action: settingsVM.reindexConfiguredFolders)
                            .buttonStyle(JarvisButtonStyle(tone: .secondary))
                    }
                    ForEach(settingsVM.settings.indexedFolders, id: \.self) { path in
                        HStack {
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Remove") {
                                settingsVM.removeIndexedFolder(path: path)
                            }
                            .buttonStyle(JarvisButtonStyle(tone: .tertiary))
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 560)
        .onAppear {
            syncFromViewModels()
            refreshPermissionState()
            settingsVM.refreshModels()
            Task {
                await notificationVM.refreshPermissionStatus()
                await MainActor.run {
                    refreshPermissionState()
                }
            }
        }
        .onChange(of: settingsVM.settings) { _, _ in
            syncFromViewModels()
            refreshPermissionState()
        }
        .onChange(of: notificationVM.priorityApps) { _, _ in
            syncPriorityApps()
        }
        .onChange(of: notificationVM.notificationsPermissionGranted) { _, _ in
            refreshPermissionState()
        }
        .onChange(of: selectedModel) { _, model in
            guard !model.isEmpty, settingsVM.settings.selectedModel != model else { return }
            settingsVM.setModel(model)
        }
        .onChange(of: selectedTone) { _, tone in
            guard settingsVM.settings.tone != tone else { return }
            settingsVM.setTone(tone)
        }
        .onChange(of: disableLogging) { _, disabled in
            guard settingsVM.settings.disableLogging != disabled else { return }
            settingsVM.setLoggingDisabled(disabled)
        }
        .onChange(of: clipboardWatcher) { _, enabled in
            guard settingsVM.settings.clipboardWatcherEnabled != enabled else { return }
            settingsVM.toggleClipboardWatcher(isOn: enabled)
        }
        .onChange(of: focusModeEnabled) { _, enabled in
            guard settingsVM.settings.focusModeEnabled != enabled else { return }
            settingsVM.setFocusModeEnabled(enabled)
            notificationVM.focusModeEnabled = enabled
            if enabled {
                settingsVM.requestNotifications()
            }
        }
        .onChange(of: allowUrgentInQuietHours) { _, enabled in
            guard settingsVM.settings.focusAllowUrgent != enabled else { return }
            settingsVM.setFocusAllowUrgent(enabled)
            notificationVM.allowUrgentInQuietHours = enabled
        }
        .onChange(of: quietStartHour) { _, _ in
            settingsVM.setQuietHours(startHour: quietStartHour, endHour: quietEndHour)
            notificationVM.quietHours = QuietHours(start: DateComponents(hour: quietStartHour), end: DateComponents(hour: quietEndHour))
        }
        .onChange(of: quietEndHour) { _, _ in
            settingsVM.setQuietHours(startHour: quietStartHour, endHour: quietEndHour)
            notificationVM.quietHours = QuietHours(start: DateComponents(hour: quietStartHour), end: DateComponents(hour: quietEndHour))
        }
        .onChange(of: privacyGuardianEnabled) { _, enabled in
            guard settingsVM.settings.privacyGuardianEnabled != enabled else { return }
            settingsVM.setPrivacyGuardianEnabled(enabled)
        }
        .onChange(of: privacyClipboardMonitorEnabled) { _, enabled in
            guard settingsVM.settings.privacyClipboardMonitorEnabled != enabled else { return }
            settingsVM.setPrivacyClipboardMonitorEnabled(enabled)
        }
        .onChange(of: privacySensitiveDetectionEnabled) { _, enabled in
            guard settingsVM.settings.privacySensitiveDetectionEnabled != enabled else { return }
            settingsVM.setPrivacySensitiveDetectionEnabled(enabled)
        }
        .onChange(of: privacyNetworkMonitorEnabled) { _, enabled in
            guard settingsVM.settings.privacyNetworkMonitorEnabled != enabled else { return }
            settingsVM.setPrivacyNetworkMonitorEnabled(enabled)
        }
    }

    private var modelOptions: [String] {
        var options = settingsVM.availableModels
        if !selectedModel.isEmpty && !options.contains(selectedModel) {
            options.insert(selectedModel, at: 0)
        }
        return options
    }

    private func syncFromViewModels() {
        selectedModel = settingsVM.settings.selectedModel
        selectedTone = settingsVM.settings.tone
        disableLogging = settingsVM.settings.disableLogging
        clipboardWatcher = settingsVM.settings.clipboardWatcherEnabled
        focusModeEnabled = settingsVM.settings.focusModeEnabled
        allowUrgentInQuietHours = settingsVM.settings.focusAllowUrgent
        quietStartHour = settingsVM.settings.quietHoursStartHour
        quietEndHour = settingsVM.settings.quietHoursEndHour
        privacyGuardianEnabled = settingsVM.settings.privacyGuardianEnabled
        privacyClipboardMonitorEnabled = settingsVM.settings.privacyClipboardMonitorEnabled
        privacySensitiveDetectionEnabled = settingsVM.settings.privacySensitiveDetectionEnabled
        privacyNetworkMonitorEnabled = settingsVM.settings.privacyNetworkMonitorEnabled
        syncPriorityApps()
    }

    private func refreshPermissionState() {
        accessibilityGranted = AXIsProcessTrusted()
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        notificationsGranted = notificationVM.notificationsPermissionGranted
    }

    private func syncPriorityApps() {
        let joined = notificationVM.priorityApps.joined(separator: ",")
        if priorityAppsText != joined {
            priorityAppsText = joined
        }
    }

    private func applyPriorityApps() {
        let apps = priorityAppsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        notificationVM.priorityApps = apps
    }

    private func requestAccessibility() {
        settingsVM.requestAccessibility()
        refreshPermissionState()
    }

    private func requestScreenCapture() {
        settingsVM.requestScreenRecording()
        refreshPermissionState()
    }

    private func requestNotifications() {
        settingsVM.requestNotifications()
        Task {
            await notificationVM.refreshPermissionStatus()
            await MainActor.run {
                refreshPermissionState()
            }
        }
    }

    private func pickFolderForIndex() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let folder = panel.urls.first else { return }
        settingsVM.indexFolder(url: folder)
    }
}
