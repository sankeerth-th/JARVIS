import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel

    var body: some View {
        Form {
            Section("Models") {
                Picker("Ollama model", selection: Binding(get: { settingsVM.settings.selectedModel }, set: settingsVM.setModel)) {
                    ForEach(settingsVM.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Button("Refresh models", action: settingsVM.refreshModels)
            }
            Section("Tone") {
                Picker("Response tone", selection: Binding(get: { settingsVM.settings.tone }, set: settingsVM.setTone)) {
                    ForEach(ToneStyle.allCases, id: \.self) { tone in
                        Text(tone.rawValue.capitalized).tag(tone)
                    }
                }
            }
            Section("Privacy") {
                Toggle("Disable logging", isOn: Binding(get: { settingsVM.settings.disableLogging }, set: settingsVM.setLoggingDisabled))
                Toggle("Clipboard watcher", isOn: Binding(get: { settingsVM.settings.clipboardWatcherEnabled }, set: settingsVM.toggleClipboardWatcher))
                Button("Clear conversation history", action: settingsVM.clearHistory)
            }
            Section("Permissions") {
                Button("Grant Accessibility", action: settingsVM.requestAccessibility)
                Button("Grant Screen Recording", action: settingsVM.requestScreenRecording)
                Button("Grant Notifications", action: settingsVM.requestNotifications)
            }
            Section("Notifications") {
                TextField("Priority apps (comma separated)", text: Binding(get: {
                    notificationVM.priorityApps.joined(separator: ",")
                }, set: { notificationVM.priorityApps = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 460)
        .onAppear {
            settingsVM.observeSettings()
            settingsVM.refreshModels()
        }
    }
}
