import Foundation
import Combine

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    enum PaletteTab: String, CaseIterable {
        case chat = "Chat"
        case notifications = "Notifications"
        case documents = "Documents"
        case knowledge = "Knowledge"
        case macros = "Macros"
        case diagnostics = "Diagnostics"
    }

    @Published var shouldShowOverlay: Bool = false
    @Published var selectedTab: PaletteTab = .chat
    @Published var inputText: String = ""
    @Published var conversation: Conversation
    @Published var history: [Conversation] = []
    @Published var quickActions: [QuickAction]
    @Published var availableModels: [String] = []
    @Published var isStreaming: Bool = false
    @Published var streamingBuffer: String = ""
    @Published var statusMessage: String? = nil
    @Published var pendingTool: ToolInvocation? = nil
    @Published var toolRequiresConfirmation: Bool = false
    @Published var knowledgeQuery: String = ""
    @Published var knowledgeResults: [IndexedDocument] = []
    @Published var clipboardBanner: String? = nil
    @Published var importedDocument: Document? = nil
    @Published var tableResult: TableExtractionResult? = nil
    @Published var notificationsPreview: [NotificationItem] = []
    @Published var macroLogs: [MacroExecutionLog] = []
    @Published var privacyStatus: PrivacyStatus
    @Published var ollamaReachable: Bool = false

    private let settingsStore: SettingsStore
    private let conversationService: ConversationService
    private let documentService: DocumentImportService
    private let tableExtractor: TableExtractor
    private let localIndexService: LocalIndexService
    private let macroService: MacroService
    private let workflowEngine: WorkflowEngine
    private let toolService: ToolExecutionService
    private let notificationViewModel: NotificationViewModel
    private let clipboardWatcher: ClipboardWatcher
    private let diagnosticsService: DiagnosticsService
    private let ollama: OllamaClient
    private let parser = ToolInvocationParser()
    private var streamTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var selectedQuickAction: QuickAction?

    init(settingsStore: SettingsStore,
         conversationService: ConversationService,
         documentService: DocumentImportService,
         tableExtractor: TableExtractor,
         localIndexService: LocalIndexService,
         macroService: MacroService,
         workflowEngine: WorkflowEngine,
         toolService: ToolExecutionService,
         notificationViewModel: NotificationViewModel,
         clipboardWatcher: ClipboardWatcher,
         diagnosticsService: DiagnosticsService,
         ollama: OllamaClient) {
        self.settingsStore = settingsStore
        self.conversationService = conversationService
        self.documentService = documentService
        self.tableExtractor = tableExtractor
        self.localIndexService = localIndexService
        self.macroService = macroService
        self.workflowEngine = workflowEngine
        self.toolService = toolService
        self.notificationViewModel = notificationViewModel
        self.clipboardWatcher = clipboardWatcher
        self.diagnosticsService = diagnosticsService
        self.ollama = ollama

        let history = conversationService.loadRecentConversations()
        self.history = history
        self.conversation = history.first ?? Conversation(title: "New Chat", model: settingsStore.selectedModel())
        self.quickActions = settingsStore.quickActions()
        self.privacyStatus = settingsStore.current.privacyStatus

        bind()
        loadModels()
    }

    private func bind() {
        notificationViewModel.$notifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in self?.notificationsPreview = Array(items.prefix(5)) }
            .store(in: &cancellables)
        settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.quickActions = settings.quickActions
                self?.privacyStatus = settings.privacyStatus
                self?.handleClipboardWatcherToggle(enabled: settings.clipboardWatcherEnabled)
            }
            .store(in: &cancellables)
        clipboardWatcher.onTextChange = { [weak self] text in
            Task { @MainActor in
                self?.clipboardBanner = String(text.prefix(500))
            }
        }
        handleClipboardWatcherToggle(enabled: settingsStore.clipboardWatcherEnabled())
        Task {
            let reachable = await ollama.isReachable()
            await MainActor.run {
                self.ollamaReachable = reachable
            }
        }
    }

    func showOverlay() { shouldShowOverlay = true }
    func hideOverlay() { shouldShowOverlay = false }

    func selectTab(_ tab: PaletteTab) {
        selectedTab = tab
    }

    func sendCurrentPrompt() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(prompt: trimmed)
        inputText = ""
    }

    func send(prompt: String) {
        var convo = conversation
        let userMessage = ChatMessage(role: .user, text: prompt)
        convo.messages.append(userMessage)
        convo.updatedAt = Date()
        conversation = convo
        conversationService.persist(convo)
        streamingBuffer = ""
        isStreaming = true
        let context = buildContext()
        streamTask?.cancel()
        streamTask = Task {
            do {
                let stream = conversationService.streamResponse(for: prompt, conversation: convo, context: context, settings: settingsStore.current)
                for try await chunk in stream {
                    await MainActor.run {
                        self.consume(chunk: chunk)
                    }
                }
                await MainActor.run {
                    self.finishStreaming()
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Ollama error: \(error.localizedDescription)"
                    self.isStreaming = false
                }
            }
        }
    }

    private func consume(chunk: String) {
        let (cleaned, invocations) = parser.extractInvocations(from: chunk)
        streamingBuffer.append(cleaned)
        for invocation in invocations {
            if toolService.requiresConfirmation(for: invocation.name) {
                pendingTool = invocation
                toolRequiresConfirmation = true
            } else {
                Task {
                    await self.handleTool(invocation: invocation)
                }
            }
        }
    }

    private func finishStreaming() {
        let assistantMessage = ChatMessage(role: .assistant, text: streamingBuffer)
        conversation.messages.append(assistantMessage)
        conversation.updatedAt = Date()
        conversationService.persist(conversation)
        history = conversationService.loadRecentConversations()
        streamingBuffer = ""
        isStreaming = false
    }

    private func buildContext() -> ConversationContext {
        var snippets: [String] = []
        if let importedDocument {
            snippets.append("Document: \(importedDocument.title)\n\(importedDocument.content.prefix(1200))")
        }
        if !knowledgeResults.isEmpty {
            let joined = knowledgeResults.map { "\($0.title): \($0.path)" }
            snippets.append(contentsOf: joined)
        }
        let digest = notificationViewModel.summary(limit: 5)
        return ConversationContext(
            selectedDocument: importedDocument,
            notificationDigest: digest,
            clipboardPreview: clipboardBanner,
            knowledgeBaseSnippets: snippets,
            macroSummary: macroLogs.map { $0.message }.joined(separator: "\n"),
            requestedAction: selectedQuickAction
        )
    }

    func importDocuments(urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let doc = try documentService.importDocument(at: url)
            importedDocument = doc
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func selectDocumentUsingPanel() {
        let urls = documentService.openPanelToSelectDocuments()
        importDocuments(urls: urls)
    }

    func clearDocument() {
        importedDocument = nil
    }

    func summarizeDocument(action: DocumentAction) {
        guard importedDocument != nil else {
            statusMessage = "Import a document first"
            return
        }
        selectedQuickAction = QuickAction(title: action.rawValue, kind: .summarizeClipboard, icon: "doc.text")
        send(prompt: "Please \(action.rawValue.lowercased()) for the attached document context.")
    }

    func runTableExtraction() {
        guard let text = clipboardBanner ?? importedDocument?.content else {
            statusMessage = "Copy or import a table first"
            return
        }
        tableResult = tableExtractor.extract(from: text)
    }

    func searchKnowledgeBase() {
        Task {
            do {
                let results = try await localIndexService.search(query: knowledgeQuery, limit: 5)
                await MainActor.run {
                    self.knowledgeResults = results
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Search failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func refreshMacros() {
        macroLogs = []
    }

    func runMacro(_ macro: Macro) {
        Task {
            let logs = await workflowEngine.run(macro, settings: settingsStore.current)
            await MainActor.run {
                self.macroLogs = logs
                self.selectedTab = .macros
            }
        }
    }

    func approvePendingTool() {
        guard let invocation = pendingTool else { return }
        toolRequiresConfirmation = false
        pendingTool = nil
        Task {
            await handleTool(invocation: invocation)
        }
    }

    func rejectPendingTool() {
        pendingTool = nil
        toolRequiresConfirmation = false
    }

    private func handleTool(invocation: ToolInvocation) async {
        do {
            let result = try await toolService.execute(invocation, context: ToolExecutionContext(settings: settingsStore.current, requestedByUser: false))
            let toolMessage = ChatMessage(role: .tool, text: result.content, metadata: result.metadata)
            conversation.messages.append(toolMessage)
        } catch {
            statusMessage = "Tool failed: \(error.localizedDescription)"
        }
    }

    func performQuickAction(_ action: QuickAction) {
        selectedQuickAction = action
        switch action.kind {
        case .summarizeClipboard:
            if let clipboard = clipboardBanner {
                send(prompt: "Summarize this clipboard content:\n\(clipboard)")
            }
        case .fixClipboardGrammar:
            if let clipboard = clipboardBanner {
                send(prompt: "Improve grammar and clarity:\n\(clipboard)")
            }
        case .makeChecklist:
            if let clipboard = clipboardBanner {
                send(prompt: "Turn this into a checklist:\n\(clipboard)")
            }
        case .draftEmail:
            selectedTab = .documents
        case .extractTable:
            runTableExtraction()
        case .meetingSummary:
            if let clipboard = clipboardBanner {
                send(prompt: "Summarize this meeting transcript with decisions and follow-ups:\n\(clipboard)")
            }
        case .codeHelper:
            if let clipboard = clipboardBanner {
                send(prompt: "Explain this code and suggest tests:\n\(clipboard)")
            }
        case .searchKnowledgeBase:
            selectedTab = .knowledge
        case .workflowMacro:
            selectedTab = .macros
        }
    }

    func clearHistory() {
        conversation = Conversation(title: "New Chat", model: settingsStore.selectedModel())
        history = []
        conversationService.clearHistory()
    }

    func selectConversation(_ conversation: Conversation) {
        self.conversation = conversation
    }

    func clearClipboardBanner() {
        clipboardBanner = nil
    }

    func loadModels() {
        Task {
            do {
                let models = try await ollama.listModels()
                await MainActor.run {
                    self.availableModels = models.map { $0.name }
                    self.ollamaReachable = true
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Model list failed: \(error.localizedDescription)"
                    self.shouldShowOllamaRestart()
                }
            }
        }
    }

    private func shouldShowOllamaRestart() {
        ollamaReachable = false
    }

    private func handleClipboardWatcherToggle(enabled: Bool) {
        if enabled {
            clipboardWatcher.start()
        } else {
            clipboardWatcher.stop()
            clipboardBanner = nil
        }
    }

    var availableMacros: [Macro] {
        macroService.macros
    }
}
