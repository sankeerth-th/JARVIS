import SwiftUI
import AppKit

struct NotificationsView: View {
    @EnvironmentObject private var viewModel: NotificationViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var keyword: String = ""
    @State private var selectedPriority: NotificationItem.Priority = .urgent
    @State private var focusModeEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                JarvisSectionHeader(title: "Notifications", subtitle: "Focus, digest, and prioritization rules")
                Spacer()
                Toggle("Focus mode", isOn: $focusModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if viewModel.focusModeEnabled {
                    Text("\(viewModel.lowPriorityCount) queued")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.18), in: Capsule())
                }
                Button("Batch digest") {
                    viewModel.batchDigestNow(model: settingsVM.settings.selectedModel)
                }
                .buttonStyle(JarvisButtonStyle(tone: .secondary))
                Button("Copy summary") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.summary(), forType: .string)
                }
                .buttonStyle(JarvisButtonStyle(tone: .secondary))
            }

            if !viewModel.notificationsPermissionGranted {
                HStack {
                    Text("Notifications permission is missing.")
                        .font(.caption)
                    Spacer()
                    Button("Open System Settings") {
                        PermissionsManager.shared.openNotificationSettings()
                    }
                    .buttonStyle(JarvisButtonStyle(tone: .primary))
                }
                .padding(8)
                .jarvisCard(fill: JarvisPalette.warning, border: JarvisPalette.warningBorder, shadowOpacity: 0.03)
            }

            Text(viewModel.summary())
                .font(.body)
                .textSelection(.enabled)
                .padding(10)
                .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.border, shadowOpacity: 0.03)

            if viewModel.isDigestRunning && viewModel.digestOutput.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Generating digest...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 220, height: 14)
                }
                .padding(8)
                .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)
                .redacted(reason: .placeholder)
            } else if !viewModel.digestOutput.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Batch digest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.digestOutput)
                        .textSelection(.enabled)
                        .padding(8)
                        .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)
                }
            }

            keywordRuleEditor

            if viewModel.notifications.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No notifications available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Enable notifications permission and wait for incoming alerts.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)
            } else {
                List {
                    Section(header: Text("Urgent")) {
                        ForEach(viewModel.notifications.filter { $0.priority == .urgent }) { item in
                            NotificationRow(item: item)
                                .listRowBackground(Color.clear)
                        }
                    }
                    Section(header: Text("Needs reply")) {
                        ForEach(viewModel.notifications.filter { $0.priority == .needsReply }) { item in
                            NotificationRow(item: item)
                                .listRowBackground(Color.clear)
                        }
                    }
                    Section(header: Text("FYI")) {
                        ForEach(viewModel.notifications.filter { $0.priority == .fyi }) { item in
                            NotificationRow(item: item)
                                .listRowBackground(Color.clear)
                        }
                    }
                    Section(header: Text("Low priority")) {
                        ForEach(viewModel.notifications.filter { $0.priority == .low }) { item in
                            NotificationRow(item: item)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)
        .onAppear {
            focusModeEnabled = viewModel.focusModeEnabled
            Task {
                await viewModel.refreshPermissionStatus()
            }
        }
        .onChange(of: focusModeEnabled) { _, enabled in
            guard viewModel.focusModeEnabled != enabled else { return }
            viewModel.focusModeEnabled = enabled
        }
        .onChange(of: viewModel.focusModeEnabled) { _, enabled in
            if focusModeEnabled != enabled {
                focusModeEnabled = enabled
            }
        }
    }

    private var keywordRuleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyword rules")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Keyword", text: $keyword)
                Picker("Priority", selection: $selectedPriority) {
                    ForEach(NotificationItem.Priority.allCases, id: \.self) { priority in
                        Text(priority.rawValue.capitalized).tag(priority)
                    }
                }
                .frame(width: 140)
                Button("Add") {
                    guard !keyword.isEmpty else { return }
                    let ruleKey = keyword
                    viewModel.keywordRules[ruleKey] = selectedPriority
                    keyword = ""
                }
                .buttonStyle(JarvisButtonStyle(tone: .primary))
            }
            if !viewModel.keywordRules.isEmpty {
                ForEach(viewModel.keywordRules.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(value.rawValue.capitalized).font(.caption)
                        Button(role: .destructive, action: {
                            viewModel.keywordRules.removeValue(forKey: key)
                        }) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.border, shadowOpacity: 0.02)
    }
}

private struct NotificationRow: View {
    let item: NotificationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(item.priority.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(priorityColor.opacity(0.2), in: Capsule())
            }
            Text(item.body)
                .font(.body)
            if let response = item.suggestedResponse {
                Text("Suggested: \(response)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.border, shadowOpacity: 0.02)
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: return .red
        case .needsReply: return .orange
        case .fyi: return .blue
        case .low: return .gray
        }
    }
}
