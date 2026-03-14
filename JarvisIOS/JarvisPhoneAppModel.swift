import Foundation
import SwiftUI
import UIKit
import Combine

enum JarvisAppTab: String, CaseIterable, Hashable, Identifiable {
    case home
    case assistant
    case visual
    case knowledge
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .assistant:
            return "Ask"
        case .visual:
            return "Visual"
        case .knowledge:
            return "Knowledge"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "house.fill"
        case .assistant:
            return "bubble.left.fill"
        case .visual:
            return "viewfinder.circle.fill"
        case .knowledge:
            return "books.vertical.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

@MainActor
final class JarvisPhoneAppModel: ObservableObject {
    struct QuickLaunchItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let route: JarvisLaunchRoute
    }

    enum ModelImportState: Equatable {
        case idle
        case importing(progress: Double, message: String)
        case success(message: String)
        case failure(message: String)
    }

    private enum ModelImportRequest: Equatable {
        case primaryModel
        case projector(modelID: UUID)
    }

    enum AssistantInputMode: Equatable {
        case text
        case voice
        case visual
    }

    enum AssistantExperienceState: Equatable {
        case idle
        case armed
        case listening
        case transcribing
        case thinking
        case grounding
        case responding
        case groundedAnswerReady
        case error(message: String)
        case unavailable(reason: String)

        var title: String {
            switch self {
            case .idle:
                return "Idle"
            case .armed:
                return "Ready to Listen"
            case .listening:
                return "Listening"
            case .transcribing:
                return "Transcribing"
            case .thinking:
                return "Thinking"
            case .grounding:
                return "Grounding"
            case .responding:
                return "Responding"
            case .groundedAnswerReady:
                return "Answer Ready"
            case .error:
                return "Attention Needed"
            case .unavailable:
                return "Unavailable"
            }
        }
    }

    enum AssistantSuggestionAction: Equatable {
        case prompt(String)
        case route(JarvisLaunchRoute)
        case saveToKnowledge
    }

