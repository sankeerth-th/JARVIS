import Foundation
import Combine
import AppKit

@MainActor
final class AppEnvironment: ObservableObject {
    let settingsStore = SettingsStore()
    let documentService = DocumentImportService()
    let tableExtractor = TableExtractor()
    let screenshotService = ScreenshotService()
    let ocrService = OCRService()
    let database = JarvisDatabase()
    let ollamaClient = OllamaClient()
    let notificationService = NotificationService()
    let permissionsManager = PermissionsManager.shared
    let clipboardWatcher = ClipboardWatcher()
    let hotKeyCenter = HotKeyCenter()
    let macActionService = JarvisMacActionService()
    lazy var projectActionService = JarvisProjectActionService(actionService: macActionService)
    let safeShellService = JarvisSafeShellService()
    let terminalExecutionService = JarvisTerminalExecutionService()
    let speechInputService = JarvisSpeechInputService()
    let speechOutputService = JarvisSpeechOutputService()
    let wakeSpeechInputService = JarvisSpeechInputService()

    lazy var localIndexService = LocalIndexService(database: database, importService: documentService, ollama: ollamaClient)
    lazy var calculator = Calculator()
    lazy var hostFileService = JarvisHostFileService(localIndexService: localIndexService, macActionService: macActionService)
    lazy var toolExecutionService = ToolExecutionService(calculator: calculator,
                                                         screenshotService: screenshotService,
                                                         ocrService: ocrService,
                                                         notificationService: notificationService,
                                                         localIndexService: localIndexService,
                                                         macActionService: macActionService,
                                                         projectActionService: projectActionService,
                                                         safeShellService: safeShellService,
                                                         speechInputService: speechInputService,
                                                         speechOutputService: speechOutputService)
    lazy var conversationService = ConversationService(database: database, ollama: ollamaClient)
    lazy var macroService = MacroService(database: database)
    lazy var workflowEngine = WorkflowEngine(notificationService: notificationService,
                                            localIndexService: localIndexService,
                                            documentService: documentService,
                                            screenshotService: screenshotService,
                                            ocrService: ocrService,
                                            ollama: ollamaClient)
    lazy var diagnosticsService = DiagnosticsService(ollama: ollamaClient, database: database)
    lazy var approvalService = JarvisExecutionApprovalService(database: database, diagnostics: diagnosticsService, settingsStore: settingsStore)
    lazy var hostActionBroker = JarvisHostActionBroker(
        fileService: hostFileService,
        terminalService: terminalExecutionService,
        screenshotService: screenshotService,
        ocrService: ocrService,
        macActionService: macActionService,
        projectActionService: projectActionService,
        approvalService: approvalService,
        diagnostics: diagnosticsService,
        database: database
    )
    lazy var assistantStateStore = JarvisAssistantStateStore(
        conversation: conversationService.loadRecentConversations().first ?? Conversation(title: "New Chat", model: settingsStore.selectedModel()),
        history: conversationService.loadRecentConversations()
    )
    lazy var assistantRuntime = JarvisAssistantRuntime(
        settingsStore: settingsStore,
        conversationService: conversationService,
        speechInputService: speechInputService,
        wakeSpeechInputService: wakeSpeechInputService,
        speechOutputService: speechOutputService,
        diagnosticsService: diagnosticsService,
        hostActionBroker: hostActionBroker,
        approvalService: approvalService,
        stateStore: assistantStateStore
    )

    lazy var notificationViewModel = NotificationViewModel(service: notificationService, settingsStore: settingsStore, ollama: ollamaClient)
    lazy var settingsViewModel = SettingsViewModel(settingsStore: settingsStore,
                                                   permissions: permissionsManager,
                                                   localIndexService: localIndexService,
                                                   macroService: macroService,
                                                   conversationService: conversationService,
                                                   ollama: ollamaClient)
    lazy var emailDraftViewModel = EmailDraftViewModel(screenshotService: screenshotService,
                                                       ocrService: ocrService,
                                                       ollama: ollamaClient,
                                                       settingsStore: settingsStore)
    lazy var diagnosticsViewModel = DiagnosticsViewModel(diagnosticsService: diagnosticsService,
                                                         ollama: ollamaClient,
                                                         settingsStore: settingsStore)
    lazy var commandPaletteViewModel = CommandPaletteViewModel(settingsStore: settingsStore,
                                                               conversationService: conversationService,
                                                               documentService: documentService,
                                                               tableExtractor: tableExtractor,
                                                               localIndexService: localIndexService,
                                                               macroService: macroService,
                                                               workflowEngine: workflowEngine,
                                                               toolService: toolExecutionService,
                                                               speechInputService: speechInputService,
                                                               speechOutputService: speechOutputService,
                                                               assistantRuntime: assistantRuntime,
                                                               notificationViewModel: notificationViewModel,
                                                               clipboardWatcher: clipboardWatcher,
                                                               diagnosticsService: diagnosticsService,
                                                               ollama: ollamaClient)

