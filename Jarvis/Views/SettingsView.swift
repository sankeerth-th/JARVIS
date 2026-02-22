import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var selectedModel: String = ""
    @State private var selectedTone: ToneStyle = .professional
    @State private var disableLogging: Bool = false
    @State private var clipboardWatcher: Bool = false
    @State private var priorityAppsText: String = ""

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
                HStack {
                    TextField("Priority apps (comma separated)", text: $priorityAppsText)
                    Button("Save", action: applyPriorityApps)
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
}
