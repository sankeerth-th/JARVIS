import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var emailVM: EmailDraftViewModel
    @EnvironmentObject private var diagnosticsVM: DiagnosticsViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var selectedModel: String = ""
    @State private var loggingDisabled: Bool = false
    @State private var isCompactMode: Bool = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.14),
                    Color(red: 0.05, green: 0.06, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [Color.cyan.opacity(0.12), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 520
                )
            )

            VStack(spacing: 12) {
                header
                if !commandVM.ollamaReachable {
                    offlineBanner
                }
                if let status = commandVM.statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }
                if commandVM.toolRequiresConfirmation, let pendingTool = commandVM.pendingTool {
                    pendingToolBanner(invocation: pendingTool)
                }
                if isCompactMode {
                    compactIdleBody
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    tabRail
                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 22)
            .animation(.easeInOut(duration: 0.20), value: isCompactMode)
            .animation(.easeInOut(duration: 0.18), value: commandVM.selectedTab)
        }
        .frame(minWidth: isCompactMode ? 640 : 940, minHeight: isCompactMode ? 240 : 620)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(.ultraThinMaterial)
        .onAppear {
            syncFromSettings()
            commandVM.loadModels()
            diagnosticsVM.refresh()
        }
        .onChange(of: commandVM.selectedTab) { _, selected in
            if selected != .chat, isCompactMode {
                isCompactMode = false
            }
        }
        .onChange(of: settingsVM.settings.selectedModel) { _, model in
            if selectedModel != model {
                selectedModel = model
            }
        }
        .onChange(of: settingsVM.settings.disableLogging) { _, disabled in
            if loggingDisabled != disabled {
                loggingDisabled = disabled
            }
        }
        .onChange(of: selectedModel) { _, model in
            guard !model.isEmpty, settingsVM.settings.selectedModel != model else { return }
            settingsVM.setModel(model)
        }
        .onChange(of: loggingDisabled) { _, disabled in
            guard settingsVM.settings.disableLogging != disabled else { return }
            settingsVM.setLoggingDisabled(disabled)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                AssistantOrbView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jarvis")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Offline assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                AssistantStatusChip(
                    title: commandVM.privacyStatus.description,
                    icon: commandVM.privacyStatus == .offline ? "lock.shield" : "wifi",
                    tint: commandVM.privacyStatus == .offline ? .green : .orange
                )

                Button(action: commandVM.clearHistory) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(AssistantPillButtonStyle(tint: .red.opacity(0.24)))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCompactMode.toggle()
                        if isCompactMode {
                            commandVM.selectTab(.chat)
                        }
                    }
                } label: {
                    Label(isCompactMode ? "Expand" : "Compact", systemImage: isCompactMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(AssistantPillButtonStyle(tint: Color.white.opacity(0.10)))
            }

            HStack(spacing: 10) {
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Model", selection: $selectedModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 210)
                .disabled(modelOptions.isEmpty)

                Spacer()

                Toggle("", isOn: $loggingDisabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                Text("No logs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .assistantCard()
    }

    private var compactIdleBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Quick ask")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Chat") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCompactMode = false
                        commandVM.selectTab(.chat)
                    }
                }
                .buttonStyle(AssistantPillButtonStyle(tint: Color.cyan.opacity(0.16)))
                Button("Docs") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCompactMode = false
                        commandVM.selectTab(.documents)
                    }
                }
                .buttonStyle(AssistantPillButtonStyle(tint: Color.white.opacity(0.10)))
                Button("Email") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCompactMode = false
                        commandVM.selectTab(.email)
                    }
                }
                .buttonStyle(AssistantPillButtonStyle(tint: Color.white.opacity(0.10)))
            }

            HStack(spacing: 10) {
                TextField("Ask Jarvis...", text: $commandVM.inputText, axis: .vertical)
                    .lineLimit(1...2)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .onSubmit {
                        performCompactSend()
                    }
                Button {
                    performCompactSend()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .padding(10)
                }
                .buttonStyle(AssistantPillButtonStyle(tint: Color.cyan.opacity(0.25)))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .assistantCard(fill: Color.white.opacity(0.035), border: Color.white.opacity(0.1))
    }

    private func performCompactSend() {
        let text = commandVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandVM.inputText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isCompactMode = false
            commandVM.selectTab(.chat)
        }
        commandVM.send(prompt: text)
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle")
                .foregroundStyle(.yellow)
            Text("Ollama is not reachable. Start it with `ollama serve`.")
                .font(.footnote)
            Spacer()
            Button("Retry", action: commandVM.loadModels)
                .buttonStyle(AssistantPillButtonStyle(tint: .blue.opacity(0.26)))
        }
        .padding(10)
        .assistantCard(fill: Color.red.opacity(0.1), border: Color.red.opacity(0.25))
    }

    private var tabRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CommandPaletteViewModel.PaletteTab.allCases, id: \.self) { tab in
                    Button {
                        commandVM.selectTab(tab)
                    } label: {
                        Label(tab.rawValue, systemImage: icon(for: tab))
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(commandVM.selectedTab == tab ? Color.cyan.opacity(0.14) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(commandVM.selectedTab == tab ? Color.cyan.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
        .padding(8)
        .assistantCard()
    }

    private func icon(for tab: CommandPaletteViewModel.PaletteTab) -> String {
        switch tab {
        case .chat: return "message"
        case .notifications: return "bell"
        case .documents: return "doc.text"
        case .email: return "envelope"
        case .knowledge: return "books.vertical"
        case .macros: return "bolt"
        case .diagnostics: return "stethoscope"
        }
    }

    private var modelOptions: [String] {
        var options = commandVM.availableModels
        if !selectedModel.isEmpty && !options.contains(selectedModel) {
            options.insert(selectedModel, at: 0)
        }
        return options
    }

    private func syncFromSettings() {
        selectedModel = settingsVM.settings.selectedModel
        loggingDisabled = settingsVM.settings.disableLogging
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
        case .email:
            EmailWorkspaceView()
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
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.yellow)
            Text("Allow tool \(invocation.name.rawValue)?")
            Spacer()
            Button("Approve", action: commandVM.approvePendingTool)
                .buttonStyle(AssistantPillButtonStyle(tint: .green.opacity(0.25)))
            Button("Reject", role: .cancel, action: commandVM.rejectPendingTool)
                .buttonStyle(AssistantPillButtonStyle(tint: .red.opacity(0.25)))
        }
        .padding(10)
        .assistantCard(fill: Color.yellow.opacity(0.10), border: Color.yellow.opacity(0.24))
    }
}