    func startServices() {
        ollamaClient.onNetworkRequest = { [weak self] url in
            guard let self else { return }
            let settings = self.settingsStore.current
            guard settings.privacyGuardianEnabled, settings.privacyNetworkMonitorEnabled else { return }
            let host = url.host?.lowercased() ?? "unknown"
            let isLocal = host == "127.0.0.1" || host == "localhost" || host == "::1"
            let type = isLocal ? "network.local" : "network.external"
            let summary = isLocal ? "Jarvis network call -> \(host)" : "Unexpected outbound call -> \(host)"
            self.diagnosticsService.logEvent(feature: "Privacy guardian", type: type, summary: summary, metadata: ["url": url.absoluteString])
        }
        let settings = settingsStore.current
        if settings.clipboardWatcherEnabled || (settings.privacyGuardianEnabled && settings.privacyClipboardMonitorEnabled) {
            clipboardWatcher.start()
        }
        assistantRuntime.start()
    }
}

@MainActor
final class JarvisAssistantStateStore: ObservableObject {
    @Published var runtimeState: JarvisAssistantRuntimeState = .idle
    @Published var conversation: Conversation
    @Published var history: [Conversation]
    @Published var isStreaming: Bool = false
    @Published var streamingText: String = ""
    @Published var statusMessage: String? = nil
    @Published var pendingApproval: PendingApprovalRequest? = nil
    @Published var latestActionRecords: [JarvisActionExecutionRecord] = []

    init(conversation: Conversation, history: [Conversation]) {
        self.conversation = conversation
        self.history = history
    }
}

@MainActor
final class JarvisVoiceSessionCoordinator {
    private let speechInputService: JarvisSpeechInputService
    private let diagnosticsService: DiagnosticsService

    init(speechInputService: JarvisSpeechInputService, diagnosticsService: DiagnosticsService) {
        self.speechInputService = speechInputService
        self.diagnosticsService = diagnosticsService
    }

    func startListening() async throws {
        diagnosticsService.logEvent(feature: "Voice runtime", type: "voice.listen_start", summary: "Starting active voice capture")
        try await speechInputService.startListening()
    }

    func stopAndCommit() async -> JarvisSpeechTranscriptResult? {
        let result = await speechInputService.stopListening()
        diagnosticsService.logEvent(feature: "Voice runtime", type: "voice.listen_stop", summary: result == nil ? "Stopped active voice capture" : "Committed voice transcript", metadata: ["hasTranscript": String(result != nil)])
        return result
    }

    func cancel() async {
        await speechInputService.cancelListening()
        diagnosticsService.logEvent(feature: "Voice runtime", type: "voice.cancelled", summary: "Cancelled active voice capture")
    }
}

@MainActor
final class JarvisWakeWordService {
    private let speechInputService: JarvisSpeechInputService
    private let settingsStore: SettingsStore
    private let diagnosticsService: DiagnosticsService
    private var cancellables: Set<AnyCancellable> = []
    private var isRunning = false
    var onWakeDetected: (() -> Void)?

    init(speechInputService: JarvisSpeechInputService, settingsStore: SettingsStore, diagnosticsService: DiagnosticsService) {
        self.speechInputService = speechInputService
        self.settingsStore = settingsStore
        self.diagnosticsService = diagnosticsService

        speechInputService.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self else { return }
                let normalized = transcript.lowercased()
                guard self.isRunning, normalized.contains("hey jarvis") else { return }
                self.diagnosticsService.logEvent(feature: "Wake word", type: "wake.detected", summary: "Detected Hey Jarvis wake phrase")
                Task { @MainActor in
                    await self.stop()
                    self.onWakeDetected?()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard settingsStore.current.wakeWordEnabled, !isRunning else { return }
        guard let accessKey = settingsStore.porcupineAccessKey(), !accessKey.isEmpty else {
            diagnosticsService.logEvent(feature: "Wake word", type: "wake.error", summary: "Wake word disabled because Porcupine access key is missing")
            return
        }
        guard resolveKeywordPath() != nil else {
            diagnosticsService.logEvent(feature: "Wake word", type: "wake.error", summary: "Wake word disabled because no keyword asset was found")
            return
        }
        isRunning = true
        diagnosticsService.logEvent(feature: "Wake word", type: "wake.start", summary: "Started wake listening")
        Task {
            do {
                _ = await speechInputService.requestPermissions()
                try await speechInputService.startListening()
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.diagnosticsService.logEvent(feature: "Wake word", type: "wake.error", summary: "Failed to start wake listening", metadata: ["error": error.localizedDescription])
                }
            }
        }
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        await speechInputService.cancelListening()
        diagnosticsService.logEvent(feature: "Wake word", type: "wake.stop", summary: "Stopped wake listening")
    }

