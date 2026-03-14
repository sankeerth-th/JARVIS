import Foundation
import Combine
import AppKit

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    struct TopSuggestion: Equatable {
        let title: String
        let subtitle: String
        let confidence: Int
        let actionKind: QuickAction.ActionKind
        let reasons: [String]
    }

    enum PaletteTab: String, CaseIterable {
        case chat = "Chat"
        case notifications = "Notifications"
        case documents = "Documents"
        case email = "Email"
        case why = "Why"
        case fileSearch = "Search"
        case thinking = "Think"
        case privacy = "Privacy"
        case macros = "Macros"
        case diagnostics = "Diagnostics"
    }

    enum FileSearchScope: String, CaseIterable, Identifiable {
        case allIndexed = "All indexed folders"
        case selectedFolder = "Single folder"
        var id: String { rawValue }
    }

    enum IndexPresetFolder: String, CaseIterable, Identifiable {
        case desktop = "Desktop"
        case documents = "Documents"
        case downloads = "Downloads"
        var id: String { rawValue }
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
    @Published var routingDebugSummary: String = ""
    @Published var routeExecutionState: RouteExecutionState = .idle
    @Published var routeExecutionReason: String = ""
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
    @Published var whySymptom: WhySymptom = .notificationOverload
    @Published var whyAdditionalNotes: String = ""
    @Published var whyReport: String = ""
    @Published var isWhyRunning: Bool = false
    @Published var fileSearchQuery: String = ""
    @Published var fileSearchResults: [FileSearchResult] = []
    @Published var fileSearchSummary: String = ""
    @Published var fileSearchStatus: String = ""
    @Published var fileSearchScope: FileSearchScope = .allIndexed
    @Published var fileSearchSelectedFolder: String = ""
    @Published var isIndexingSearchFolders: Bool = false
    @Published var fileSearchShowDebugDetails: Bool = false
    @Published var privacyWarning: String? = nil
    @Published var privacyReport: String = ""
    @Published var privacyEvents: [FeatureEvent] = []
    @Published var thinkProblemStatement: String = ""
    @Published var thinkConstraints: String = ""
    @Published var thinkOptionsInput: String = ""
    @Published var thinkEntries: [ThinkingEntry] = []
    @Published var thinkAnswerDraft: String = ""
    @Published var thinkRecommendation: String = ""
    @Published var thinkSimulation: String = ""
    @Published var topSuggestion: TopSuggestion? = nil
    @Published var thinkingStatus: String = ""

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
    private let intentClassifier = IntentClassifier()
    private let routePlanner = RoutePlanner()
    private let parser = ToolInvocationParser()
    private var streamTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var clipboardWatcherEnabled = false
    private var rawStreamingBuffer: String = ""
    private var handledToolInvocationKeys: Set<String> = []
    private var thinkingQuestionCount = 0
    private let commandHistoryStore = CommandHistoryStore()
    private var promptRecallCursor: Int = -1
    private var hasReceivedStreamingToken = false
    private var streamOwnership = StreamOwnershipController()
    private var pendingToolRequestID: UUID?
    private var knowledgeContextResults: [KnowledgeSearchResult] = []

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
        self.clipboardWatcherEnabled = shouldEnableClipboardWatcher(settings: settingsStore.current)

        bind()
        loadModels()
        refreshTopSuggestion()
    }

    private func bind() {
        notificationViewModel.$notifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.notificationsPreview = Array(items.prefix(5))
                self?.refreshTopSuggestion()
            }
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
                self.handleClipboardWatcherToggle(enabled: self.shouldEnableClipboardWatcher(settings: settings))
                self.refreshTopSuggestion()
            }
            .store(in: &cancellables)
        clipboardWatcher.onTextChange = { [weak self] text in
            Task { @MainActor in
                self?.handleClipboardUpdate(text)
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
        privacyEvents = diagnosticsService.recentEvents(limit: 50, feature: "Privacy guardian")
    }

    func showOverlay() {
        refreshTopSuggestion()
        shouldShowOverlay = true
    }
    func hideOverlay() { shouldShowOverlay = false }

    func selectTab(_ tab: PaletteTab) {
        if tab != selectedTab, tab != .chat, streamOwnership.activeRequest != nil {
            cancelActiveStream(reason: "tab_switched:\(tab.rawValue)")
        }
        selectedTab = tab
        if tab == .fileSearch {
            ensureFileSearchFolderSelection()
        }
        refreshTopSuggestion()
    }

    func sendCurrentPrompt() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            executeTopSuggestion()
            return
        }
        promptRecallCursor = -1
        if handlePaletteCommand(trimmed) {
            inputText = ""
            return
        }
        send(prompt: trimmed, requestedAction: nil)
        inputText = ""
    }

    func send(prompt: String, requestedAction: QuickAction? = nil) {
        commandHistoryStore.recordPrompt(prompt)
        let promptInsights = analyzePrompt(prompt)
        thinkingStatus = promptInsights.thinkingMessage
        statusMessage = promptInsights.statusMessage
        routeExecutionState = .analyzingInput
        routeExecutionReason = "Analyzing prompt and active UI context"
        let signal = routeSignal(for: requestedAction)
        let classification = intentClassifier.classify(prompt: prompt, signal: signal)
        let routePlan = routePlanner.makePlan(classification: classification, signal: signal)
        cancelActiveStream(reason: "new_request_started")
        var convo = conversation
        let activeRequest = streamOwnership.begin(conversationID: convo.id, routePlan: routePlan)
        let userMessage = ChatMessage(
            role: .user,
            text: prompt,
            metadata: requestMetadata(
                requestID: activeRequest.requestID,
                routePlan: routePlan,
                source: "route.user"
            )
        )
        convo.messages.append(userMessage)
        convo.updatedAt = Date()
        conversation = convo
        conversationService.persist(convo)
        rawStreamingBuffer = ""
        handledToolInvocationKeys = []
        streamingBuffer = ""
        hasReceivedStreamingToken = false
        isStreaming = true
        refreshTopSuggestion()
        routeExecutionState = .routeSelected
        routeExecutionReason = classification.reasons.joined(separator: "; ")
        routingDebugSummary = routeSummary(request: activeRequest, classification: classification)
        diagnosticsService.logEvent(
            feature: "Routing",
            type: "route.selected",
            summary: "Selected route for prompt",
            metadata: [
                "requestID": activeRequest.requestID.uuidString,
                "intent": routePlan.intent.rawValue,
                "promptTemplate": routePlan.promptTemplate.rawValue,
                "memoryScope": routePlan.memoryScope.rawValue,
                "contextPolicy": contextPolicySummary(routePlan.contextPolicy),
                "allowedTools": routePlan.allowedTools.map(\.rawValue).joined(separator: ","),
                "surface": signal.selectedSurface.rawValue
            ]
        )
        routeExecutionState = .executingRoute
        routeExecutionReason = "Executing \(routePlan.intent.rawValue) with one primary route"
        streamTask = Task {
            await preloadKnowledgeForPromptIfNeeded(prompt, routePlan: routePlan)
            let context = buildContext(routePlan: routePlan, requestedAction: requestedAction)
            do {
                let stream = conversationService.streamResponse(
                    conversation: convo,
                    context: context,
                    routePlan: routePlan,
                    settings: settingsStore.current
                )
                for try await chunk in stream {
                    guard streamOwnership.owns(activeRequest.requestID) else { break }
                    consume(
                        chunk: chunk,
                        requestID: activeRequest.requestID,
                        conversationID: activeRequest.conversationID,
                        routePlan: routePlan
                    )
                }
                finishStreaming(requestID: activeRequest.requestID, conversationID: activeRequest.conversationID)
            } catch {
                guard streamOwnership.owns(activeRequest.requestID) else { return }
                statusMessage = "Ollama error: \(error.localizedDescription)"
                routeExecutionState = .failed
                routeExecutionReason = error.localizedDescription
                diagnosticsService.logEvent(feature: "Chat", type: "error", summary: "Chat request failed", metadata: ["error": error.localizedDescription])
                appendMessageToConversation(
                    id: activeRequest.conversationID,
                    message: ChatMessage(role: .assistant, text: "I could not reach the selected Ollama model. Check Diagnostics and retry.")
                )
                thinkingStatus = ""
                isStreaming = false
                streamOwnership.complete(requestID: activeRequest.requestID)
            }
        }
    }

    private func consume(chunk: String, requestID: UUID, conversationID: UUID, routePlan: RoutePlan) {
        guard streamOwnership.owns(requestID) else { return }
        rawStreamingBuffer.append(chunk)
        if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !hasReceivedStreamingToken {
            hasReceivedStreamingToken = true
            thinkingStatus = "Generating answer in real time..."
            routeExecutionState = .streamingResponse
            routeExecutionReason = "Active request owns streaming sink"
        }
        guard rawStreamingBuffer.contains("tool{") else {
            streamingBuffer = rawStreamingBuffer
            return
        }
        let (cleaned, invocations) = parser.extractInvocations(from: rawStreamingBuffer)
        streamingBuffer = cleaned
        for invocation in invocations {
            let invocationKey = toolInvocationKey(invocation)
            guard handledToolInvocationKeys.contains(invocationKey) == false else { continue }
            handledToolInvocationKeys.insert(invocationKey)
            guard routePlan.allowedTools.contains(invocation.name) else {
                diagnosticsService.logEvent(
                    feature: "Routing",
                    type: "tool.blocked",
                    summary: "Blocked tool not allowed for route",
                    metadata: [
                        "requestID": requestID.uuidString,
                        "tool": invocation.name.rawValue,
                        "intent": routePlan.intent.rawValue
                    ]
                )
                continue
            }
            if toolService.requiresConfirmation(for: invocation.name) {
                pendingTool = invocation
                toolRequiresConfirmation = true
                pendingToolRequestID = requestID
            } else {
                Task {
                    await self.handleTool(invocation: invocation, requestID: requestID, conversationID: conversationID, routePlan: routePlan)
                }
            }
        }
    }

    private func finishStreaming(requestID: UUID, conversationID: UUID) {
        guard streamOwnership.owns(requestID) else { return }
        let finalReply = sanitizeAssistantReply(streamingBuffer)
        appendMessageToConversation(
            id: conversationID,
            message: ChatMessage(
                role: .assistant,
                text: finalReply,
                metadata: responseProvenance(requestID: requestID, routePlan: streamOwnership.activeRequest?.routePlan)
            )
        )
        rawStreamingBuffer = ""
        handledToolInvocationKeys = []
        streamingBuffer = ""
        thinkingStatus = ""
        isStreaming = false
        streamOwnership.complete(requestID: requestID)
        routeExecutionState = .completed
        routeExecutionReason = "Stream completed and response persisted"
        diagnosticsService.logEvent(
            feature: "Routing",
            type: "stream.completed",
            summary: "Completed streaming request",
            metadata: ["requestID": requestID.uuidString, "conversationID": conversationID.uuidString]
        )
    }

    private func sanitizeAssistantReply(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "I could not generate a useful answer. Please retry."
        }
        let blockedPhrases = [
            "what can i do for you",
            "i'm here and ready when you are",
            "hello! 😊 i'm here and ready when you are"
        ]
        let normalizedLines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                let lower = line.lowercased()
                return !blockedPhrases.contains(where: lower.contains)
            }
            .filter { !$0.isEmpty }
        let cleaned = normalizedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "I could not generate a useful answer. Please retry."
        }
        return cleaned
    }

    private func analyzePrompt(_ prompt: String) -> (thinkingMessage: String, statusMessage: String?) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let likelyUnclear = tokens.count < 3
            || trimmed.contains("??")
            || trimmed.range(of: "\\b(pls|plz|asap|idk|wanna|gimme)\\b", options: .regularExpression) != nil
        if likelyUnclear {
            return (
                thinkingMessage: "Interpreting your request and correcting wording...",
                statusMessage: "I will infer intent first, then answer."
            )
        }
        if tokens.count <= 8 {
            return (
                thinkingMessage: "Fast mode: concise answer...",
                statusMessage: nil
            )
        }
        return (
            thinkingMessage: "Breaking down the request before answering...",
            statusMessage: nil
        )
    }

    private func preloadKnowledgeForPromptIfNeeded(_ prompt: String, routePlan: RoutePlan) async {
        let normalized = prompt.lowercased()
        guard routePlan.contextPolicy.includeKnowledgeContext else {
            knowledgeContextResults = []
            return
        }
        
        // Broader auto-trigger: check if query likely refers to local knowledge
        let shouldSearch = promptContainsAny(normalized, keywords: [
            "search", "find", "file", "pdf", "photo", "image", "document",
            "my resume", "my cv", "my notes", "what did i write", "where did i save",
            "summarize my", "what's in my", "the report", "the invoice"
        ]) || shouldAutoTriggerKnowledgeSearch(normalized)
        
        guard shouldSearch else {
            knowledgeContextResults = []
            return
        }
        
        do {
            let roots = settingsStore.current.indexedFolders
            let results = try await localIndexService.searchFiles(
                query: prompt,
                limit: 8,
                queryExpansionModel: settingsStore.current.selectedModel,
                rootFolders: roots.isEmpty ? nil : roots
            )
            
            // Map to enriched KnowledgeSearchResult with excerpts
            let enrichedResults = results.map { result -> KnowledgeSearchResult in
                KnowledgeSearchResult(
                    title: result.document.title,
                    path: result.document.path,
                    excerpt: result.snippet,
                    score: result.score,
                    sourceType: inferSourceType(from: result.document.path)
                )
            }
            
            await MainActor.run {
                self.knowledgeContextResults = enrichedResults
            }
        } catch {
            await MainActor.run {
                self.knowledgeContextResults = []
            }
            // Keep chat responsive even if semantic preload fails.
        }
    }
    
    private func shouldAutoTriggerKnowledgeSearch(_ normalized: String) -> Bool {
        // Detect likely knowledge-seeking questions
        let patterns = [
            "what does my", "where is my", "content of my", "text from my",
            "explain the", "summarize the", "what's in the", "information about the"
        ]
        return patterns.contains { normalized.contains($0) }
    }
    
    private func inferSourceType(from path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "pdf": return "PDF"
        case "txt", "md", "markdown", "text", "rtf": return "Text"
        case "docx": return "Word"
        case "png", "jpg", "jpeg", "heic", "tif", "tiff": return "Image"
        default: return nil
        }
    }

    private func buildContext(routePlan: RoutePlan, requestedAction: QuickAction?) -> ConversationContext {
        // Use enriched knowledge results if available, fallback to legacy snippets
        let hasEnrichedResults = !knowledgeContextResults.isEmpty
        let knowledgeSnippets: [String] = routePlan.contextPolicy.includeKnowledgeContext && !hasEnrichedResults
            ? knowledgeContextResults.map { "\($0.title): \($0.path)" }
            : []
        let digest = routePlan.contextPolicy.includeNotificationContext ? notificationViewModel.summary(limit: 5) : nil

        return ConversationContext(
            selectedDocument: routePlan.contextPolicy.includeDocumentContext ? importedDocument : nil,
            notificationDigest: digest,
            clipboardPreview: routePlan.contextPolicy.includeClipboardContext ? clipboardBanner : nil,
            knowledgeBaseSnippets: knowledgeSnippets,
            knowledgeSearchResults: routePlan.contextPolicy.includeKnowledgeContext ? knowledgeContextResults : [],
            macroSummary: routePlan.contextPolicy.includeMacroContext ? macroLogs.map { $0.message }.joined(separator: "\n") : nil,
            requestedAction: requestedAction
        )
    }

    private func promptContainsAny(_ prompt: String, keywords: [String]) -> Bool {
        keywords.contains { prompt.contains($0) }
    }

    private func routeSignal(for requestedAction: QuickAction?) -> RouteSignal {
        RouteSignal(
            selectedSurface: selectedTab.conversationSurface,
            quickActionKind: requestedAction?.kind,
            hasImportedDocument: importedDocument != nil,
            hasClipboardText: !(clipboardBanner?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            hasIndexedFolders: !settingsStore.current.indexedFolders.isEmpty
        )
    }

    private func routeSummary(request: StreamRequest, classification: IntentClassification) -> String {
        let reasons = classification.reasons.prefix(2).joined(separator: "; ")
        return "Route \(request.routePlan.intent.rawValue) | state \(routeExecutionState.rawValue) | scope \(request.routePlan.memoryScope.rawValue) | request \(request.requestID.uuidString.prefix(8)) | \(reasons)"
    }

    private func cancelActiveStream(reason: String) {
        streamTask?.cancel()
        streamTask = nil
        if let active = streamOwnership.cancelActive() {
            diagnosticsService.logEvent(
                feature: "Routing",
                type: "stream.cancelled",
                summary: "Cancelled active stream",
                metadata: [
                    "requestID": active.requestID.uuidString,
                    "conversationID": active.conversationID.uuidString,
                    "reason": reason
                ]
            )
            routeExecutionState = .cancelled
            routeExecutionReason = reason
        }
        pendingTool = nil
        pendingToolRequestID = nil
        toolRequiresConfirmation = false
        rawStreamingBuffer = ""
        handledToolInvocationKeys = []
        streamingBuffer = ""
        isStreaming = false
        if streamOwnership.activeRequest == nil, routeExecutionState != .cancelled {
            routeExecutionState = .idle
            routeExecutionReason = ""
        }
    }

    private func appendMessageToConversation(id: UUID, message: ChatMessage) {
        if conversation.id == id {
            conversation.messages.append(message)
            conversation.updatedAt = Date()
            conversationService.persist(conversation)
            history = conversationService.loadRecentConversations()
            return
        }
        var recent = conversationService.loadRecentConversations()
        guard var target = recent.first(where: { $0.id == id }) else { return }
        target.messages.append(message)
        target.updatedAt = Date()
        conversationService.persist(target)
        recent = conversationService.loadRecentConversations()
        history = recent
        if conversation.id == id, let refreshed = recent.first(where: { $0.id == id }) {
            conversation = refreshed
        }
    }

    private func contextPolicySummary(_ policy: RouteContextPolicy) -> String {
        var parts: [String] = []
        if policy.includeDocumentContext { parts.append("document") }
        if policy.includeNotificationContext { parts.append("notifications") }
        if policy.includeClipboardContext { parts.append("clipboard") }
        if policy.includeKnowledgeContext { parts.append("knowledge") }
        if policy.includeMacroContext { parts.append("macro") }
        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }

    private func responseProvenance(requestID: UUID, routePlan: RoutePlan?) -> [String: String] {
        guard let routePlan else {
            return ["requestID": requestID.uuidString, "source": "route.unknown"]
        }
        return requestMetadata(
            requestID: requestID,
            routePlan: routePlan,
            source: "route.\(routePlan.intent.rawValue)"
        )
    }

    private func requestMetadata(requestID: UUID, routePlan: RoutePlan, source: String) -> [String: String] {
        [
            "requestID": requestID.uuidString,
            "intent": routePlan.intent.rawValue,
            "promptTemplate": routePlan.promptTemplate.rawValue,
            "memoryScope": routePlan.memoryScope.rawValue,
            "source": source
        ]
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
        if !knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fileSearchQuery = knowledgeQuery
        }
        selectedTab = .fileSearch
        runFileSearch()
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

    func runWhyAnalysis() {
        let notes = whyAdditionalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        isWhyRunning = true
        whyReport = ""
        Task {
            let signals = diagnosticsService.snapshotSignals()
            let recentErrors = diagnosticsService.recentErrors(limit: 5)
            let recentEvents = diagnosticsService.recentEvents(limit: 5)
            let recentApps = diagnosticsService.recentFrontmostApps(limit: 8)
            let canUseNotifications = await diagnosticsService.isNotificationPermissionGranted()
            let notificationDigest = canUseNotifications ? notificationViewModel.summary(limit: 8) : "Notification permission missing."
            var missingData: [String] = []
            if !canUseNotifications {
                missingData.append("Notifications (permission missing)")
            }
            if recentEvents.isEmpty {
                missingData.append("Recent Jarvis feature events (none)")
            }
            let prompt = """
            Explain a likely root cause for this symptom using local-only signals.
            Return sections exactly:
            Likely Causes
            What data was used
            What data was NOT used
            Recommended fixes

            Include confidence percentages for each likely cause.

            Symptom: \(whySymptom.rawValue)
            User note: \(notes.isEmpty ? "None" : notes)

            System signals:
            \(signals.map { "- \($0.key): \($0.value)" }.joined(separator: "\n"))

            Recent Jarvis errors:
            \(recentErrors.map { "- [\($0.feature)] \($0.summary)" }.joined(separator: "\n"))

            Recent events:
            \(recentEvents.map { "- [\($0.feature)] \($0.summary)" }.joined(separator: "\n"))

            Recent app switches:
            \(recentApps.map { "- \($0)" }.joined(separator: "\n"))

            Notification summary:
            \(notificationDigest)

            Missing data:
            \(missingData.map { "- \($0)" }.joined(separator: "\n"))
            """
            do {
                let response = try await ollama.generate(
                    request: GenerateRequest(
                        model: settingsStore.current.selectedModel,
                        prompt: prompt,
                        system: "You are Jarvis Why Mode. Use only provided local signals and be transparent.",
                        stream: false,
                        options: ["temperature": 0.2, "num_predict": 500]
                    )
                )
                await MainActor.run {
                    self.whyReport = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.isWhyRunning = false
                    self.diagnosticsService.logEvent(feature: "Why happened mode", type: "run", summary: "Generated root-cause report", metadata: ["symptom": self.whySymptom.rawValue])
                }
            } catch {
                await MainActor.run {
                    self.whyReport = "Could not generate analysis: \(error.localizedDescription)"
                    self.isWhyRunning = false
                    self.diagnosticsService.logEvent(feature: "Why happened mode", type: "error", summary: "Why mode failed", metadata: ["error": error.localizedDescription])
                }
            }
        }
    }

    func copyWhyReport() {
        guard !whyReport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(whyReport, forType: .string)
        statusMessage = "Why report copied."
    }

    func createChecklistFromWhyReport() {
        let items = checklistItems(from: whyReport)
        guard !items.isEmpty else {
            statusMessage = "No actionable checklist items found."
            return
        }
        let id = diagnosticsService.createChecklist(title: "Why Mode - \(whySymptom.rawValue)", items: items)
        statusMessage = "Checklist saved (\(id.uuidString.prefix(8)))."
        diagnosticsService.logEvent(feature: "Why happened mode", type: "checklist", summary: "Created checklist from why report", metadata: ["count": "\(items.count)"])
    }

    func runFileSearch() {
        let query = fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[DEBUG] runFileSearch called with query: '\(query)'")
        guard !query.isEmpty else {
            fileSearchStatus = "Enter a query."
            fileSearchResults = []
            print("[DEBUG] Query is empty, returning")
            return
        }
        ensureFileSearchFolderSelection()
        fileSearchStatus = "Searching local files..."
        let roots: [String]? = {
            switch fileSearchScope {
            case .allIndexed:
                return settingsStore.current.indexedFolders.isEmpty ? nil : settingsStore.current.indexedFolders
            case .selectedFolder:
                let selected = fileSearchSelectedFolder.trimmingCharacters(in: .whitespacesAndNewlines)
                return selected.isEmpty ? nil : [selected]
            }
        }()
        Task {
            do {
                print("[DEBUG] Calling localIndexService.searchFiles with roots: \(roots ?? ["nil"])")
                let results = try await localIndexService.searchFiles(
                    query: query,
                    limit: 20,
                    queryExpansionModel: nil,
                    rootFolders: roots
                )
                print("[DEBUG] Search returned \(results.count) results")
                await MainActor.run {
                    self.fileSearchResults = results
                    self.fileSearchStatus = results.isEmpty ? "No matches." : "Found \(results.count) result(s)."
                    self.knowledgeResults = results.map { $0.document }
                    print("[DEBUG] Updated knowledgeResults with \(self.knowledgeResults.count) items")
                    self.diagnosticsService.logEvent(feature: "Semantic search", type: "run", summary: "Search executed", metadata: ["query": query, "results": "\(results.count)"])
                }
            } catch {
                print("[DEBUG] Search failed with error: \(error)")
                await MainActor.run {
                    self.fileSearchStatus = "Search failed: \(error.localizedDescription)"
                    self.fileSearchResults = []
                    self.diagnosticsService.logEvent(feature: "Semantic search", type: "error", summary: "Search failed", metadata: ["error": error.localizedDescription])
                }
            }
        }
    }

    func ensureFileSearchFolderSelection() {
        let options = fileSearchFolderOptions
        if fileSearchSelectedFolder.isEmpty || !options.contains(fileSearchSelectedFolder) {
            fileSearchSelectedFolder = options.first ?? ""
        }
    }

    func addFolderForSearchIndex() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let folder = panel.urls.first else { return }
        indexSearchFolder(folder)
    }

    func indexPresetFolder(_ preset: IndexPresetFolder) {
        let manager = FileManager.default
        let directory: FileManager.SearchPathDirectory
        switch preset {
        case .desktop: directory = .desktopDirectory
        case .documents: directory = .documentDirectory
        case .downloads: directory = .downloadsDirectory
        }
        guard let url = manager.urls(for: directory, in: .userDomainMask).first else { return }
        indexSearchFolder(url)
    }

    func reindexSearchFolders() {
        let folders = settingsStore.current.indexedFolders
        guard !folders.isEmpty else {
            fileSearchStatus = "Add at least one folder to index."
            return
        }
        isIndexingSearchFolders = true
        fileSearchStatus = "Re-indexing \(folders.count) folder(s)..."
        Task {
            var total = 0
            for path in folders {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                let count = (try? await localIndexService.indexFolder(url)) ?? 0
                total += count
            }
            await MainActor.run {
                self.isIndexingSearchFolders = false
                self.fileSearchStatus = "Indexed \(total) files across \(folders.count) folder(s). OCR is applied for images and scanned PDFs."
            }
        }
    }

    private func indexSearchFolder(_ folder: URL) {
        isIndexingSearchFolders = true
        fileSearchStatus = "Indexing \(folder.lastPathComponent)..."
        Task {
            do {
                let count = try await localIndexService.indexFolder(folder)
                await MainActor.run {
                    self.settingsStore.addIndexedFolder(folder.path)
                    self.ensureFileSearchFolderSelection()
                    self.isIndexingSearchFolders = false
                    self.fileSearchStatus = "Indexed \(count) files from \(folder.lastPathComponent)."
                }
            } catch {
                await MainActor.run {
                    self.isIndexingSearchFolders = false
                    self.fileSearchStatus = "Index failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func openSearchResult(_ result: FileSearchResult) {
        NSWorkspace.shared.open(URL(fileURLWithPath: result.document.path))
    }

    func summarizeSearchResult(_ result: FileSearchResult) {
        let text = result.document.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            fileSearchSummary = "No indexed text for this file."
            return
        }
        Task {
            do {
                let prompt = """
                Summarize this file in two sections:
                1) Short summary (3 lines max)
                2) Key points (bullets)
                File: \(result.document.title)
                Content:
                \(text.prefix(5000))
                """
                let output = try await ollama.generate(
                    request: GenerateRequest(
                        model: settingsStore.current.selectedModel,
                        prompt: prompt,
                        system: "You are Jarvis file summarizer. Be concise.",
                        stream: false,
                        options: ["temperature": 0.2, "num_predict": 280]
                    )
                )
                await MainActor.run {
                    self.fileSearchSummary = output
                    self.diagnosticsService.logEvent(feature: "Semantic search", type: "summarize", summary: "Summarized indexed file", metadata: ["path": result.document.path])
                }
            } catch {
                await MainActor.run {
                    self.fileSearchSummary = "Summary failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleFocusModeCommand() {
        notificationViewModel.toggleFocusMode()
        statusMessage = notificationViewModel.focusModeEnabled ? "Focus mode enabled." : "Focus mode disabled."
        diagnosticsService.logEvent(feature: "Focus mode", type: "toggle", summary: statusMessage ?? "")
        refreshTopSuggestion()
        if notificationViewModel.focusModeEnabled {
            Task {
                await notificationViewModel.refreshPermissionStatus()
                if !notificationViewModel.notificationsPermissionGranted {
                    await MainActor.run {
                        self.statusMessage = "Notifications permission is missing. Open System Settings from Notifications tab."
                    }
                }
            }
        }
    }

    func showNotificationDigestCommand() {
        selectedTab = .notifications
        refreshTopSuggestion()
        Task {
            await notificationViewModel.refreshPermissionStatus()
            if notificationViewModel.notificationsPermissionGranted {
                notificationViewModel.batchDigestNow(model: settingsStore.current.selectedModel)
                diagnosticsService.logEvent(feature: "Focus mode", type: "digest", summary: "Generated notification digest")
            } else {
                await MainActor.run {
                    self.statusMessage = "Notifications permission missing. Open System Settings from Notifications tab."
                }
            }
        }
    }

    func addCurrentAppToPriorityCommand() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            statusMessage = "No active app detected."
            return
        }
        notificationViewModel.addPriorityApp(bundleID)
        statusMessage = "Added \(bundleID) to priority apps."
        diagnosticsService.logEvent(feature: "Focus mode", type: "priority-app", summary: "Added priority app", metadata: ["app": bundleID])
        refreshTopSuggestion()
    }

    func buildPrivacyReport() {
        let since = Date().addingTimeInterval(-24 * 3600)
        let events = diagnosticsService.recentEvents(limit: 200, feature: "Privacy guardian", since: since)
        privacyEvents = events
        guard !events.isEmpty else {
            privacyReport = "No privacy guardian events in the last 24h."
            return
        }
        let input = events.prefix(120).map { "- [\($0.type)] \($0.summary) @ \($0.createdAt.formatted(date: .omitted, time: .shortened))" }.joined(separator: "\n")
        Task {
            do {
                let prompt = """
                Summarize these local privacy events with sections:
                Top risks
                Last 24h highlights
                Recommended actions
                Do not include raw secrets.

                Events:
                \(input)
                """
                let report = try await ollama.generate(
                    request: GenerateRequest(
                        model: settingsStore.current.selectedModel,
                        prompt: prompt,
                        system: "You are Jarvis Privacy Guardian. Keep output concise, no raw secrets.",
                        stream: false,
                        options: ["temperature": 0.1, "num_predict": 320]
                    )
                )
                await MainActor.run {
                    self.privacyReport = report.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.diagnosticsService.logEvent(feature: "Privacy guardian", type: "report", summary: "Generated privacy report")
                }
            } catch {
                await MainActor.run {
                    self.privacyReport = "Privacy report failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearClipboardNow() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("", forType: .string)
        privacyWarning = nil
        diagnosticsService.logEvent(feature: "Privacy guardian", type: "clipboard-clear", summary: "Cleared clipboard from guardian action")
    }

    func nextThinkingQuestion() {
        let problem = thinkProblemStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !problem.isEmpty else {
            statusMessage = "Add a problem statement first."
            return
        }
        Task {
            let options = parsedThinkingOptions
            let transcript = thinkEntries.map { "\($0.role.rawValue.capitalized): \($0.text)" }.joined(separator: "\n")
            let prompt = """
            You are a Socratic thinking companion. Ask exactly one concise next question.
            Problem: \(problem)
            Constraints: \(thinkConstraints)
            Candidate options: \(options.joined(separator: "; "))
            Prior thread:
            \(transcript)
            """
            do {
                let question = try await ollama.generate(
                    request: GenerateRequest(
                        model: settingsStore.current.selectedModel,
                        prompt: prompt,
                        system: "Ask one question at a time, no extra text.",
                        stream: false,
                        options: ["temperature": 0.3, "num_predict": 120]
                    )
                )
                await MainActor.run {
                    let entry = ThinkingEntry(role: .assistant, text: question.trimmingCharacters(in: .whitespacesAndNewlines))
                    self.thinkEntries.append(entry)
                    self.thinkingQuestionCount += 1
                    self.diagnosticsService.logEvent(feature: "Thinking companion", type: "question", summary: "Asked next Socratic question")
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Thinking question failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func submitThinkingAnswer() {
        let answer = thinkAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        thinkEntries.append(ThinkingEntry(role: .user, text: answer))
        thinkAnswerDraft = ""
        if thinkingQuestionCount >= 3 {
            buildThinkingRecommendation()
        }
    }

    func buildThinkingRecommendation() {
        let problem = thinkProblemStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !problem.isEmpty else { return }
        let transcript = thinkEntries.map { "\($0.role.rawValue.capitalized): \($0.text)" }.joined(separator: "\n")
        Task {
            do {
                let prompt = """
                Analyze this decision. Return sections:
                Options (3)
                Pros/Cons
                Risks
                Recommended choice with rationale

                Problem: \(problem)
                Constraints: \(thinkConstraints)
                Options provided: \(parsedThinkingOptions.joined(separator: "; "))
                Conversation:
                \(transcript)
                """
                let result = try await ollama.generate(
                    request: GenerateRequest(
                        model: settingsStore.current.selectedModel,
                        prompt: prompt,
                        system: "Be structured and concise.",
                        stream: false,
                        options: ["temperature": 0.2, "num_predict": 520]
                    )
                )
                await MainActor.run {
                    self.thinkRecommendation = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.diagnosticsService.logEvent(feature: "Thinking companion", type: "recommendation", summary: "Generated decision recommendation")
                }
            } catch {
                await MainActor.run {
                    self.thinkRecommendation = "Could not generate recommendation: \(error.localizedDescription)"
                }
            }
        }
    }

    func simulateThinkingOutcome(option: String) {
        guard !option.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            do {
                let prompt = """
                Simulate outcomes for option: \(option)
                Return sections:
                Best case
                Expected case
                Worst case
                Mitigations
                """
                let result = try await ollama.generate(
                    request: GenerateRequest(
                        model: settingsStore.current.selectedModel,
                        prompt: prompt,
                        system: "Provide pragmatic simulation.",
                        stream: false,
                        options: ["temperature": 0.2, "num_predict": 320]
                    )
                )
                await MainActor.run {
                    self.thinkSimulation = result.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                await MainActor.run {
                    self.thinkSimulation = "Simulation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func saveThinkingSession() {
        let title = thinkProblemStatement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Thinking Session" : String(thinkProblemStatement.prefix(60))
        let session = ThinkingSessionRecord(
            title: title,
            problem: thinkProblemStatement,
            constraints: thinkConstraints,
            options: parsedThinkingOptions,
            entries: thinkEntries,
            summary: thinkRecommendation,
            createdAt: Date(),
            updatedAt: Date()
        )
        diagnosticsService.saveThinkingSession(session)
        statusMessage = "Thinking session saved."
        diagnosticsService.logEvent(feature: "Thinking companion", type: "save", summary: "Saved thinking session", metadata: ["title": title])
    }

    func approvePendingTool() {
        guard let invocation = pendingTool,
              let pendingRequestID = pendingToolRequestID,
              let active = streamOwnership.activeRequest,
              active.requestID == pendingRequestID else { return }
        toolRequiresConfirmation = false
        pendingTool = nil
        pendingToolRequestID = nil
        Task {
            await handleTool(
                invocation: invocation,
                requestID: active.requestID,
                conversationID: active.conversationID,
                routePlan: active.routePlan
            )
        }
    }

    func rejectPendingTool() {
        if let requestID = pendingToolRequestID {
            diagnosticsService.logEvent(
                feature: "Routing",
                type: "tool.rejected",
                summary: "User rejected pending tool invocation",
                metadata: ["requestID": requestID.uuidString]
            )
        }
        pendingTool = nil
        pendingToolRequestID = nil
        toolRequiresConfirmation = false
    }

    private func handleTool(invocation: ToolInvocation, requestID: UUID, conversationID: UUID, routePlan: RoutePlan) async {
        guard streamOwnership.owns(requestID) else { return }
        guard routePlan.allowedTools.contains(invocation.name) else { return }
        do {
            let result = try await toolService.execute(invocation, context: ToolExecutionContext(settings: settingsStore.current, requestedByUser: false))
            let metadata = requestMetadata(
                requestID: requestID,
                routePlan: routePlan,
                source: "route.tool"
            ).merging(result.metadata, uniquingKeysWith: { _, newValue in newValue })
            let toolMessage = ChatMessage(role: .tool, text: result.content, metadata: metadata)
            appendMessageToConversation(id: conversationID, message: toolMessage)
            diagnosticsService.logEvent(
                feature: "Routing",
                type: "tool.executed",
                summary: "Executed route-allowed tool",
                metadata: [
                    "requestID": requestID.uuidString,
                    "tool": invocation.name.rawValue,
                    "intent": routePlan.intent.rawValue
                ]
            )
        } catch {
            statusMessage = "Tool failed: \(error.localizedDescription)"
            diagnosticsService.logEvent(
                feature: "Routing",
                type: "tool.error",
                summary: "Tool execution failed",
                metadata: ["requestID": requestID.uuidString, "error": error.localizedDescription]
            )
        }
    }

    func performQuickAction(_ action: QuickAction) {
        commandHistoryStore.recordAction(action.kind)
        switch action.kind {
        case .summarizeClipboard:
            if let clipboard = clipboardBanner {
                send(prompt: "Summarize this clipboard content:\n\(clipboard)", requestedAction: action)
            }
        case .fixClipboardGrammar:
            if let clipboard = clipboardBanner {
                send(prompt: "Improve grammar and clarity:\n\(clipboard)", requestedAction: action)
            }
        case .makeChecklist:
            if let clipboard = clipboardBanner {
                send(prompt: "Turn this into a checklist:\n\(clipboard)", requestedAction: action)
            }
        case .draftEmail:
            selectedTab = .email
        case .extractTable:
            runTableExtraction()
        case .meetingSummary:
            if let clipboard = clipboardBanner {
                send(prompt: "Summarize this meeting transcript with decisions and follow-ups:\n\(clipboard)", requestedAction: action)
            }
        case .codeHelper:
            if let clipboard = clipboardBanner {
                send(prompt: "Explain this code and suggest tests:\n\(clipboard)", requestedAction: action)
            }
        case .searchKnowledgeBase:
            selectedTab = .fileSearch
        case .workflowMacro:
            selectedTab = .macros
        case .whyDidThisHappen:
            selectedTab = .why
        case .searchMyFiles:
            selectedTab = .fileSearch
        case .toggleFocusMode:
            toggleFocusModeCommand()
        case .showNotificationDigest:
            showNotificationDigestCommand()
        case .addCurrentAppToPriority:
            addCurrentAppToPriorityCommand()
        case .privacyReport:
            selectedTab = .privacy
            buildPrivacyReport()
        case .thinkWithMe:
            selectedTab = .thinking
        }
        refreshTopSuggestion()
    }

    func executeTopSuggestion() {
        guard let suggestion = topSuggestion else { return }
        let action = quickAction(for: suggestion.actionKind)
        statusMessage = "Suggestion: \(suggestion.title)"
        performQuickAction(action)
    }

    func refreshSuggestionContext() {
        refreshTopSuggestion()
    }

    func copyLatestAssistantMessage() {
        guard let message = latestAssistantMessage, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
        statusMessage = "Latest response copied."
    }

    func repeatLastPrompt() {
        guard let last = commandHistoryStore.recentPrompts(limit: 1).first else { return }
        inputText = last
        sendCurrentPrompt()
    }

    func recallPrompt(up: Bool) {
        let prompts = commandHistoryStore.recentPrompts(limit: 25)
        guard !prompts.isEmpty else { return }
        if up {
            promptRecallCursor = min(promptRecallCursor + 1, prompts.count - 1)
        } else {
            promptRecallCursor = max(promptRecallCursor - 1, -1)
        }
        if promptRecallCursor == -1 {
            inputText = ""
            return
        }
        inputText = prompts[promptRecallCursor]
    }

    func clearHistory() {
        cancelActiveStream(reason: "history_cleared")
        conversation = Conversation(title: "New Chat", model: settingsStore.selectedModel())
        history = []
        conversationService.clearHistory()
        refreshTopSuggestion()
    }

    func selectConversation(_ conversation: Conversation) {
        if let active = streamOwnership.activeRequest, active.conversationID != conversation.id {
            cancelActiveStream(reason: "conversation_switched")
        }
        self.conversation = conversation
    }

    func clearClipboardBanner() {
        clipboardBanner = nil
        refreshTopSuggestion()
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
                    self.refreshTopSuggestion()
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

    private func shouldEnableClipboardWatcher(settings: AppSettings) -> Bool {
        settings.clipboardWatcherEnabled || (settings.privacyGuardianEnabled && settings.privacyClipboardMonitorEnabled)
    }

    var availableMacros: [Macro] {
        macroService.macros
    }

    var fileSearchFolderOptions: [String] {
        let configured = settingsStore.current.indexedFolders
        let defaults = [
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path,
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        ].compactMap { $0 }
        return Array(Set(configured + defaults)).sorted()
    }

    var latestAssistantMessage: String? {
        conversation.messages.last(where: { $0.role == .assistant })?.text
    }

    var isStreamingSelectedConversation: Bool {
        guard let active = streamOwnership.activeRequest else { return false }
        return isStreaming && active.conversationID == conversation.id
    }

    var visibleStreamingBuffer: String {
        isStreamingSelectedConversation ? streamingBuffer : ""
    }

    var visibleThinkingStatus: String {
        isStreamingSelectedConversation ? thinkingStatus : ""
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

    private func handleClipboardUpdate(_ text: String) {
        clipboardBanner = String(text.prefix(500))
        refreshTopSuggestion()
        let settings = settingsStore.current
        guard settings.privacyGuardianEnabled,
              settings.privacyClipboardMonitorEnabled,
              settings.privacySensitiveDetectionEnabled else {
            privacyWarning = nil
            return
        }
        let findings = detectSensitiveClipboardData(in: text)
        guard !findings.isEmpty else {
            privacyWarning = nil
            return
        }
        let warning = "Sensitive content detected in clipboard: \(findings.joined(separator: ", "))"
        privacyWarning = warning
        diagnosticsService.logEvent(
            feature: "Privacy guardian",
            type: "clipboard-sensitive",
            summary: warning
        )
    }

    private func detectSensitiveClipboardData(in text: String) -> [String] {
        var findings: [String] = []
        let ssnRegex = "\\b\\d{3}-\\d{2}-\\d{4}\\b"
        let apiRegex = "(?i)(api[_-]?key|secret|token)\\s*[:=]\\s*[A-Za-z0-9_\\-]{8,}"
        if text.range(of: ssnRegex, options: .regularExpression) != nil {
            findings.append("SSN pattern")
        }
        if text.range(of: apiRegex, options: .regularExpression) != nil {
            findings.append("API key/token pattern")
        }
        let cardCandidates = text
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { $0.count >= 13 && $0.count <= 19 }
        for candidate in cardCandidates where Self.passesLuhn(candidate) {
            let suffix = String(candidate.suffix(4))
            findings.append("Card ending \(suffix)")
            break
        }
        return findings
    }

    private static func passesLuhn(_ number: String) -> Bool {
        var sum = 0
        let reversed = number.reversed().map { Int(String($0)) ?? 0 }
        for (index, digit) in reversed.enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    private func checklistItems(from report: String) -> [String] {
        let lines = report.components(separatedBy: .newlines)
        var inFixSection = false
        var items: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.localizedCaseInsensitiveContains("Recommended fixes") {
                inFixSection = true
                continue
            }
            if inFixSection && trimmed.isEmpty {
                continue
            }
            if inFixSection {
                if trimmed.hasPrefix("-")
                    || trimmed.hasPrefix("*")
                    || trimmed.hasPrefix("•")
                    || trimmed.range(of: "^\\d+\\.", options: .regularExpression) != nil {
                    let item = trimmed
                        .replacingOccurrences(of: "^[-*•\\d\\.\\s]+", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !item.isEmpty {
                        items.append(item)
                    }
                } else if !trimmed.lowercased().contains("likely causes")
                            && !trimmed.lowercased().contains("what data") {
                    items.append(trimmed)
                }
            }
        }
        return Array(items.prefix(12))
    }

    private var parsedThinkingOptions: [String] {
        thinkOptionsInput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func quickAction(for kind: QuickAction.ActionKind) -> QuickAction {
        if let existing = quickActions.first(where: { $0.kind == kind }) {
            return existing
        }
        return QuickAction.defaults.first(where: { $0.kind == kind }) ?? QuickAction(title: "Suggested action", kind: kind, icon: "bolt")
    }

    private func refreshTopSuggestion() {
        var candidates: [(kind: QuickAction.ActionKind, score: Int, reasons: [String], subtitle: String)] = []
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier?.lowercased() ?? ""
        let appName = frontmost?.localizedName ?? "current app"
        let hasClipboardText = !(clipboardBanner?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let historyWeights = commandHistoryStore.actionWeights()

        func add(_ kind: QuickAction.ActionKind, score: Int, reason: String, subtitle: String) {
            if let index = candidates.firstIndex(where: { $0.kind == kind }) {
                var entry = candidates[index]
                entry.score += score
                if !entry.reasons.contains(reason) {
                    entry.reasons.append(reason)
                }
                candidates[index] = entry
            } else {
                candidates.append((kind: kind, score: score, reasons: [reason], subtitle: subtitle))
            }
        }

        if bundleID.contains("mail") {
            add(.draftEmail, score: 48, reason: "You are in Mail", subtitle: "Draft a reply from current context")
        }
        if bundleID.contains("xcode") {
            add(.codeHelper, score: 44, reason: "You are in Xcode", subtitle: "Explain/refactor/test code quickly")
        }
        if bundleID.contains("finder") {
            add(.searchMyFiles, score: 40, reason: "You are in Finder", subtitle: "Search local files semantically")
        }
        if bundleID.contains("safari") || bundleID.contains("chrome") {
            add(.summarizeClipboard, score: 28, reason: "Browser is active", subtitle: "Summarize selected/copied content")
        }
        if hasClipboardText {
            add(.summarizeClipboard, score: 34, reason: "Clipboard has text", subtitle: "Summarize clipboard content")
        }
        if notificationViewModel.focusModeEnabled, notificationViewModel.lowPriorityCount > 0 {
            add(.showNotificationDigest, score: 36, reason: "Focus Mode has queued notifications", subtitle: "Generate digest for pending alerts")
        }
        if importedDocument != nil {
            add(.searchMyFiles, score: 16, reason: "You recently used documents", subtitle: "Find related local files")
        }

        for (kind, weight) in historyWeights {
            guard weight > 0 else { continue }
            add(kind, score: min(32, 6 * weight), reason: "Based on your recent usage", subtitle: "Frequently used in your workflow")
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            topSuggestion = TopSuggestion(
                title: "Think with me",
                subtitle: "Start a structured decision walkthrough",
                confidence: 52,
                actionKind: .thinkWithMe,
                reasons: ["No strong contextual signal detected"]
            )
            return
        }
        let action = quickAction(for: best.kind)
        let confidence = min(99, max(35, best.score))
        let reasons = Array(best.reasons.prefix(2))
        topSuggestion = TopSuggestion(
            title: action.title,
            subtitle: best.subtitle + " in \(appName).",
            confidence: confidence,
            actionKind: best.kind,
            reasons: reasons
        )
    }

    private func handlePaletteCommand(_ raw: String) -> Bool {
        let command = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch command {
        case "why did this happen?", "why did this happen":
            commandHistoryStore.recordAction(.whyDidThisHappen)
            selectedTab = .why
            refreshTopSuggestion()
            return true
        case "search my files", "find files":
            commandHistoryStore.recordAction(.searchMyFiles)
            selectedTab = .fileSearch
            refreshTopSuggestion()
            return true
        case "toggle focus mode":
            commandHistoryStore.recordAction(.toggleFocusMode)
            toggleFocusModeCommand()
            return true
        case "show notification digest":
            commandHistoryStore.recordAction(.showNotificationDigest)
            showNotificationDigestCommand()
            return true
        case "add current app to priority list":
            commandHistoryStore.recordAction(.addCurrentAppToPriority)
            addCurrentAppToPriorityCommand()
            return true
        case "privacy report":
            commandHistoryStore.recordAction(.privacyReport)
            selectedTab = .privacy
            buildPrivacyReport()
            refreshTopSuggestion()
            return true
        case "think with me":
            commandHistoryStore.recordAction(.thinkWithMe)
            selectedTab = .thinking
            refreshTopSuggestion()
            return true
        default:
            return false
        }
    }
}

private final class CommandHistoryStore {
    private enum Keys {
        static let actionCounts = "jarvis.command_history.action_counts"
        static let prompts = "jarvis.command_history.prompts"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordAction(_ action: QuickAction.ActionKind) {
        var counts = defaults.dictionary(forKey: Keys.actionCounts) as? [String: Int] ?? [:]
        counts[action.rawValue, default: 0] += 1
        defaults.set(counts, forKey: Keys.actionCounts)
    }

    func recordPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var prompts = defaults.stringArray(forKey: Keys.prompts) ?? []
        if let index = prompts.firstIndex(of: trimmed) {
            prompts.remove(at: index)
        }
        prompts.append(trimmed)
        if prompts.count > 40 {
            prompts.removeFirst(prompts.count - 40)
        }
        defaults.set(prompts, forKey: Keys.prompts)
    }

    func actionWeights() -> [QuickAction.ActionKind: Int] {
        let counts = defaults.dictionary(forKey: Keys.actionCounts) as? [String: Int] ?? [:]
        var output: [QuickAction.ActionKind: Int] = [:]
        for (rawKey, value) in counts {
            guard let kind = QuickAction.ActionKind(rawValue: rawKey) else { continue }
            output[kind] = value
        }
        return output
    }

    func recentPrompts(limit: Int) -> [String] {
        let prompts = defaults.stringArray(forKey: Keys.prompts) ?? []
        return Array(prompts.reversed().prefix(max(1, limit)))
    }
}

private extension CommandPaletteViewModel.PaletteTab {
    var conversationSurface: ConversationSurface {
        switch self {
        case .chat: return .chat
        case .notifications: return .notifications
        case .documents: return .documents
        case .email: return .email
        case .why: return .why
        case .fileSearch: return .fileSearch
        case .thinking: return .thinking
        case .privacy: return .privacy
        case .macros: return .macros
        case .diagnostics: return .diagnostics
        }
    }
}