    struct AssistantSuggestion: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let icon: String
        let action: AssistantSuggestionAction
    }

    @Published var conversation: JarvisConversationRecord
    @Published var conversations: [JarvisConversationRecord]
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var statusText: String = "Ready"
    @Published var runtimeState: JarvisModelRuntimeState
    @Published var modelFileAccessState: JarvisModelFileAccessState
    @Published var knowledgeQuery: String = ""
    @Published var knowledgeResults: [JarvisKnowledgeResult] = []
    @Published var knowledgeItems: [JarvisKnowledgeItem] = []

    @Published var models: [JarvisImportedModel] = []
    @Published var activeModelID: UUID?
    @Published var modelImportState: ModelImportState = .idle
    @Published var settings: JarvisAssistantSettings {
        didSet {
            guard settingsPersistenceEnabled else { return }
            handleSettingsChange(from: oldValue, to: settings)
        }
    }

    @Published var selectedTab: JarvisAppTab = .home
    @Published private(set) var assistantReturnTab: JarvisAppTab?

    @Published var isAssistantPresented = false
    @Published var isKnowledgePresented = false
    @Published var isSettingsPresented = false
    @Published var isModelLibraryPresented = false
    @Published var isModelImporterPresented = false
    @Published var isVisualIntelligencePresented = false
    @Published var showSetupFlow = false
    @Published var shouldFocusComposer = false
    @Published var assistantInputMode: AssistantInputMode = .text
    @Published var assistantExperienceState: AssistantExperienceState = .idle
    @Published var assistantLiveTranscript: String = ""
    @Published var assistantSuggestions: [AssistantSuggestion] = []
    @Published private(set) var speechState: JarvisSpeechState = .idle
    @Published private(set) var speechPermissions = JarvisSpeechPermissions(
        microphoneGranted: false,
        speechRecognitionGranted: false
    )

    let quickLaunchItems: [QuickLaunchItem]

    var activeModel: JarvisImportedModel? {
        guard let activeModelID else { return nil }
        return models.first(where: { $0.id == activeModelID })
    }

    var hasReadyModel: Bool {
        models.contains(where: { $0.status == .ready })
    }

    var needsModelSetup: Bool {
        guard let activeModel else { return true }
        return activeModel.status != .ready
    }

    var supportedModelFormatText: String {
        modelLibrary.supportedFormatText()
    }

    var runtimeEngineName: String {
        runtime.engineName
    }

    var canRunInference: Bool {
        runtime.isInferenceAvailable
    }

    var runtimeBlockedReason: String {
        runtime.inferenceUnavailableReason
    }

    var supportedModelProfile: JarvisSupportedModelProfile {
        JarvisSupportedModelCatalog.profile(for: settings.preferredModelProfile) ?? JarvisSupportedModelCatalog.goldPath
    }

    var supportedModelDisplayName: String {
        supportedModelProfile.displayName
    }

    var supportedModelShortDescription: String {
        supportedModelProfile.shortDescription
    }

    var supportedModelImportGuidance: String {
        supportedModelProfile.importGuidance
    }

    var activeModelSupportStatusText: String {
        guard let activeModel else {
            return "No active local model selected"
        }
        if let profile = JarvisSupportedModelCatalog.profile(for: activeModel.supportedProfileID) {
            return "Curated profile: \(profile.displayName)"
        }
        return activeModel.statusMessage ?? "Bookmark-backed local model ready for activation."
    }

    var activeModelVisualStatusText: String {
        guard let activeModel else {
            return "No active model"
        }
        return activeModel.visualReadinessDescription
    }

    var modelFileAccessDetail: String {
        modelFileAccessState.detail
    }

    var shouldShowAssistantBackButton: Bool {
        selectedTab == .assistant && assistantReturnTab != nil
    }

    private let store: JarvisConversationStore
    private let modelLibrary: JarvisModelLibrary
    private let launchStore: JarvisLaunchRouteStore
    private let settingsStore: JarvisAssistantSettingsStore
    private let runtime: JarvisLocalModelRuntime
    private let speechCoordinator: JarvisSpeechCoordinator
    private var streamTask: Task<Void, Never>?
    private var groundingTransitionTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var settingsPersistenceEnabled = false
    private var pendingModelLibraryImport = false
    private var pendingImportRequest: ModelImportRequest = .primaryModel

    init(
        store: JarvisConversationStore = JarvisConversationStore(),
        modelLibrary: JarvisModelLibrary = JarvisModelLibrary(),
        launchStore: JarvisLaunchRouteStore = .shared,
        settingsStore: JarvisAssistantSettingsStore = JarvisAssistantSettingsStore()
    ) {
        let loadedSettings = settingsStore.load()
        self.store = store
        self.modelLibrary = modelLibrary
        self.launchStore = launchStore
        self.settingsStore = settingsStore
        self.settings = loadedSettings

        self.runtime = JarvisLocalModelRuntime(configuration: loadedSettings.runtimeConfiguration)
        self.speechCoordinator = JarvisSpeechCoordinator()
        self.runtimeState = runtime.state
        self.modelFileAccessState = runtime.fileAccessState

        let loadedConversations = store.loadConversations()
        self.conversations = loadedConversations
        self.conversation = loadedConversations.first ?? JarvisConversationRecord(title: "Jarvis")
        self.knowledgeItems = store.loadKnowledgeItems()

        self.quickLaunchItems = [
            QuickLaunchItem(
                title: "Ask Jarvis",
                subtitle: "Open directly into chat",
                icon: "sparkles",
                route: JarvisLaunchRoute(action: .ask, source: "home")
            ),
            QuickLaunchItem(
                title: "Voice Mode",
                subtitle: "Launch listening-first assistant",
                icon: "waveform.circle.fill",
                route: JarvisLaunchRoute(action: .voice, source: "home")
            ),
            QuickLaunchItem(
                title: "Visual Intelligence",
                subtitle: "Open camera-intelligence workspace",
                icon: "viewfinder.circle.fill",
                route: JarvisLaunchRoute(action: .visualIntelligence, source: "home")
            ),
            QuickLaunchItem(
                title: "Quick Capture",
                subtitle: "Drop text and continue later",
                icon: "square.and.pencil",
                route: JarvisLaunchRoute(action: .quickCapture, source: "home")
            ),
            QuickLaunchItem(
                title: "Summarize Text",
                subtitle: "Turn long text into key points",
                icon: "text.quote",
                route: JarvisLaunchRoute(action: .summarize, source: "home")
            ),
            QuickLaunchItem(
                title: "Search Local Knowledge",
                subtitle: "Find previous notes and answers",
                icon: "magnifyingglass",
                route: JarvisLaunchRoute(action: .search, source: "home")
            ),
            QuickLaunchItem(
                title: "Continue Last Conversation",
                subtitle: "Resume where you left off",
                icon: "arrow.uturn.forward.circle",
                route: JarvisLaunchRoute(action: .continueConversation, source: "home")
            )
        ]

        JarvisHaptics.configure(isEnabled: loadedSettings.hapticsEnabled)

        runtime.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.runtimeState = state
                self?.syncAssistantExperience(with: state)
            }
            .store(in: &cancellables)

        runtime.$fileAccessState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.modelFileAccessState = state
                self?.syncAssistantExperience(withFileAccess: state)
            }
            .store(in: &cancellables)

        speechCoordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.speechState = state
                self.syncAssistantExperienceWithSpeech(state)
            }
            .store(in: &cancellables)

        speechCoordinator.$permissions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] permissions in
                self?.speechPermissions = permissions
            }
            .store(in: &cancellables)

        speechCoordinator.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self else { return }
                if self.assistantInputMode == .voice {
                    self.assistantLiveTranscript = transcript
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.runtime.unload()
                    await MainActor.run {
                        self.runtimeState = self.runtime.state
                        self.statusText = "Released model after memory warning"
                    }
                }
            }
            .store(in: &cancellables)

        settingsPersistenceEnabled = true
    }

    func bootstrap() {
        reloadModelLibrary()
        runtimeState = runtime.state
        showSetupFlow = needsModelSetup
        assistantExperienceState = needsModelSetup ? .unavailable(reason: missingSupportedModelReason()) : .idle

        let handledPendingRoute = consumePendingRouteIfNeeded()
        if !handledPendingRoute {
            applyStartupRouteIfNeeded()
        }

        if settings.autoWarmOnLaunch {
            warmModelIfPossible(source: "launch")
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            runtime.resumeFromForeground()
            runtimeState = runtime.state
            _ = consumePendingRouteIfNeeded()
        case .background:
            persistCurrentConversation()
            if settings.unloadModelOnBackground || settings.batterySaverMode {
                Task {
                    await runtime.unload()
                    await MainActor.run {
                        runtimeState = runtime.state
                    }
                }
            } else {
                runtime.pauseForBackground()
                runtimeState = runtime.state
            }
        case .inactive:
            persistCurrentConversation()
        @unknown default:
            break
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard let route = JarvisLaunchRoute.parse(url: url) else { return }
        apply(route: route)
    }

    func handleTabSelection(_ tab: JarvisAppTab) {
        selectedTab = tab
        if tab != .assistant {
            assistantReturnTab = nil
            if assistantInputMode == .voice {
                stopVoicePreview(commit: false)
            }
            if assistantInputMode != .visual {
                assistantInputMode = .text
            }
            if !needsModelSetup {
                assistantExperienceState = .idle
            }
        } else if assistantInputMode == .text && !needsModelSetup {
            assistantExperienceState = .armed
        }
    }

    func returnFromAssistant() {
        let destination = assistantReturnTab ?? .home
        assistantReturnTab = nil
        if assistantInputMode == .voice {
            stopVoicePreview(commit: false)
        }
        assistantInputMode = .text
        selectedTab = destination
        assistantExperienceState = needsModelSetup ? .unavailable(reason: missingSupportedModelReason()) : .idle
        statusText = "Ready"
    }

    func apply(route: JarvisLaunchRoute) {
        if routeRequiresModel(route.action), needsModelSetup {
            selectedTab = .home
            showSetupFlow = true
            statusText = missingSupportedModelStatusText()
            assistantExperienceState = .unavailable(reason: missingSupportedModelReason())
            JarvisHaptics.error()
            return
        }

        assistantSuggestions = []
        isAssistantPresented = false
        isKnowledgePresented = false
        isSettingsPresented = false
        isVisualIntelligencePresented = false

        switch route.action {
        case .home:
            selectedTab = .home
            assistantReturnTab = nil
            assistantInputMode = .text
            assistantExperienceState = needsModelSetup ? .unavailable(reason: missingSupportedModelReason()) : .idle
            statusText = "Ready"
        case .ask:
            prepareConversationForFocusedEntry()
            if let payload = route.payload, !payload.isEmpty {
                draft = payload
            }
            enterAssistant(mode: .text, status: "Ask Jarvis", focusComposer: true)
        case .quickCapture:
            prepareConversationForFocusedEntry()
            let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            draft = (clipboard?.isEmpty == false) ? (clipboard ?? "") : ""
            enterAssistant(mode: .text, status: "Quick capture", focusComposer: true)
        case .summarize:
            prepareConversationForFocusedEntry()
            let seed = route.payload ?? UIPasteboard.general.string ?? ""
            if seed.isEmpty {
                draft = ""
            } else {
                draft = "Summarize this into concise bullets:\n\(seed)"
            }
            enterAssistant(mode: .text, status: "Summarize text", focusComposer: true)
        case .search:
            selectedTab = .knowledge
            assistantReturnTab = nil
            knowledgeQuery = route.payload ?? ""
            refreshKnowledgeResults()
            assistantInputMode = .text
            assistantExperienceState = .idle
            statusText = "Search local knowledge"
        case .continueConversation:
            if let latest = conversations.first {
                conversation = latest
            }
            enterAssistant(mode: .text, status: "Continue conversation", focusComposer: true)
        case .voice:
            enterAssistant(mode: .voice, status: "Voice mode", focusComposer: false)
            startVoicePreview()
        case .visualIntelligence:
            selectedTab = .visual
            assistantReturnTab = nil
            assistantInputMode = .visual
            assistantExperienceState = .idle
            statusText = "Visual intelligence"
        case .settings:
            selectedTab = .settings
            assistantReturnTab = nil
            assistantInputMode = .text
            assistantExperienceState = .idle
            statusText = "Settings"
        case .modelLibrary:
            selectedTab = .settings
            presentModelLibrary()
            statusText = "Model library"
        }

        JarvisHaptics.selection()
    }

    func beginModelImport() {
        pendingImportRequest = .primaryModel
        modelImportState = .idle
        isModelImporterPresented = true
    }

    func beginProjectorImport(for modelID: UUID) {
        pendingImportRequest = .projector(modelID: modelID)
        modelImportState = .idle
        isModelImporterPresented = true
    }

    func presentModelLibrary(beginImport: Bool = false) {
        pendingModelLibraryImport = beginImport
        isModelLibraryPresented = true
    }

    func consumePendingModelLibraryImport() -> Bool {
        guard pendingModelLibraryImport else { return false }
        pendingModelLibraryImport = false
        return true
    }

    func clearModelImportFeedback() {
        modelImportState = .idle
    }

    func handleModelImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            modelImportState = .failure(message: error.localizedDescription)
            statusText = "Model import failed"
            JarvisHaptics.error()
        case .success(let urls):
            guard let source = urls.first else {
                modelImportState = .failure(message: "No file selected.")
                return
            }
            switch pendingImportRequest {
            case .primaryModel:
                importModel(from: source)
            case .projector(let modelID):
                attachProjector(from: source, to: modelID)
            }
        }
    }

    func importModel(from sourceURL: URL) {
        Task {
            do {
                modelImportState = .importing(progress: 0.04, message: "Starting import")
                let imported = try modelLibrary.importModel(from: sourceURL) { progress, message in
                    Task { @MainActor in
                        self.modelImportState = .importing(progress: progress, message: message)
                    }
                }

                reloadModelLibrary()
                showSetupFlow = needsModelSetup

                let successText = importOutcomeMessage(for: imported)
                statusText = successText
                modelImportState = .success(message: successText)
                modelFileAccessState = .bookmarkCreated(
                    modelName: imported.displayName,
                    detail: "Security-scoped bookmark stored. Activate the model before warmup."
                )
                if !needsModelSetup {
                    assistantExperienceState = .armed
                }
                JarvisHaptics.success()
            } catch {
                statusText = "Model import failed"
                modelImportState = .failure(message: error.localizedDescription)
                JarvisHaptics.error()
            }
        }
    }

    func attachProjector(from sourceURL: URL, to modelID: UUID) {
        Task {
            do {
                modelImportState = .importing(progress: 0.05, message: "Starting projector import")
                let updatedModel = try modelLibrary.attachProjector(from: sourceURL, to: modelID) { progress, message in
                    Task { @MainActor in
                        self.modelImportState = .importing(progress: progress, message: message)
                    }
                }

                reloadModelLibrary()
                let successText = "Attached projector for \(updatedModel.displayName). Text use is ready now; visual readiness metadata is stored for later."
                statusText = successText
                modelImportState = .success(message: successText)
                JarvisHaptics.success()
            } catch {
                statusText = "Projector import failed"
                modelImportState = .failure(message: error.localizedDescription)
                JarvisHaptics.error()
            }
        }
    }

    func setActiveModel(id: UUID) {
        do {
            try modelLibrary.setActiveModel(id: id)
            reloadModelLibrary()
            guard let activeModel else {
                throw JarvisModelError.unavailable("No active model selected.")
            }

            showSetupFlow = needsModelSetup
            modelImportState = .idle
            if let profile = JarvisSupportedModelCatalog.profile(for: activeModel.supportedProfileID) {
                statusText = "Activated \(activeModel.displayName). \(profile.activationGuidance)"
            } else {
                statusText = "Activated \(activeModel.displayName). Warm it now or let Jarvis auto-warm on first send."
            }
            assistantExperienceState = .armed
            JarvisHaptics.selection()
        } catch {
            statusText = "Could not activate model"
            modelImportState = .failure(message: error.localizedDescription)
        }
    }

    func removeModel(id: UUID) {
        do {
            try modelLibrary.removeModel(id: id)
            reloadModelLibrary()
            showSetupFlow = needsModelSetup
            if needsModelSetup {
                selectedTab = .home
                assistantReturnTab = nil
                if hasReadyModel {
                    assistantExperienceState = .unavailable(reason: "Activate one of your imported models to continue.")
                    statusText = "Activate an imported model to continue"
                } else {
                    assistantExperienceState = .unavailable(reason: missingSupportedModelReason())
                    statusText = missingSupportedModelStatusText()
                }
            } else {
                statusText = "Model removed"
            }
            JarvisHaptics.selection()
        } catch {
            statusText = "Could not remove model"
            modelImportState = .failure(message: error.localizedDescription)
        }
    }

    func revalidateModel(id: UUID) {
        do {
            let model = try modelLibrary.revalidateModel(id: id)
            reloadModelLibrary()
            statusText = "\(model.displayName): \(model.status.displayName)"
            if needsModelSetup {
                showSetupFlow = true
            }
        } catch {
            statusText = "Validation failed"
            modelImportState = .failure(message: error.localizedDescription)
        }
    }

    func sendCurrentDraft() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        send(prompt: prompt)
        draft = ""
    }

    func send(prompt: String) {
        if needsModelSetup {
            selectedTab = .home
            showSetupFlow = true
            statusText = missingSupportedModelStatusText()
            assistantExperienceState = .unavailable(reason: missingSupportedModelReason())
            JarvisHaptics.error()
            return
        }

        if !canRunInference {
            statusText = runtimeBlockedReason
            assistantExperienceState = .unavailable(reason: runtimeBlockedReason)
            JarvisHaptics.error()
            return
        }

        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        if !settings.autoWarmOnFirstSend {
            switch runtimeState {
            case .cold, .failed, .paused:
                let reason = "Warm \(activeModel?.displayName ?? "the active model") before sending. Auto-warm on first send is turned off."
                statusText = reason
                assistantExperienceState = .unavailable(reason: reason)
                JarvisHaptics.error()
                return
            default:
                break
            }
        }

        streamTask?.cancel()
        groundingTransitionTask?.cancel()
        runtimeState = runtime.state

        let historyForRuntime = conversation.messages

        var updated = conversation
        updated.updatedAt = Date()
        updated.messages.append(JarvisChatMessage(role: .user, text: cleanPrompt))
        let streamingID = UUID()
        updated.messages.append(JarvisChatMessage(id: streamingID, role: .assistant, text: "", isStreaming: true))
        conversation = updated
        persistCurrentConversation()

        isSending = true
        statusText = pendingWarmupStatusText()
        assistantExperienceState = .thinking
        assistantSuggestions = []
        JarvisHaptics.softImpact()

        groundingTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard let self else { return }
            guard self.isSending, self.assistantExperienceState == .thinking else { return }
            self.assistantExperienceState = .grounding
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.runtime.streamResponse(prompt: cleanPrompt, history: historyForRuntime)
                var emittedFirstToken = false
                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    if !emittedFirstToken {
                        emittedFirstToken = true
                        await MainActor.run {
                            self.groundingTransitionTask?.cancel()
                            self.groundingTransitionTask = nil
                        }
                        await MainActor.run {
                            self.assistantExperienceState = .responding
                        }
                    }
                    await self.appendStreamingToken(token, id: streamingID)
                }
                await self.finalizeStreamingMessage(id: streamingID)
                await MainActor.run {
                    self.isSending = false
                    self.groundingTransitionTask?.cancel()
                    self.groundingTransitionTask = nil
                    self.statusText = "Ready"
                    self.runtimeState = self.runtime.state
                    self.assistantExperienceState = .groundedAnswerReady
                    self.refreshAssistantSuggestions()
                    self.persistCurrentConversation()
                    JarvisHaptics.success()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    self.isSending = false
                    self.groundingTransitionTask?.cancel()
                    self.groundingTransitionTask = nil
                    self.runtimeState = self.runtime.state
                    self.statusText = message
                    self.replaceStreamingMessage(id: streamingID, with: "I couldn't complete that request: \(message)")
                    self.assistantExperienceState = .error(message: message)
                    self.persistCurrentConversation()
                    JarvisHaptics.error()
                }
            }
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        groundingTransitionTask?.cancel()
        groundingTransitionTask = nil
        runtime.cancel()
        isSending = false
        runtimeState = runtime.state
        statusText = "Cancelled"
        assistantExperienceState = needsModelSetup ? .unavailable(reason: missingSupportedModelReason()) : .armed
        JarvisHaptics.selection()
    }

    func setAssistantInputMode(_ mode: AssistantInputMode) {
        if assistantInputMode == .voice, mode != .voice {
            stopVoicePreview(commit: false)
        }
        assistantInputMode = mode
        switch mode {
        case .text:
            assistantExperienceState = .armed
            shouldFocusComposer = true
        case .voice:
            shouldFocusComposer = false
            startVoicePreview()
        case .visual:
            assistantExperienceState = .idle
            shouldFocusComposer = false
            apply(route: JarvisLaunchRoute(action: .visualIntelligence, source: "assistant.mode"))
        }
    }

    func startVoicePreview() {
        guard !needsModelSetup else {
            assistantExperienceState = .unavailable(reason: missingSupportedModelReason())
            return
        }
        guard canRunInference else {
            assistantExperienceState = .unavailable(reason: runtimeBlockedReason)
            return
        }

        assistantInputMode = .voice
        assistantLiveTranscript = ""
        assistantExperienceState = .thinking
        statusText = "Preparing voice input"
        JarvisHaptics.listeningStart()

        let options = JarvisSpeechSessionOptions(
            autoSendAfterSilence: true,
            silenceTimeout: 0.95
        )

        Task { [weak self] in
            guard let self else { return }
            await self.speechCoordinator.start(options: options) { [weak self] committed in
                Task { @MainActor [weak self] in
                    self?.handleCommittedSpeechTranscript(committed)
                }
            }
        }
    }

    func stopVoicePreview(commit: Bool) {
        if commit {
            statusText = "Finalizing voice input"
            assistantExperienceState = .transcribing
            Task { [weak self] in
                await self?.speechCoordinator.stop(commitIfAvailable: true)
            }
        } else {
            statusText = "Voice cancelled"
            assistantLiveTranscript = ""
            assistantExperienceState = needsModelSetup ? .unavailable(reason: missingSupportedModelReason()) : .armed
            Task { [weak self] in
                await self?.speechCoordinator.cancel()
            }
        }
        JarvisHaptics.listeningStop()
    }

    func performAssistantSuggestion(_ suggestion: AssistantSuggestion) {
        switch suggestion.action {
        case .prompt(let prompt):
            draft = prompt
            shouldFocusComposer = true
            assistantInputMode = .text
            assistantExperienceState = .armed
        case .route(let route):
            apply(route: route)
        case .saveToKnowledge:
            addKnowledgeItemFromConversation()
        }
    }

    func warmModel() {
        warmModelIfPossible(source: "manual")
    }

    func unloadActiveModel() {
        Task {
            await runtime.unload()
            await MainActor.run {
                runtimeState = runtime.state
                statusText = "Model unloaded from memory"
                if !needsModelSetup {
                    assistantExperienceState = .armed
                }
            }
        }
    }

    func retryRuntimeWarmup() {
        warmModelIfPossible(source: "retry")
    }

    func startNewConversation() {
        if !conversation.messages.isEmpty {
            persistCurrentConversation()
        }
        conversation = JarvisConversationRecord(title: "New Conversation")
        assistantSuggestions = []
        assistantLiveTranscript = ""
        statusText = "New conversation"
        assistantExperienceState = .armed
    }

    func openConversation(_ record: JarvisConversationRecord, source: String) {
        conversation = record
        enterAssistant(mode: .text, status: "Continue conversation", focusComposer: true, source: source)
    }

    func addKnowledgeItemFromConversation() {
        guard let lastAssistant = conversation.messages.last(where: { $0.role == .assistant }) else { return }
        let item = JarvisKnowledgeItem(
            title: conversation.title,
            text: lastAssistant.text,
            source: "conversation"
        )
        store.addKnowledgeItem(item)
        knowledgeItems = store.loadKnowledgeItems()
        refreshKnowledgeResults()
        JarvisHaptics.softImpact()
    }

    func refreshKnowledgeResults() {
        let query = knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            knowledgeResults = knowledgeItems.prefix(20).map {
                JarvisKnowledgeResult(item: $0, score: 1, snippet: String($0.text.prefix(180)))
            }
            return
        }
        knowledgeResults = store.searchKnowledge(query: query, limit: 20)
    }

    func clearKnowledge() {
        store.clearKnowledgeItems()
        knowledgeItems = []
        refreshKnowledgeResults()
    }

    func triggerQuickLaunch(_ item: QuickLaunchItem) {
        apply(route: item.route)
    }

    func dismissSetupFlowIfReady() {
        showSetupFlow = needsModelSetup
    }

    private func handleSettingsChange(from oldValue: JarvisAssistantSettings, to newValue: JarvisAssistantSettings) {
        settingsStore.save(newValue)
        JarvisHaptics.configure(isEnabled: newValue.hapticsEnabled)
        runtime.updateConfiguration(newValue.runtimeConfiguration)
        runtimeState = runtime.state

        if oldValue.autoWarmOnLaunch != newValue.autoWarmOnLaunch, newValue.autoWarmOnLaunch {
            warmModelIfPossible(source: "settings")
        }
    }

    private func consumePendingRouteIfNeeded() -> Bool {
        guard let pending = launchStore.consumePendingRoute() else { return false }
        apply(route: pending)
        return true
    }

    private func applyStartupRouteIfNeeded() {
        guard settings.startupRoute != .home else {
            selectedTab = .home
            return
        }

        let route = JarvisLaunchRoute(action: settings.startupRoute.launchAction, source: "settings.startup")
        apply(route: route)
    }

    private func reloadModelLibrary() {
        models = modelLibrary.loadModels()
        activeModelID = modelLibrary.activeModelID()

        if let activeModel, activeModel.status == .ready {
            let selection = modelLibrary.runtimeSelection(for: activeModel)
            runtime.setSelectedModel(selection)
        } else {
            runtime.setSelectedModel(nil)
        }

        runtimeState = runtime.state
        modelFileAccessState = runtime.fileAccessState
    }

    private func warmModelIfPossible(source: String) {
        guard !needsModelSetup else { return }
        guard canRunInference else {
            statusText = runtimeBlockedReason
            assistantExperienceState = .unavailable(reason: runtimeBlockedReason)
            return
        }

        let shouldWarm: Bool
        switch runtimeState {
        case .ready, .busy:
            shouldWarm = false
        default:
            shouldWarm = true
        }

        guard shouldWarm else {
            statusText = "Model already warm"
            return
        }

        let warmTargetName = activeModel?.displayName ?? supportedModelDisplayName
        statusText = source == "launch" ? "Auto-warming \(warmTargetName)" : "Warming \(warmTargetName)"
        assistantExperienceState = .thinking

        Task {
            do {
                try await runtime.prepareIfNeeded()
                await MainActor.run {
                    runtimeState = runtime.state
                    statusText = "Model warmed"
                    if !needsModelSetup {
                        assistantExperienceState = .armed
                    }
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    runtimeState = runtime.state
                    statusText = message
                    assistantExperienceState = .error(message: message)
                }
            }
        }
    }

    private func routeRequiresModel(_ action: JarvisLaunchAction) -> Bool {
        switch action {
        case .ask, .quickCapture, .summarize, .continueConversation, .voice:
            return true
        case .home, .search, .visualIntelligence, .settings, .modelLibrary:
            return false
        }
    }

    private func prepareConversationForFocusedEntry() {
        if selectedTab != .assistant && !conversation.messages.isEmpty {
            persistCurrentConversation()
            conversation = JarvisConversationRecord(title: "New Conversation")
        }
        assistantSuggestions = []
        assistantLiveTranscript = ""
    }

    private func enterAssistant(mode: AssistantInputMode, status: String, focusComposer: Bool, source: String = "route") {
        if selectedTab != .assistant {
            assistantReturnTab = selectedTab
        }
        selectedTab = .assistant
        assistantInputMode = mode
        shouldFocusComposer = focusComposer
        assistantExperienceState = mode == .voice ? .listening : .armed
        statusText = status
        if source == "route" {
            JarvisHaptics.selection()
        }
    }

    private func handleCommittedSpeechTranscript(_ transcript: String) {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        assistantLiveTranscript = clean
        assistantExperienceState = .transcribing
        statusText = "Voice captured"
        if assistantInputMode == .voice {
            send(prompt: clean)
            assistantLiveTranscript = ""
        }
    }

    private func syncAssistantExperience(with state: JarvisModelRuntimeState) {
        guard selectedTab == .assistant || assistantInputMode == .voice else { return }

        switch state {
        case .noModel:
            if needsModelSetup {
                assistantExperienceState = .unavailable(reason: missingSupportedModelReason())
            }
        case .runtimeUnavailable(let reason):
            assistantExperienceState = .unavailable(reason: reason)
        case .warming:
            if isSending {
                assistantExperienceState = .thinking
            }
        case .busy:
            if isSending {
                assistantExperienceState = .responding
            }
        case .failed(_, let message):
            assistantExperienceState = .error(message: message)
        case .cold, .ready, .paused:
            if !isSending, assistantInputMode == .text, !needsModelSetup {
                assistantExperienceState = .armed
            }
        }
    }

    private func syncAssistantExperience(withFileAccess state: JarvisModelFileAccessState) {
        guard selectedTab == .assistant || assistantInputMode == .voice else { return }
        guard !isSending else { return }

        switch state {
        case .noImportedFile:
            if needsModelSetup {
                assistantExperienceState = .unavailable(reason: missingSupportedModelReason())
            }
        case .bookmarkCreated(_, let detail), .accessPending(_, let detail):
            statusText = detail
            if assistantInputMode == .text, !needsModelSetup {
                assistantExperienceState = .armed
            }
        case .accessGranted:
            if assistantInputMode == .text, !needsModelSetup {
                assistantExperienceState = .armed
            }
        case .accessLost(_, let reason), .bookmarkResolutionFailed(_, let reason):
            statusText = reason
            assistantExperienceState = .error(message: reason)
        }
    }

    private func syncAssistantExperienceWithSpeech(_ state: JarvisSpeechState) {
        guard assistantInputMode == .voice || selectedTab == .assistant else { return }
        guard !isSending else { return }

        switch state {
        case .idle:
            if assistantInputMode == .voice, !needsModelSetup {
                assistantExperienceState = .armed
            }
        case .requestingPermission:
            assistantExperienceState = .thinking
            statusText = "Requesting microphone access"
        case .ready:
            if assistantInputMode == .voice {
                assistantExperienceState = .armed
                statusText = "Voice ready"
            }
        case .listening:
            assistantExperienceState = .listening
            statusText = "Listening"
        case .transcribing:
            assistantExperienceState = .transcribing
            statusText = "Transcribing"
        case .stopping:
            assistantExperienceState = .transcribing
            statusText = "Finalizing"
        case .failed(let failure):
            assistantExperienceState = .error(message: failure.message)
            statusText = failure.message
        }
    }

    private func pendingWarmupStatusText() -> String {
        switch runtimeState {
        case .cold(let modelName):
            return "Warming \(modelName)"
        case .warming(let modelName, _, _):
            return "Warming \(modelName)"
        case .failed(let modelName, _):
            return "Retrying \(modelName ?? "model")"
        default:
            return "Thinking locally"
        }
    }

    private func missingSupportedModelReason() -> String {
        if hasReadyModel {
            return "Activate one of your imported models to continue. Recommended target: \(supportedModelDisplayName)."
        }
        return "Import and activate a bookmark-backed local GGUF model to continue. Recommended target: \(supportedModelDisplayName)."
    }

    private func missingSupportedModelStatusText() -> String {
        hasReadyModel ? "Activate an imported model to continue" : "Import and activate a local model to continue"
    }

    private func importOutcomeMessage(for model: JarvisImportedModel) -> String {
        switch model.status {
        case .ready:
            if let profile = JarvisSupportedModelCatalog.profile(for: model.supportedProfileID) {
                let suffix = model.statusMessage.map { " \($0)" } ?? ""
                return "Imported \(model.displayName). Security-scoped bookmark stored. It matches the curated iPhone profile: \(profile.displayName). Activate it from Model Library.\(suffix)"
            }
            if let message = model.statusMessage, !message.isEmpty {
                return "Imported \(model.displayName). Security-scoped bookmark stored. \(message)"
            }
            return "Imported \(model.displayName). Security-scoped bookmark stored. Activate it from Model Library when ready."
        case .unsupported:
            return model.statusMessage ?? "Imported \(model.displayName), but the file is not currently supported."
        case .invalid:
            return model.statusMessage ?? "Imported \(model.displayName), but the file is invalid."
        case .missing:
            return model.statusMessage ?? "Imported model file is missing."
        case .failed:
            return model.statusMessage ?? "Model import failed validation."
        }
    }

    private func refreshAssistantSuggestions() {
        guard let latestAssistant = conversation.messages.last(where: { $0.role == .assistant }),
              !latestAssistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            assistantSuggestions = []
            return
        }

        assistantSuggestions = [
            AssistantSuggestion(
                title: "Ask follow-up",
                icon: "arrow.turn.down.right",
                action: .prompt("Can you expand with one practical example?")
            ),
            AssistantSuggestion(
                title: "Summarize answer",
                icon: "text.quote",
                action: .prompt("Summarize your last answer in 3 bullets.")
            ),
            AssistantSuggestion(
                title: "Save to knowledge",
                icon: "bookmark",
                action: .saveToKnowledge
            ),
            AssistantSuggestion(
                title: "Continue voice",
                icon: "waveform",
                action: .route(JarvisLaunchRoute(action: .voice, source: "assistant.suggestion"))
            )
        ]
    }

    private func persistCurrentConversation() {
        var copy = conversation
        guard !copy.messages.isEmpty else {
            conversations = store.loadConversations()
            return
        }

        copy.updatedAt = Date()
        if let firstUser = copy.messages.first(where: { $0.role == .user }) {
            copy.title = String(firstUser.text.prefix(40))
        }
        store.saveConversation(copy)
        conversations = store.loadConversations()
        conversation = conversations.first(where: { $0.id == copy.id }) ?? copy
    }

    private func appendStreamingToken(_ token: String, id: UUID) async {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[index].text += token
        conversation.messages[index].isStreaming = true
    }

    private func finalizeStreamingMessage(id: UUID) async {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[index].isStreaming = false
    }

    private func replaceStreamingMessage(id: UUID, with text: String) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[index].text = text
        conversation.messages[index].isStreaming = false
    }
}
