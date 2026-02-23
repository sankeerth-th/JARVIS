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
                Toggle("Focus mode", isOn: $focusModeEnabled)
                    .toggleStyle(.switch)
                Spacer()
                Button("Batch digest now") {
                    viewModel.batchDigestNow(model: settingsVM.settings.selectedModel)
                }
                .buttonStyle(.bordered)
                Menu("Quiet hours") {
                    Button("None") {
                        viewModel.quietHours = nil
                    }
                    Button("10p-7a") {
                        viewModel.quietHours = QuietHours(start: DateComponents(hour: 22), end: DateComponents(hour: 7))
                    }
                }
                .menuStyle(.borderlessButton)

                Button("Copy summary") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.summary(), forType: .string)
                }
                .buttonStyle(.bordered)
            }

            if !viewModel.notificationsPermissionGranted {
                HStack {
                    Text("Notifications permission is missing.")
                        .font(.caption)
                    Spacer()
                    Button("Open System Settings") {
                        PermissionsManager.shared.openNotificationSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if viewModel.focusModeEnabled && viewModel.lowPriorityCount > 0 {
                Text("You have \(viewModel.lowPriorityCount) low-priority notifications.")
                    .font(.caption)
                    .padding(8)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(viewModel.summary())
                .font(.body)
                .textSelection(.enabled)
                .padding(10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            if !viewModel.digestOutput.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Batch digest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.digestOutput)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            keywordRuleEditor

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
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
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
                .buttonStyle(.borderedProminent)
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
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
                    .background(Color.orange.opacity(0.2), in: Capsule())
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
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