private struct ChatTabView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 10) {
                conversationScroll
                inputArea
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                quickActionPanel
                historyPanel
            }
            .frame(width: 332)
        }
    }

    private var quickActionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.caption)
                .foregroundStyle(.secondary)
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(commandVM.quickActions) { action in
                    Button(action: { commandVM.performQuickAction(action) }) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: action.icon)
                                .frame(width: 14)
                            Text(action.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(AssistantPillButtonStyle(tint: Color.cyan.opacity(0.18)))
                }
            }
            if let clipboard = commandVM.clipboardBanner {
                ClipboardBannerView(text: clipboard, clearAction: commandVM.clearClipboardBanner)
            }
        }
        .padding(10)
        .assistantCard()
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(commandVM.history) { convo in
                        Button {
                            commandVM.selectConversation(convo)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(convo.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(convo.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .assistantCard()
    }

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(commandVM.conversation.messages) { message in
                        ConversationRow(message: message)
                    }
                    if commandVM.isStreaming {
                        ConversationRow(message: ChatMessage(
                            role: .assistant,
                            text: commandVM.streamingBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Jarvis is generating..." : commandVM.streamingBuffer,
                            isStreaming: true
                        ))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .onChange(of: commandVM.conversation.messages.count) { _, _ in
                    if let last = commandVM.conversation.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: commandVM.streamingBuffer) { _, _ in
                    if let last = commandVM.conversation.messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .assistantCard()
    }

    private var inputArea: some View {
        HStack(spacing: 10) {
            TextField("Ask Jarvis...", text: $commandVM.inputText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(inputFocused ? Color.cyan.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: inputFocused ? Color.cyan.opacity(0.25) : .clear, radius: 10)
                .animation(.easeInOut(duration: 0.18), value: inputFocused)
                .onSubmit { commandVM.sendCurrentPrompt() }

            Button(action: commandVM.sendCurrentPrompt) {
                Image(systemName: "paperplane.fill")
                    .padding(10)
            }
            .buttonStyle(AssistantPillButtonStyle(tint: Color.cyan.opacity(0.25)))
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(10)
        .assistantCard()
        .onAppear {
            inputFocused = true
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
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    message.role == .user ? Color.cyan.opacity(0.16) : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(message.role == .user ? Color.cyan.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
                )
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Documents")
                        .font(.headline)
                    Spacer()
                    Button("Import", action: commandVM.selectDocumentUsingPanel)
                        .buttonStyle(AssistantPillButtonStyle(tint: Color.cyan.opacity(0.24)))
                    if commandVM.importedDocument != nil {
                        Button("Clear", action: commandVM.clearDocument)
                            .buttonStyle(AssistantPillButtonStyle(tint: Color.white.opacity(0.10)))
                    }
                }

                if let document = commandVM.importedDocument {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title)
                            .font(.subheadline.weight(.semibold))
                        ScrollView {
                            Text(document.content)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                        .frame(height: 220)
                    }
                    .padding(10)
                    .assistantCard()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DocumentAction.allCases) { action in
                                Button(action.rawValue) { commandVM.summarizeDocument(action: action) }
                                    .buttonStyle(AssistantPillButtonStyle(tint: Color.cyan.opacity(0.18)))
                            }
                        }
                    }

                    if commandVM.isDocumentActionRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Processing document...")
                                .font(.caption)
                        }
                        .padding(10)
                        .assistantCard()
                    }

                    if !commandVM.documentActionOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Output")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(commandVM.documentActionOutput)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            HStack {
                                Button("Copy output", action: commandVM.copyDocumentOutput)
                                    .buttonStyle(AssistantPillButtonStyle(tint: Color.white.opacity(0.10)))
                                Spacer()
                            }
                        }
                        .padding(10)
                        .assistantCard()
                    }
                } else {
                    Text("Import a text, markdown, PDF, or DOCX document to start.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .assistantCard()
                }

                Divider().opacity(0.25)

                Button("Extract table", action: commandVM.runTableExtraction)
                    .buttonStyle(AssistantPillButtonStyle(tint: Color.cyan.opacity(0.20)))

                if let table = commandVM.tableResult {
                    TableExtractionView(result: table)
                        .padding(10)
                        .assistantCard()
                }
            }
        }
        .assistantCard()
    }
}