    func restartIfNeeded() {
        guard settingsStore.current.wakeWordEnabled else { return }
        start()
    }

    private func resolveKeywordPath() -> String? {
        if let stored = settingsStore.porcupineKeywordPath(),
           FileManager.default.fileExists(atPath: stored) {
            return stored
        }
        if let bundled = Bundle.main.path(forResource: "hey_jarvis", ofType: "ppn"),
           FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        return nil
    }
}

@MainActor
final class JarvisAgentLoop {
    private let settingsStore: SettingsStore
    private let conversationService: ConversationService
    private let diagnosticsService: DiagnosticsService
    private let hostActionBroker: JarvisHostActionBroker
    private let streamingSpeechService: JarvisStreamingSpeechService
    private let intentClassifier = IntentClassifier()
    private let routePlanner = RoutePlanner()

    init(
        settingsStore: SettingsStore,
        conversationService: ConversationService,
        diagnosticsService: DiagnosticsService,
        hostActionBroker: JarvisHostActionBroker,
        streamingSpeechService: JarvisStreamingSpeechService
    ) {
        self.settingsStore = settingsStore
        self.conversationService = conversationService
        self.diagnosticsService = diagnosticsService
        self.hostActionBroker = hostActionBroker
        self.streamingSpeechService = streamingSpeechService
    }

    func handlePrompt(
        _ prompt: String,
        conversation: Conversation,
        context: ConversationContext
    ) async -> (conversation: Conversation, history: [Conversation], pendingApproval: PendingApprovalRequest?, records: [JarvisActionExecutionRecord], stream: AsyncThrowingStream<String, Error>?) {
        if let plan = hostActionBroker.plan(for: prompt) {
            let outcome = await hostActionBroker.execute(plan: plan, settings: settingsStore.current)
            var updated = conversation
            updated.messages.append(ChatMessage(role: .assistant, text: outcome.assistantMessage))
            updated.updatedAt = Date()
            conversationService.persist(updated)
            return (updated, conversationService.loadRecentConversations(), outcome.pendingApproval, outcome.records, nil)
        }

        let signal = RouteSignal(
            selectedSurface: .chat,
            quickActionKind: nil,
            hasImportedDocument: context.selectedDocument != nil,
            hasClipboardText: !(context.clipboardPreview?.isEmpty ?? true),
            hasIndexedFolders: !settingsStore.current.indexedFolders.isEmpty
        )
        let classification = intentClassifier.classify(prompt: prompt, signal: signal)
        let routePlan = routePlanner.makePlan(classification: classification, signal: signal)
        diagnosticsService.logEvent(feature: "Runtime", type: "route.selected", summary: "Selected route in agent loop", metadata: ["intent": routePlan.intent.rawValue])
        let stream = conversationService.streamResponse(conversation: conversation, context: context, routePlan: routePlan, settings: settingsStore.current)
        return (conversation, conversationService.loadRecentConversations(), nil, [], stream)
    }

    func pushStreamingSpeech(_ chunk: String) {
        guard settingsStore.current.voiceAutoResponseEnabled else { return }
        let mode: JarvisStreamingSpeechService.Mode = settingsStore.current.streamingSpeechEnabled ? .streamingSpeech : .silentStreaming
        Task {
            await streamingSpeechService.setMode(mode)
            await streamingSpeechService.push(chunk: chunk)
        }
    }

    func finishStreamingSpeech() {
        guard settingsStore.current.voiceAutoResponseEnabled else { return }
        Task { await streamingSpeechService.finish() }
    }

    func cancelStreamingSpeech() {
        Task { await streamingSpeechService.cancel() }
    }
}

