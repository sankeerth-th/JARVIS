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

    var body: some View {
        Form {
            Section("Models") {
                Picker("Ollama model", selection: $selectedModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .disabled(modelOptions.isEmpty)
                Button("Refresh models", action: settingsVM.refreshModels)
            }
            Section("Tone") {
                Picker("Response tone", selection: $selectedTone) {
                    ForEach(ToneStyle.allCases, id: \.self) { tone in
                        Text(tone.rawValue.capitalized).tag(tone)
                    }
                }
            }
            Section("Privacy") {
                Toggle("Disable logging", isOn: $disableLogging)
                Toggle("Clipboard watcher", isOn: $clipboardWatcher)
                Toggle("Privacy Guardian", isOn: $privacyGuardianEnabled)
                Toggle("Clipboard monitor (guardian)", isOn: $privacyClipboardMonitorEnabled)
                Toggle("Sensitive pattern detection", isOn: $privacySensitiveDetectionEnabled)
                Toggle("Network monitor (Jarvis only)", isOn: $privacyNetworkMonitorEnabled)
                Button("Clear conversation history", action: settingsVM.clearHistory)
            }
            Section("Permissions") {
                HStack {
                    Button("Grant Accessibility", action: settingsVM.requestAccessibility)
                    Button("Open Settings", action: settingsVM.openAccessibilitySettings)
                }
                HStack {
                    Button("Grant Screen Recording", action: settingsVM.requestScreenRecording)
                    Button("Open Settings", action: settingsVM.openScreenRecordingSettings)
                }
                HStack {
                    Button("Grant Notifications", action: settingsVM.requestNotifications)
                    Button("Open Settings", action: settingsVM.openNotificationSettings)
                }
                Button("Send test notification", action: notificationVM.sendTestNotification)
            }
            Section("Notifications") {
                Toggle("Focus Mode", isOn: $focusModeEnabled)
                Toggle("Allow urgent during quiet hours", isOn: $allowUrgentInQuietHours)
                HStack {
                    TextField("Priority apps (comma separated)", text: $priorityAppsText)
                    Button("Save", action: applyPriorityApps)
                }
                HStack {
                    Stepper("Quiet start: \(quietStartHour):00", value: $quietStartHour, in: 0...23)
                    Stepper("Quiet end: \(quietEndHour):00", value: $quietEndHour, in: 0...23)
                }
            }
            Section("Indexed folders") {
                Button("Add folder", action: pickFolderForIndex)
                Button("Re-index configured folders", action: settingsVM.reindexConfiguredFolders)
                ForEach(settingsVM.settings.indexedFolders, id: \.self) { path in
                    HStack {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Remove") {
                            settingsVM.removeIndexedFolder(path: path)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 460)
        .onAppear {
            syncFromViewModels()
            settingsVM.refreshModels()
        }
        .onChange(of: settingsVM.settings) { _, _ in
            syncFromViewModels()
        }
        .onChange(of: notificationVM.priorityApps) { _, _ in
            syncPriorityApps()
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
