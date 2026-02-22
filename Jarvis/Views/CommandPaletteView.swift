import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var emailVM: EmailDraftViewModel
    @EnvironmentObject private var diagnosticsVM: DiagnosticsViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    var body: some View {
        VStack(spacing: 12) {
            header
            if !commandVM.ollamaReachable {
                HStack {
                    Text("Ollama server not reachable. Start it via `ollama serve` or the Ollama app.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Retry", action: commandVM.loadModels)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            if let status = commandVM.statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if commandVM.toolRequiresConfirmation, let pendingTool = commandVM.pendingTool {
                pendingToolBanner(invocation: pendingTool)
            }
            Picker("Tab", selection: $commandVM.selectedTab) {
                ForEach(CommandPaletteViewModel.PaletteTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            tabContent
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 520)
        .background(.ultraThinMaterial)
        .onAppear {
            diagnosticsVM.refresh()
            settingsVM.observeSettings()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(commandVM.privacyStatus.description, systemImage: commandVM.privacyStatus == .offline ? "shield.checkerboard" : "wifi")
                .foregroundStyle(commandVM.privacyStatus == .offline ? .green : .orange)
            Picker("Model", selection: Binding(get: { settingsVM.settings.selectedModel }, set: settingsVM.setModel)) {
                ForEach(commandVM.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .frame(width: 180)
            Toggle("Disable logging", isOn: Binding(get: { settingsVM.settings.disableLogging }, set: settingsVM.setLoggingDisabled))
                .toggleStyle(.switch)
            Spacer()
            Button(action: commandVM.clearHistory) {
                Label("Clear History", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch commandVM.selectedTab {
        case .chat:
            ChatTabView()
                .environmentObject(commandVM)
        case .notifications:
            NotificationsView()
                .environmentObject(notificationVM)
        case .documents:
            DocumentWorkspaceView()
                .environmentObject(commandVM)
                .environmentObject(emailVM)
        case .knowledge:
            KnowledgeBaseView()
                .environmentObject(commandVM)
                .environmentObject(settingsVM)
        case .macros:
            MacroListView()
                .environmentObject(commandVM)
                .environmentObject(settingsVM)
        case .diagnostics:
            DiagnosticsView()
                .environmentObject(diagnosticsVM)
        }
    }

    private func pendingToolBanner(invocation: ToolInvocation) -> some View {
        HStack {
            Text("Allow tool \(invocation.name.rawValue)?")
            Spacer()
            Button("Approve", action: commandVM.approvePendingTool)
            Button("Reject", role: .cancel, action: commandVM.rejectPendingTool)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(8)
    }
}

private struct ChatTabView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                conversationScroll
                inputArea
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick actions").font(.caption).textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(commandVM.quickActions) { action in
                            Button(action: { commandVM.performQuickAction(action) }) {
                                Label(action.title, systemImage: action.icon)
                                    .padding(8)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let clipboard = commandVM.clipboardBanner {
                    ClipboardBannerView(text: clipboard, clearAction: commandVM.clearClipboardBanner)
                }
                Text("History").font(.caption)
                List(commandVM.history) { convo in
                    Button {
                        commandVM.selectConversation(convo)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(convo.title).font(.body)
                            Text(convo.updatedAt.formatted()).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .frame(minWidth: 180, maxHeight: 200)
            }
            .frame(width: 250)
        }
    }

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(commandVM.conversation.messages) { message in
                        ConversationRow(message: message)
                    }
                    if commandVM.isStreaming {
                        ConversationRow(message: ChatMessage(role: .assistant, text: commandVM.streamingBuffer, isStreaming: true))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: commandVM.conversation.messages.count) { _ in
                    if let last = commandVM.conversation.messages.last?.id {
                        withAnimation { proxy.scrollTo(last) }
                    }
                }
            }
        }
        .background(.thinMaterial)
        .cornerRadius(12)
    }

    private var inputArea: some View {
        HStack {
            TextField("Ask Jarvis…", text: $commandVM.inputText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commandVM.sendCurrentPrompt() }
            Button(action: commandVM.sendCurrentPrompt) {
                Image(systemName: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

private struct ConversationRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.text)
                .font(.body)
                .padding(8)
                .background(message.role == .user ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(10)
        }
        .id(message.id)
    }

    private var label: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Jarvis"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }
}

private struct DocumentWorkspaceView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var emailVM: EmailDraftViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Import document", action: commandVM.selectDocumentUsingPanel)
                if commandVM.importedDocument != nil {
                    Button("Clear", action: commandVM.clearDocument)
                }
                Spacer()
                Button("Capture window", action: emailVM.captureActiveWindow)
                Button("Capture screen", action: emailVM.captureFullScreen)
                Button("Draft email", action: { emailVM.draftReply() })
            }
            if let document = commandVM.importedDocument {
                Text(document.title).font(.headline)
                ScrollView {
                    Text(document.content)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                HStack {
                    ForEach(DocumentAction.allCases) { action in
                        Button(action.rawValue) { commandVM.summarizeDocument(action: action) }
                    }
                }
            }
            Divider()
            EmailDraftView()
                .environmentObject(emailVM)
            Divider()
            Button("Extract table", action: commandVM.runTableExtraction)
            if let table = commandVM.tableResult {
                TableExtractionView(result: table)
            }
        }
    }
}

private struct TableExtractionView: View {
    let result: TableExtractionResult

    var body: some View {
        VStack(alignment: .leading) {
            Text("Markdown")
            Text(render(format: .markdown))
                .font(.system(.body, design: .monospaced))
            Text("CSV")
            Text(render(format: .csv))
                .font(.system(.body, design: .monospaced))
            Text("JSON")
            Text(render(format: .json))
                .font(.system(.body, design: .monospaced))
        }
    }

    private func render(format: TableExtractionResult.OutputFormat) -> String {
        let extractor = TableExtractor()
        return (try? extractor.render(result, format: format)) ?? ""
    }
}