@MainActor
final class JarvisAssistantRuntime {
    private let settingsStore: SettingsStore
    private let conversationService: ConversationService
    private let diagnosticsService: DiagnosticsService
    let stateStore: JarvisAssistantStateStore
    private let voiceCoordinator: JarvisVoiceSessionCoordinator
    private let wakeWordService: JarvisWakeWordService
    private let agentLoop: JarvisAgentLoop
    private let hostActionBroker: JarvisHostActionBroker
    private let approvalService: JarvisExecutionApprovalService
    private var activeTask: Task<Void, Never>?
    private var pendingApprovalContext: JarvisActionPlan?
    var onWakePresentationRequested: (() -> Void)?

    init(
        settingsStore: SettingsStore,
        conversationService: ConversationService,
        speechInputService: JarvisSpeechInputService,
        wakeSpeechInputService: JarvisSpeechInputService,
        speechOutputService: JarvisSpeechOutputService,
        diagnosticsService: DiagnosticsService,
        hostActionBroker: JarvisHostActionBroker,
        approvalService: JarvisExecutionApprovalService,
        stateStore: JarvisAssistantStateStore
    ) {
        self.settingsStore = settingsStore
        self.conversationService = conversationService
        self.diagnosticsService = diagnosticsService
        self.stateStore = stateStore
        self.voiceCoordinator = JarvisVoiceSessionCoordinator(speechInputService: speechInputService, diagnosticsService: diagnosticsService)
        self.wakeWordService = JarvisWakeWordService(speechInputService: wakeSpeechInputService, settingsStore: settingsStore, diagnosticsService: diagnosticsService)
        self.hostActionBroker = hostActionBroker
        self.approvalService = approvalService
        self.agentLoop = JarvisAgentLoop(
            settingsStore: settingsStore,
            conversationService: conversationService,
            diagnosticsService: diagnosticsService,
            hostActionBroker: hostActionBroker,
            streamingSpeechService: JarvisStreamingSpeechService(speechOutputService: speechOutputService, diagnostics: diagnosticsService)
        )
        self.wakeWordService.onWakeDetected = { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.onWakePresentationRequested?()
            self.stateStore.runtimeState = .heardWakeWord
            Task { try? await self.voiceCoordinator.startListening() }
        }
    }

    func start() {
        stateStore.history = conversationService.loadRecentConversations()
        stateStore.conversation = stateStore.history.first ?? Conversation(title: "New Chat", model: settingsStore.selectedModel())
        setState(settingsStore.current.wakeWordEnabled ? .wakeListening : .idle, detail: "runtime_started")
        wakeWordService.restartIfNeeded()
        settingsStore.importPorcupineAccessKeyFromEnvironmentIfNeeded()
    }

    func submitText(_ prompt: String, context: ConversationContext) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancelActive(reason: "new_request")

        var conversation = stateStore.conversation
        conversation.messages.append(ChatMessage(role: .user, text: trimmed))
        conversation.updatedAt = Date()
        stateStore.conversation = conversation
        conversationService.persist(conversation)
        stateStore.history = conversationService.loadRecentConversations()
        stateStore.streamingText = ""
        stateStore.isStreaming = false
        setState(.planning, detail: trimmed)

        activeTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.agentLoop.handlePrompt(trimmed, conversation: conversation, context: context)
            await MainActor.run {
                self.stateStore.pendingApproval = result.pendingApproval
                self.stateStore.latestActionRecords = result.records
                if let pending = result.pendingApproval {
                    self.pendingApprovalContext = JarvisActionPlan(id: pending.planID, requestText: trimmed, summary: pending.message, steps: [pending.step])
                    self.stateStore.statusMessage = pending.message
                    self.setState(.awaitingApproval, detail: pending.message)
                    return
                }
            }

