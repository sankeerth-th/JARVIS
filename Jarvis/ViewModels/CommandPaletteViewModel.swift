import Foundation
import Combine
import AppKit

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    enum PaletteTab: String, CaseIterable {
        case chat = "Chat"
        case notifications = "Notifications"
        case documents = "Documents"
        case email = "Email"
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
    @Published var documentActionOutput: String = ""
    @Published var isDocumentActionRunning: Bool = false

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
    private var clipboardWatcherEnabled = false
    private var rawStreamingBuffer: String = ""
    private var handledToolInvocationKeys: Set<String> = []

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
        self.clipboardWatcherEnabled = settingsStore.clipboardWatcherEnabled()

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
                guard let self else { return }
                if self.quickActions != settings.quickActions {
                    self.quickActions = settings.quickActions
                }
                if self.privacyStatus != settings.privacyStatus {
                    self.privacyStatus = settings.privacyStatus
                }
                self.handleClipboardWatcherToggle(enabled: settings.clipboardWatcherEnabled)
            }
            .store(in: &cancellables)
        clipboardWatcher.onTextChange = { [weak self] text in
            Task { @MainActor in
                self?.clipboardBanner = String(text.prefix(500))
            }
        }
        if clipboardWatcherEnabled {
            clipboardWatcher.start()
        } else {
            clipboardWatcher.stop()
        }
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
        rawStreamingBuffer = ""
        handledToolInvocationKeys = []
        streamingBuffer = ""
        isStreaming = true
        let context = buildContext()
        streamTask?.cancel()
        streamTask = Task {
            do {
                let stream = conversationService.streamResponse(for: prompt, conversation: convo, context: context, settings: settingsStore.current)
                for try await chunk in stream {
                    consume(chunk: chunk)
                }
                finishStreaming()
            } catch {
                statusMessage = "Ollama error: \(error.localizedDescription)"
                isStreaming = false
            }
        }
    }

    private func consume(chunk: String) {
        rawStreamingBuffer.append(chunk)
        let (cleaned, invocations) = parser.extractInvocations(from: rawStreamingBuffer)
        streamingBuffer = cleaned
        for invocation in invocations {
            let invocationKey = toolInvocationKey(invocation)
            guard handledToolInvocationKeys.contains(invocationKey) == false else { continue }
            handledToolInvocationKeys.insert(invocationKey)
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
        rawStreamingBuffer = ""
        handledToolInvocationKeys = []
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
            documentActionOutput = ""
            statusMessage = "Imported \(doc.title)"
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
        documentActionOutput = ""
    }

    func copyDocumentOutput() {
        let output = documentActionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        statusMessage = "Document output copied"
    }

    func summarizeDocument(action: DocumentAction) {
        guard let importedDocument else {
            statusMessage = "Import a document first"
            return
        }
        statusMessage = "Running \(action.rawValue)…"
        selectedQuickAction = QuickAction(title: action.rawValue, kind: .summarizeClipboard, icon: "doc.text")
        isDocumentActionRunning = true
        Task {
            do {
                let output = try await conversationService.performDocumentAction(document: importedDocument, action: action, settings: settingsStore.current)
                self.documentActionOutput = output
                self.statusMessage = "\(action.rawValue) complete."
                self.isDocumentActionRunning = false
            } catch {
                self.statusMessage = "\(action.rawValue) failed: \(error.localizedDescription)"
                self.isDocumentActionRunning = false
            }
        }
    }

    func runTableExtraction() {
        guard let text = clipboardBanner ?? importedDocument?.content else {
            statusMessage = "Copy or import a table first"
            return
        }
        let localResult = tableExtractor.extract(from: text)
        tableResult = localResult
        guard shouldUseModelTableFallback(localResult) else {
            statusMessage = "Table extracted locally."
            return
        }
        statusMessage = "Refining table with model…"
        Task {
            do {
                if let improved = try await conversationService.inferTable(text: text, settings: settingsStore.current) {
                    await MainActor.run {
                        self.tableResult = improved
                        self.statusMessage = "Table extraction improved."
                    }
                } else {
                    await MainActor.run {
                        self.statusMessage = "Used local table extraction."
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Used local table extraction (\(error.localizedDescription))."
                }
            }
        }
    }

    func searchKnowledgeBase() {
        Task {
            do {
                let results = try await localIndexService.search(query: knowledgeQuery, limit: 5)
                await MainActor.run {
                    self.knowledgeResults = results
                    if results.isEmpty {
                        self.statusMessage = "No local matches. Add a folder in Knowledge and re-index."
                    } else {
                        self.statusMessage = "Found \(results.count) local match(es)."
                    }
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
            selectedTab = .email
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
                let names = models.map { $0.name }
                await MainActor.run {
                    self.availableModels = names
                    self.ollamaReachable = true
                    if !names.contains(self.settingsStore.selectedModel()), let first = names.first {
                        self.settingsStore.setModel(first)
                        self.statusMessage = "Model switched to \(first) (previous selection was unavailable)."
                    }
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
        guard enabled != clipboardWatcherEnabled else { return }
        clipboardWatcherEnabled = enabled
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

    var latestAssistantMessage: String? {
        conversation.messages.last(where: { $0.role == .assistant })?.text
    }

    private func toolInvocationKey(_ invocation: ToolInvocation) -> String {
        let args = invocation.arguments.keys.sorted().map { "\($0)=\(invocation.arguments[$0] ?? "")" }.joined(separator: "&")
        return "\(invocation.name.rawValue)|\(args)"
    }

    private func shouldUseModelTableFallback(_ result: TableExtractionResult) -> Bool {
        if result.rows.count < 2 {
            return true
        }
        if result.headers.count == 1, result.rows.count >= 3 {
            return true
        }
        let filledCells = result.rows.reduce(0) { partial, row in
            partial + row.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        }
        return filledCells <= result.rows.count
    }
}
