import SwiftUI
import AppKit

struct NotificationsView: View {
    @EnvironmentObject private var viewModel: NotificationViewModel
    @State private var keyword: String = ""
    @State private var selectedPriority: NotificationItem.Priority = .urgent
    @State private var focusModeEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Focus mode", isOn: $focusModeEnabled)
                Spacer()
                Menu("Quiet hours") {
                    Button("None") {
                        viewModel.quietHours = nil
                    }
                    Button("10p-7a") {
                        viewModel.quietHours = QuietHours(start: DateComponents(hour: 22), end: DateComponents(hour: 7))
                    }
                }
                Button("Copy summary") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.summary(), forType: .string)
                }
                .buttonStyle(.bordered)
            }
            Text(viewModel.summary())
                .font(.body)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            keywordRuleEditor
            List {
                Section(header: Text("Urgent")) {
                    ForEach(viewModel.notifications.filter { $0.priority == .urgent }) { item in
                        NotificationRow(item: item)
                    }
                }
                Section(header: Text("Needs reply")) {
                    ForEach(viewModel.notifications.filter { $0.priority == .needsReply }) { item in
                        NotificationRow(item: item)
                    }
                }
                Section(header: Text("FYI")) {
                    ForEach(viewModel.notifications.filter { $0.priority == .fyi }) { item in
                        NotificationRow(item: item)
                    }
                }
            }
        }
        .padding(8)
        .onAppear {
            focusModeEnabled = viewModel.focusModeEnabled
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
        VStack(alignment: .leading) {
            Text("Keyword rules").font(.caption)
            HStack {
                TextField("Keyword", text: $keyword)
                Picker("Priority", selection: $selectedPriority) {
                    ForEach(NotificationItem.Priority.allCases, id: \.self) { priority in
                        Text(priority.rawValue.capitalized).tag(priority)
                    }
                }
                Button("Add") {
                    guard !keyword.isEmpty else { return }
                    let ruleKey = keyword
                    viewModel.keywordRules[ruleKey] = selectedPriority
                    keyword = ""
                }
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
                }
            }
        }
    }
}

private struct NotificationRow: View {
    let item: NotificationItem

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(item.title).bold()
                Spacer()
                Text(item.priority.rawValue.capitalized)
                    .font(.caption)
                    .padding(4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(6)
            }
            Text(item.body)
                .font(.body)
            if let response = item.suggestedResponse {
                Text("Suggested: \(response)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