            if let stream = result.stream {
                await self.consumeStream(stream)
            } else {
                await MainActor.run {
                    self.stateStore.conversation = result.conversation
                    self.stateStore.history = result.history
                    self.stateStore.statusMessage = result.conversation.messages.last?.text
                    self.setState(.idle, detail: "action_completed")
                }
                self.agentLoop.finishStreamingSpeech()
                self.wakeWordService.restartIfNeeded()
            }
        }
    }

    func startVoiceCapture() {
        Task {
            do {
                setState(.activelyListening, detail: "manual_voice_start")
                try await voiceCoordinator.startListening()
            } catch {
                setState(.failed, detail: error.localizedDescription)
                stateStore.statusMessage = error.localizedDescription
            }
        }
    }

    func stopVoiceCaptureAndSubmit(context: ConversationContext) {
        Task {
            let transcript = await voiceCoordinator.stopAndCommit()
            if let transcript, !transcript.transcript.isEmpty {
                setState(.transcribing, detail: transcript.transcript)
                submitText(transcript.transcript, context: context)
            } else {
                setState(.idle, detail: "voice_stopped")
                wakeWordService.restartIfNeeded()
            }
        }
    }

    func approvePending(scope: JarvisApprovalScope = .once, context: ConversationContext) {
        guard let pending = stateStore.pendingApproval, let plan = pendingApprovalContext else { return }
        stateStore.pendingApproval = nil
        pendingApprovalContext = nil
        stateStore.statusMessage = "Approval granted."
        approvalService.allow(pending, scope: scope)
        // Reuse the broker path by resubmitting the original request with the approved plan.
        submitApproved(plan: plan, pending: pending, scope: scope)
    }

    private func submitApproved(plan: JarvisActionPlan, pending: PendingApprovalRequest, scope: JarvisApprovalScope) {
        cancelActive(reason: "approved_action")
        stateStore.pendingApproval = nil
        stateStore.latestActionRecords = []
        diagnosticsService.logEvent(feature: "Approval runtime", type: "approval.resume", summary: "Resuming approved action", metadata: ["scope": scope.rawValue])
        // Current runtime supports allow-once semantics in the active session.
        activeTask = Task { [weak self] in
            guard let self else { return }
            self.setState(.executingActions, detail: pending.step.title)
            let outcome = await self.hostActionBroker.execute(plan: plan, settings: self.settingsStore.current, approvalRequest: pending, elevatedConfirmation: pending.step.kind == .shellCommand)
            await MainActor.run {
                self.stateStore.latestActionRecords = outcome.records
                var convo = self.stateStore.conversation
                convo.messages.append(ChatMessage(role: .assistant, text: outcome.assistantMessage))
                convo.updatedAt = Date()
                self.conversationService.persist(convo)
                self.stateStore.conversation = convo
                self.stateStore.history = self.conversationService.loadRecentConversations()
                self.stateStore.statusMessage = outcome.assistantMessage
                self.setState(.idle, detail: "approved_action_completed")
            }
            self.wakeWordService.restartIfNeeded()
        }
    }

    func rejectPending() {
        guard let pending = stateStore.pendingApproval else { return }
        diagnosticsService.logEvent(feature: "Approval runtime", type: "approval.rejected", summary: "Rejected pending host action", metadata: ["actionKind": pending.step.kind.rawValue])
        stateStore.pendingApproval = nil
        pendingApprovalContext = nil
        stateStore.statusMessage = "Action denied."
        setState(.idle, detail: "approval_rejected")
        wakeWordService.restartIfNeeded()
    }

    func cancelActive(reason: String) {
        activeTask?.cancel()
        activeTask = nil
        agentLoop.cancelStreamingSpeech()
        stateStore.isStreaming = false
        stateStore.streamingText = ""
        setState(.interrupted, detail: reason)
    }

    private func consumeStream(_ stream: AsyncThrowingStream<String, Error>) async {
        await MainActor.run {
            self.stateStore.isStreaming = true
            self.setState(.streamingResponse, detail: "model_stream")
        }
        var collected = ""
        do {
            for try await chunk in stream {
                if Task.isCancelled { break }
                collected.append(chunk)
                await MainActor.run {
                    self.stateStore.streamingText = collected
                }
                self.agentLoop.pushStreamingSpeech(chunk)
            }
            self.agentLoop.finishStreamingSpeech()
            await MainActor.run {
                var convo = self.stateStore.conversation
                convo.messages.append(ChatMessage(role: .assistant, text: collected.trimmingCharacters(in: .whitespacesAndNewlines)))
                convo.updatedAt = Date()
                self.conversationService.persist(convo)
                self.stateStore.conversation = convo
                self.stateStore.history = self.conversationService.loadRecentConversations()
                self.stateStore.isStreaming = false
                self.stateStore.statusMessage = "Response complete."
                self.setState(.idle, detail: "stream_completed")
            }
        } catch {
            self.agentLoop.cancelStreamingSpeech()
            await MainActor.run {
                self.stateStore.isStreaming = false
                self.stateStore.statusMessage = error.localizedDescription
                self.setState(.failed, detail: error.localizedDescription)
            }
        }
        wakeWordService.restartIfNeeded()
    }

    private func setState(_ state: JarvisAssistantRuntimeState, detail: String) {
        stateStore.runtimeState = state
        if settingsStore.current.runtimeDiagnosticsEnabled {
            diagnosticsService.logEvent(feature: "Runtime", type: "runtime.state", summary: state.rawValue, metadata: ["detail": detail])
        }
    }
}
