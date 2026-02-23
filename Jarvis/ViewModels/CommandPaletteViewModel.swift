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
        case why = "Why"
        case fileSearch = "Search"
        case thinking = "Think"
        case privacy = "Privacy"
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
    @Published var whySymptom: WhySymptom = .notificationOverload
    @Published var whyAdditionalNotes: String = ""
    @Published var whyReport: String = ""
    @Published var isWhyRunning: Bool = false
    @Published var fileSearchQuery: String = ""
    @Published var fileSearchResults: [FileSearchResult] = []
    @Published var fileSearchSummary: String = ""
    @Published var fileSearchStatus: String = ""
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
    private var thinkingQuestionCount = 0

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
                self.handleClipboardWatcherToggle(enabled: self.shouldEnableClipboardWatcher(settings: settings))
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

    func showOverlay() { shouldShowOverlay = true }
    func hideOverlay() { shouldShowOverlay = false }

    func selectTab(_ tab: PaletteTab) {
        selectedTab = tab
    }

    func sendCurrentPrompt() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if handlePaletteCommand(trimmed) {
            inputText = ""
            return
        }
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
        selectedQuickAction = nil
        streamTask?.cancel()
        streamTask = Task {
            do {
                let stream = conversationService.streamResponse(conversation: convo, context: context, settings: settingsStore.current)
                for try await chunk in stream {
                    consume(chunk: chunk)
                }
                finishStreaming()
            } catch {
                statusMessage = "Ollama error: \(error.localizedDescription)"
                diagnosticsService.logEvent(feature: "Chat", type: "error", summary: "Chat request failed", metadata: ["error": error.localizedDescription])
                let errorMessage = ChatMessage(role: .assistant, text: "I could not reach the selected Ollama model. Check Diagnostics and retry.")
                conversation.messages.append(errorMessage)
                conversation.updatedAt = Date()
                conversationService.persist(conversation)
                history = conversationService.loadRecentConversations()
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
        let finalReply = sanitizeAssistantReply(streamingBuffer)
        let assistantMessage = ChatMessage(role: .assistant, text: finalReply)
        conversation.messages.append(assistantMessage)
        conversation.updatedAt = Date()
        conversationService.persist(conversation)
        history = conversationService.loadRecentConversations()
        rawStreamingBuffer = ""
        handledToolInvocationKeys = []
        streamingBuffer = ""
        isStreaming = false
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
        guard !query.isEmpty else {
            fileSearchStatus = "Enter a query."
            fileSearchResults = []
            return
        }
        fileSearchStatus = "Searching local files..."
        Task {
            do {
                let results = try await localIndexService.searchFiles(query: query, limit: 20, queryExpansionModel: settingsStore.current.selectedModel)
                await MainActor.run {
                    self.fileSearchResults = results
                    self.fileSearchStatus = results.isEmpty ? "No matches." : "Found \(results.count) result(s)."
                    self.diagnosticsService.logEvent(feature: "Semantic search", type: "run", summary: "Search executed", metadata: ["query": query, "results": "\(results.count)"])
                }
            } catch {
                await MainActor.run {
                    self.fileSearchStatus = "Search failed: \(error.localizedDescription)"
                    self.diagnosticsService.logEvent(feature: "Semantic search", type: "error", summary: "Search failed", metadata: ["error": error.localizedDescription])
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

    private func shouldEnableClipboardWatcher(settings: AppSettings) -> Bool {
        settings.clipboardWatcherEnabled || (settings.privacyGuardianEnabled && settings.privacyClipboardMonitorEnabled)
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

    private func handleClipboardUpdate(_ text: String) {
        clipboardBanner = String(text.prefix(500))
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

    private func handlePaletteCommand(_ raw: String) -> Bool {
        let command = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch command {
        case "why did this happen?", "why did this happen":
            selectedTab = .why
            return true
        case "search my files", "find files":
            selectedTab = .fileSearch
            return true
        case "toggle focus mode":
            toggleFocusModeCommand()
            return true
        case "show notification digest":
            showNotificationDigestCommand()
            return true
        case "add current app to priority list":
            addCurrentAppToPriorityCommand()
            return true
        case "privacy report":
            selectedTab = .privacy
            buildPrivacyReport()
            return true
        case "think with me":
            selectedTab = .thinking
            return true
        default:
            return false
        }
    }
}