private struct EmailWorkspaceView: View {
    @EnvironmentObject private var emailVM: EmailDraftViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Email Drafting")
                    .font(.headline)
                Spacer()
                Button("Capture window", action: emailVM.captureActiveWindow)
                    .buttonStyle(AssistantPillButtonStyle(tint: Color.cyan.opacity(0.22)))
                Button("Capture screen", action: emailVM.captureFullScreen)
                    .buttonStyle(AssistantPillButtonStyle(tint: Color.white.opacity(0.12)))
                Button("Draft") { emailVM.draftReply() }
                    .buttonStyle(AssistantPillButtonStyle(tint: Color.green.opacity(0.22)))
                    .disabled(emailVM.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            EmailDraftView()
                .environmentObject(emailVM)
                .assistantCard()
        }
        .padding(10)
        .assistantCard()
    }
}

private struct TableExtractionView: View {
    let result: TableExtractionResult
    @State private var selectedFormat: TableExtractionResult.OutputFormat = .markdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Format", selection: $selectedFormat) {
                Text("Markdown").tag(TableExtractionResult.OutputFormat.markdown)
                Text("CSV").tag(TableExtractionResult.OutputFormat.csv)
                Text("JSON").tag(TableExtractionResult.OutputFormat.json)
            }
            .pickerStyle(.segmented)

            ScrollView {
                Text(render(format: selectedFormat))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 120)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private func render(format: TableExtractionResult.OutputFormat) -> String {
        let extractor = TableExtractor()
        return (try? extractor.render(result, format: format)) ?? ""
    }
}

private struct AssistantOrbView: View {
    @State private var glow: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.28))
                .frame(width: glow ? 24 : 20, height: glow ? 24 : 20)
                .blur(radius: 4)
            Circle()
                .fill(
                    LinearGradient(colors: [Color.cyan.opacity(0.95), Color.blue.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 12, height: 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

private struct AssistantStatusChip: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
    }
}

private struct AssistantPillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.28 : 0.14), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AssistantCardModifier: ViewModifier {
    let fill: Color
    let border: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }
}

private extension View {
    func assistantCard(fill: Color = Color.white.opacity(0.045), border: Color = Color.white.opacity(0.11)) -> some View {
        modifier(AssistantCardModifier(fill: fill, border: border))
    }
}
