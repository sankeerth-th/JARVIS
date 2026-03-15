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

    enum AssistantEntryStyle: Equatable {
        case standard
        case assistant
        case chat
        case quickAsk
        case quickCapture
        case draftReply
        case summarize
        case continueConversation
        case voiceFirst
        case visualPreview
        case systemAssistant
    }

    enum AssistantExperienceState: Equatable {
        case idle
        case armed
        case listening
        case transcribing
        case thinking
        case processing
        case grounding
        case responding
        case answerReady
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
            case .processing:
                return "Processing"
            case .grounding:
                return "Grounding"
            case .responding:
                return "Responding"
            case .answerReady:
                return "Answer Ready"
            case .error:
                return "Attention Needed"
            case .unavailable:
                return "Unavailable"
            }
        }
    }

    enum AssistantRuntimeGateStatus: Equatable {
        case noModel(String)
        case unsupportedModel(String)
        case fileAccessPending(String)
        case fileAccessLost(String)
        case runtimeCold(String)
        case warming(String)
        case ready
        case failed(String)

        var detail: String {
            switch self {
            case .noModel(let detail),
                 .unsupportedModel(let detail),
                 .fileAccessPending(let detail),
                 .fileAccessLost(let detail),
                 .runtimeCold(let detail),
                 .warming(let detail),
                 .failed(let detail):
                return detail
            case .ready:
                return "Ready"
            }
        }
    }

    enum AssistantSuggestionAction: Equatable {
        case prompt(String)
        case task(JarvisAssistantTask, String)
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
    @Published var runtimeFailure: JarvisRuntimeFailure?
    @Published var modelFileAccessState: JarvisModelFileAccessState
    @Published var runtimeLoadDiagnostics: JarvisRuntimeLoadDiagnostics?
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
    @Published private(set) var assistantEntryStyle: AssistantEntryStyle = .standard
    @Published private(set) var assistantEntryDate: Date = .distantPast
    @Published private(set) var assistantTask: JarvisAssistantTask = .chat
    @Published private(set) var activeAssistantRoute: JarvisAssistantEntryRoute = .assistant
    @Published private(set) var assistantTaskContext = JarvisAssistantTaskContext(task: .chat, source: "launch")
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
        models.contains(where: \.canActivate)
    }

    var needsModelSetup: Bool {
        guard let activeModel else { return true }
        return !activeModel.canActivate
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

    var canRunVisualAssistant: Bool {
        runtime.supportsVisualInputs
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

    var supportedModelClassificationText: String {
        supportedModelProfile.compatibilityClass.displayName
    }

    var supportedModelCapabilitySummary: String {
        let capabilities = supportedModelProfile.runtimeCapabilities
        if capabilities.supportsVisionInputs {
            return capabilities.requiresProjectorForVision
                ? "Text-first today, projector-backed vision later."
                : "Text and visual assistant capable."
        }
        return "Text-first on-device assistant path."
    }

    var activeModelSupportStatusText: String {
        guard let activeModel else {
            return "No active local model selected"
        }
        if let profile = JarvisSupportedModelCatalog.profile(for: activeModel.supportedProfileID) {
            return "\(profile.compatibilityClass.displayName): \(profile.displayName)"
        }
        return activeModel.statusMessage ?? "Valid GGUF import with no curated profile match. Activation is allowed, but performance and quality are unverified on this device."
    }

    var activeModelVisualStatusText: String {
        guard let activeModel else {
            return "No active model"
        }
        return activeModel.visualReadinessDescription
    }

    var visualAssistantStatusText: String {
        if needsModelSetup {
            return missingSupportedModelReason()
        }
        if !canRunInference {
            return runtimeBlockedReason
        }
        if canRunVisualAssistant {
            return "Visual runtime is available for the active model."
        }
        if let activeModel, activeModel.capabilities.supportsVisionInputs {
            return activeModel.hasProjectorAttached
                ? "Visual entry is staged, but the current runtime remains text-only."
                : "Attach the projector to keep the model vision-ready for a future runtime update."
        }
        return "Visual assistant preview is available, but the active model is text-only."
    }

    var modelFileAccessDetail: String {
        modelFileAccessState.detail
    }

    var assistantRuntimeGateStatus: AssistantRuntimeGateStatus {
        if let activeModel, activeModel.activationEligibility != .eligible {
            return .unsupportedModel(activeModel.statusMessage ?? "The selected model is not activatable on iPhone.")
        }

        switch modelFileAccessState {
        case .noImportedFile:
            return .noModel(missingSupportedModelReason())
        case .bookmarkCreated(_, let detail), .accessPending(_, let detail):
            return .fileAccessPending(detail)
        case .accessLost(_, let reason), .bookmarkResolutionFailed(_, let reason):
            return .fileAccessLost(reason)
        case .accessGranted:
            break
        }

        switch runtimeState {
        case .noModel:
            return .noModel(missingSupportedModelReason())
        case .runtimeUnavailable(let reason):
            return .failed(reason)
        case .cold(let modelName):
            return .runtimeCold("\(modelName) is loaded and will warm on demand.")
        case .warming(let modelName, _, let detail):
            return .warming("\(modelName): \(detail)")
        case .ready:
            return .ready
        case .busy(let modelName, let detail):
            return .warming("\(modelName): \(detail)")
        case .paused(let modelName, let detail):
            return .runtimeCold("\(modelName ?? "Runtime"): \(detail)")
        case .failed(_, let failure):
            return .failed(failure.message)
        }
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
    private var pendingAssistantRequest: JarvisAssistantRequest?

    init(
        store: JarvisConversationStore = JarvisConversationStore(),
        modelLibrary: JarvisModelLibrary = JarvisModelLibrary(),
        launchStore: JarvisLaunchRouteStore = .shared,
        settingsStore: JarvisAssistantSettingsStore = JarvisAssistantSettingsStore(),
        speechCoordinator: JarvisSpeechCoordinator? = nil
    ) {
        let loadedSettings = settingsStore.load()
        self.store = store
        self.modelLibrary = modelLibrary
        self.launchStore = launchStore
        self.settingsStore = settingsStore
        self.settings = loadedSettings

        self.runtime = JarvisLocalModelRuntime(configuration: loadedSettings.runtimeConfiguration)
        self.speechCoordinator = speechCoordinator ?? JarvisSpeechCoordinator()
        self.runtimeState = runtime.state
        self.runtimeFailure = runtime.lastFailure
        self.modelFileAccessState = runtime.fileAccessState
        self.runtimeLoadDiagnostics = runtime.lastLoadDiagnostics

        let loadedConversations = store.loadConversations()
        self.conversations = loadedConversations
        self.conversation = loadedConversations.first ?? JarvisConversationRecord(title: "Jarvis")
        self.knowledgeItems = store.loadKnowledgeItems()

        self.quickLaunchItems = [
            QuickLaunchItem(
                title: "Ask Jarvis",
                subtitle: "Open directly into chat",
                icon: "sparkles",
                route: .assistant(.chat, task: .chat, source: .inApp, shouldFocusComposer: true)
            ),
            QuickLaunchItem(
                title: "Voice Mode",
                subtitle: "Launch listening-first assistant",
                icon: "waveform.circle.fill",
                route: .assistant(.voice, task: .chat, source: .inApp, shouldStartListening: true)
            ),
            QuickLaunchItem(
                title: "Visual Intelligence",
                subtitle: "Open camera-intelligence workspace",
                icon: "viewfinder.circle.fill",
                route: .assistant(.visual, task: .visualDescribe, source: .inApp)
            ),
            QuickLaunchItem(
                title: "Quick Capture",
                subtitle: "Drop text and continue later",
                icon: "square.and.pencil",
                route: JarvisLaunchRoute(action: .quickCapture, source: JarvisAssistantEntrySource.inApp.rawValue, assistantTask: .quickCapture, shouldFocusComposer: true)
            ),
            QuickLaunchItem(
                title: "Summarize Text",
                subtitle: "Turn long text into key points",
                icon: "text.quote",
                route: JarvisLaunchRoute(action: .summarize, source: JarvisAssistantEntrySource.inApp.rawValue, assistantTask: .summarize, shouldFocusComposer: true)
            ),
            QuickLaunchItem(
                title: "Search Local Knowledge",
                subtitle: "Find previous notes and answers",
                icon: "magnifyingglass",
                route: .assistant(.knowledge, source: .inApp)
            ),
            QuickLaunchItem(
                title: "Continue Last Conversation",
                subtitle: "Resume where you left off",
                icon: "arrow.uturn.forward.circle",
                route: .assistant(.continueConversation, task: .chat, source: .inApp, shouldFocusComposer: true)
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

        runtime.$lastFailure
            .receive(on: DispatchQueue.main)
            .sink { [weak self] failure in
                self?.runtimeFailure = failure
            }
            .store(in: &cancellables)

        runtime.$lastLoadDiagnostics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] diagnostics in
                self?.runtimeLoadDiagnostics = diagnostics
            }
            .store(in: &cancellables)

        self.speechCoordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.speechState = state
                self.syncAssistantExperienceWithSpeech(state)
            }
            .store(in: &cancellables)

        self.speechCoordinator.$permissions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] permissions in
                self?.speechPermissions = permissions
            }
            .store(in: &cancellables)

        self.speechCoordinator.$transcript
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
                self.runtimeFailure = self.runtime.lastFailure
                self.runtimeLoadDiagnostics = self.runtime.lastLoadDiagnostics
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
        runtimeFailure = runtime.lastFailure
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
            runtimeFailure = runtime.lastFailure
            _ = consumePendingRouteIfNeeded()
        case .background:
            persistCurrentConversation()
            if settings.unloadModelOnBackground || settings.batterySaverMode {
                Task {
                    await runtime.unload()
                    await MainActor.run {
                        runtimeState = runtime.state
                        runtimeFailure = runtime.lastFailure
                    }
                }
            } else {
                runtime.pauseForBackground()
                runtimeState = runtime.state
                runtimeFailure = runtime.lastFailure
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
            assistantEntryStyle = .standard
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
        assistantEntryStyle = .standard
        selectedTab = destination
        assistantExperienceState = needsModelSetup ? .unavailable(reason: missingSupportedModelReason()) : .idle
        statusText = "Ready"
    }

    func apply(route: JarvisLaunchRoute) {
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
            assistantEntryStyle = .standard
            assistantTask = .chat
            activeAssistantRoute = .assistant
            assistantTaskContext = JarvisAssistantTaskContext(task: .chat, source: route.source)
            assistantExperienceState = needsModelSetup ? .unavailable(reason: missingSupportedModelReason()) : .idle
            statusText = "Ready"
        case .assistant:
            prepareConversationForFocusedEntry()
            setAssistantTask(route.assistantTask ?? .chat, source: route.source, seedText: route.payload)
            enterAssistant(
                mode: .text,
                status: "Assistant ready",
                focusComposer: route.shouldFocusComposer ?? true,
                entryRoute: .assistant,
                entryStyle: .assistant
            )
        case .chat, .ask:
            prepareConversationForFocusedEntry()
            setAssistantTask(route.assistantTask ?? .chat, source: route.source, seedText: route.payload)
            if let payload = route.payload, !payload.isEmpty {
                draft = payload
            }
            enterAssistant(
                mode: .text,
                status: route.action == .ask ? "Quick ask" : "Chat ready",
                focusComposer: route.shouldFocusComposer ?? true,
                entryRoute: .chat,
                entryStyle: route.action == .ask ? .quickAsk : .chat
            )
        case .quickCapture:
            prepareConversationForFocusedEntry()
            setAssistantTask(.quickCapture, source: route.source)
            let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            draft = (clipboard?.isEmpty == false) ? (clipboard ?? "") : ""
            enterAssistant(mode: .text, status: "Quick capture", focusComposer: route.shouldFocusComposer ?? true, entryRoute: .chat, entryStyle: .quickCapture)
        case .summarize:
            prepareConversationForFocusedEntry()
            setAssistantTask(.summarize, source: route.source)
            let seed = route.payload ?? UIPasteboard.general.string ?? ""
            draft = seed
            enterAssistant(mode: .text, status: "Summarize text", focusComposer: route.shouldFocusComposer ?? true, entryRoute: .chat, entryStyle: .summarize)
        case .search, .knowledge:
            selectedTab = .knowledge
            assistantReturnTab = nil
            assistantTask = .knowledgeAnswer
            activeAssistantRoute = .knowledge
            assistantTaskContext = JarvisAssistantTaskContext(task: .knowledgeAnswer, source: route.source, seedText: route.query ?? route.payload)
            knowledgeQuery = route.query ?? route.payload ?? ""
            refreshKnowledgeResults()
            assistantInputMode = .text
            assistantEntryStyle = .standard
            assistantExperienceState = .idle
            statusText = "Search local knowledge"
        case .draftReply:
            prepareConversationForFocusedEntry()
            let seed = route.payload ?? UIPasteboard.general.string ?? ""
            if !seed.isEmpty {
                draft = seed
            }
            setAssistantTask(.reply, source: route.source, seedText: seed, replyTargetText: seed)
            enterAssistant(
                mode: .text,
                status: "Draft reply",
                focusComposer: route.shouldFocusComposer ?? true,
                entryRoute: .draftReply,
                entryStyle: .draftReply
            )
        case .continueConversation:
            if let latest = conversations.first {
                conversation = latest
            }
            setAssistantTask(.chat, source: route.source)
            enterAssistant(mode: .text, status: "Continue conversation", focusComposer: route.shouldFocusComposer ?? true, entryRoute: .continueConversation, entryStyle: .continueConversation)
        case .voice:
            setAssistantTask(.chat, source: route.source)
            enterAssistant(mode: .voice, status: "Voice mode", focusComposer: false, entryRoute: .voice, entryStyle: .voiceFirst)
            if route.shouldStartListening ?? settings.autoStartListeningForVoiceEntry {
                startVoicePreview()
            } else {
                assistantExperienceState = needsModelSetup ? .unavailable(reason: missingSupportedModelReason()) : .armed
                statusText = "Voice entry ready"
            }
        case .visualIntelligence:
            selectedTab = .visual
            assistantReturnTab = nil
            assistantInputMode = .visual
            activeAssistantRoute = .visual
            assistantTask = .visualDescribe
            assistantTaskContext = JarvisAssistantTaskContext(task: .visualDescribe, source: route.source, seedText: route.payload)
            assistantEntryStyle = .visualPreview
            assistantExperienceState = canRunVisualAssistant ? .armed : .unavailable(reason: visualAssistantStatusText)
            statusText = "Visual assistant preview"
        case .settings:
            selectedTab = .settings
            assistantReturnTab = nil
            assistantInputMode = .text
            assistantEntryStyle = .standard
            assistantExperienceState = .idle
            statusText = "Settings"
        case .modelLibrary:
            selectedTab = .settings
            presentModelLibrary()
            statusText = "Model library"
        case .systemAssistant:
            prepareConversationForFocusedEntry()
            setAssistantTask(route.assistantTask ?? .analyzeText, source: route.source, seedText: route.payload)
            enterAssistant(
                mode: .text,
                status: "System assistant",
                focusComposer: route.shouldFocusComposer ?? true,
                entryRoute: .systemAssistant,
                entryStyle: .systemAssistant
            )
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
                modelFileAccessState = .accessPending(
                    modelName: imported.displayName,
                    detail: "Model copied into Jarvis app storage. Activate it before warmup."
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
            let activatedModel = try modelLibrary.activateModel(id: id)
            reloadModelLibrary()
            guard let activeModel = activeModel ?? models.first(where: { $0.id == activatedModel.id }) else {
                throw JarvisModelError.unavailable("No active model selected.")
            }

            showSetupFlow = needsModelSetup
            modelImportState = .idle
            if let profile = JarvisSupportedModelCatalog.profile(for: activeModel.supportedProfileID) {
                statusText = "Activated \(activeModel.displayName). \(profile.compatibilityClass.displayName): \(profile.activationGuidance)"
            } else {
                statusText = "Activated \(activeModel.displayName). Warm it now or let Jarvis auto-warm on first send."
            }
            assistantExperienceState = .armed
            runtimeFailure = nil
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
            statusText = "\(model.displayName): \(model.importState.displayName) / \(model.activationEligibility.displayName)"
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
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        guard validateAssistantSendAvailability(for: assistantTask) else { return }
        let request = buildAssistantRequest(prompt: cleanPrompt)
        pendingAssistantRequest = request

        if !settings.autoWarmOnFirstSend {
            switch runtimeState {
            case .cold, .failed, .paused:
                let reason = "Warm \(activeModel?.displayName ?? "the active model") before sending. Auto-warm on first send is turned off."
                draft = cleanPrompt
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
            var streamingID: UUID?
            do {
                try await self.runtime.prepareIfNeeded()
                let activeRequest = await MainActor.run { () -> JarvisAssistantRequest in
                    let activeRequest = self.pendingAssistantRequest ?? request
                    let newStreamingID = UUID()
                    var updated = self.conversation
                    updated.updatedAt = Date()
                    updated.messages.append(JarvisChatMessage(role: .user, text: activeRequest.prompt))
                    updated.messages.append(JarvisChatMessage(id: newStreamingID, role: .assistant, text: "", isStreaming: true))
                    self.conversation = updated
                    self.persistCurrentConversation()
                    self.runtimeState = self.runtime.state
                    self.runtimeFailure = self.runtime.lastFailure
                    streamingID = newStreamingID
                    self.pendingAssistantRequest = activeRequest
                    return activeRequest
                }

                let stream = self.runtime.streamResponse(request: activeRequest)
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
                    if let streamingID {
                        await self.appendStreamingToken(token, id: streamingID)
                    }
                }
                if let streamingID {
                    await self.finalizeStreamingMessage(id: streamingID)
                }
                await MainActor.run {
                    self.isSending = false
                    self.groundingTransitionTask?.cancel()
                    self.groundingTransitionTask = nil
                    self.statusText = "Ready"
                    self.runtimeState = self.runtime.state
                    self.runtimeFailure = self.runtime.lastFailure
                    self.assistantExperienceState = .answerReady
                    self.refreshAssistantSuggestions()
                    self.persistCurrentConversation()
                    self.pendingAssistantRequest = nil
                    JarvisHaptics.success()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    self.isSending = false
                    self.groundingTransitionTask?.cancel()
                    self.groundingTransitionTask = nil
                    self.runtimeState = self.runtime.state
                    self.runtimeFailure = self.runtime.lastFailure
                    self.statusText = message
                    if let streamingID {
                        self.replaceStreamingMessage(id: streamingID, with: "I couldn't complete that request: \(message)")
                        self.persistCurrentConversation()
                    } else {
                        self.draft = request.prompt
                    }
                    self.pendingAssistantRequest = request
                    self.assistantExperienceState = .error(message: message)
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
        runtimeFailure = runtime.lastFailure
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
            assistantEntryStyle = .standard
            assistantExperienceState = .armed
            shouldFocusComposer = true
        case .voice:
            assistantEntryStyle = .voiceFirst
            assistantEntryDate = Date()
            activeAssistantRoute = .voice
            shouldFocusComposer = false
            startVoicePreview()
        case .visual:
            assistantEntryStyle = .visualPreview
            activeAssistantRoute = .visual
            assistantTask = .visualDescribe
            assistantExperienceState = canRunVisualAssistant ? .armed : .unavailable(reason: visualAssistantStatusText)
            shouldFocusComposer = false
            apply(route: JarvisLaunchRoute(action: .visualIntelligence, source: "assistant.mode"))
        }
    }

    func startVoicePreview() {
        guard validateAssistantSendAvailability(for: .chat, presentSetup: false) else { return }

        assistantInputMode = .voice
        assistantLiveTranscript = ""
        assistantExperienceState = .processing
        statusText = "Preparing voice input"
        JarvisHaptics.listeningStart()

        let options = JarvisSpeechSessionOptions(
            localeIdentifier: settings.speechLocaleIdentifier,
            autoSendAfterSilence: settings.autoSendVoiceAfterPause,
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
            setAssistantTask(.chat, source: "assistant.suggestion", seedText: prompt)
            activeAssistantRoute = .chat
            draft = prompt
            shouldFocusComposer = true
            assistantInputMode = .text
            assistantExperienceState = .armed
        case .task(let task, let prompt):
            setAssistantTask(task, source: "assistant.suggestion", seedText: prompt, replyTargetText: task == .reply ? prompt : nil)
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
        activeAssistantRoute = .assistant
        setAssistantTask(.chat, source: "conversation.new")
        pendingAssistantRequest = nil
        assistantSuggestions = []
        assistantLiveTranscript = ""
        statusText = "New conversation"
        assistantExperienceState = .armed
    }

    func openConversation(_ record: JarvisConversationRecord, source: String) {
        conversation = record
        setAssistantTask(.chat, source: source)
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

    func askWithKnowledgeResult(_ result: JarvisKnowledgeResult) {
        setAssistantTask(.knowledgeAnswer, source: "knowledge.result", seedText: knowledgeQuery.isEmpty ? result.item.title : knowledgeQuery)
        enterAssistant(mode: .text, status: "Grounded answer", focusComposer: true, source: "knowledge.result")
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
        runtimeFailure = runtime.lastFailure

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

        if let activeModel, activeModel.canActivate {
            let selection = modelLibrary.runtimeSelection(for: activeModel)
            runtime.setSelectedModel(selection)
        } else {
            runtime.setSelectedModel(nil)
        }

        runtimeState = runtime.state
        runtimeFailure = runtime.lastFailure
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
                    runtimeFailure = runtime.lastFailure
                    statusText = "Model warmed"
                    if !needsModelSetup {
                        assistantExperienceState = .armed
                    }
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    runtimeState = runtime.state
                    runtimeFailure = runtime.lastFailure
                    statusText = message
                    assistantExperienceState = .error(message: message)
                }
            }
        }
    }

    private func prepareConversationForFocusedEntry() {
        if selectedTab != .assistant && !conversation.messages.isEmpty {
            persistCurrentConversation()
            conversation = JarvisConversationRecord(title: "New Conversation")
        }
        assistantSuggestions = []
        assistantLiveTranscript = ""
        pendingAssistantRequest = nil
    }

    private func setAssistantTask(
        _ task: JarvisAssistantTask,
        source: String,
        seedText: String? = nil,
        replyTargetText: String? = nil
    ) {
        assistantTask = task
        assistantTaskContext = JarvisAssistantTaskContext(
            task: task,
            source: source,
            seedText: seedText,
            replyTargetText: replyTargetText,
            groundedResults: task == .knowledgeAnswer ? Array(knowledgeResults.prefix(task.groundingLimit)) : []
        )
        if let seedText, !seedText.isEmpty {
            draft = seedText
        }
    }

    private func buildAssistantRequest(prompt: String) -> JarvisAssistantRequest {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = Array(conversation.messages.suffix(assistantTask.historyLimit))
        let groundedResults: [JarvisKnowledgeResult]
        switch assistantTask {
        case .knowledgeAnswer:
            groundedResults = Array(knowledgeResults.prefix(assistantTask.groundingLimit))
        default:
            groundedResults = []
        }

        let replyTargetText: String?
        if assistantTask == .reply {
            replyTargetText = assistantTaskContext.replyTargetText ?? conversation.messages.last(where: { $0.role == .assistant || $0.role == .user })?.text
        } else {
            replyTargetText = nil
        }

        return JarvisAssistantRequest(
            task: assistantTask,
            prompt: trimmedPrompt,
            source: assistantTaskContext.source,
            history: history,
            groundedResults: groundedResults,
            replyTargetText: replyTargetText
        )
    }

    private func validateAssistantSendAvailability(
        for task: JarvisAssistantTask,
        presentSetup: Bool = true
    ) -> Bool {
        if needsModelSetup {
            if presentSetup {
                showSetupFlow = true
            }
            statusText = missingSupportedModelStatusText()
            assistantExperienceState = .unavailable(reason: missingSupportedModelReason())
            JarvisHaptics.error()
            return false
        }

        if !canRunInference {
            statusText = runtimeBlockedReason
            assistantExperienceState = .unavailable(reason: runtimeBlockedReason)
            JarvisHaptics.error()
            return false
        }

        if task == .visualDescribe && !canRunVisualAssistant {
            statusText = visualAssistantStatusText
            assistantExperienceState = .unavailable(reason: visualAssistantStatusText)
            JarvisHaptics.error()
            return false
        }

        return true
    }

    private func enterAssistant(
        mode: AssistantInputMode,
        status: String,
        focusComposer: Bool,
        source: String = "route",
        entryRoute: JarvisAssistantEntryRoute = .assistant,
        entryStyle: AssistantEntryStyle = .standard
    ) {
        if selectedTab != .assistant {
            assistantReturnTab = selectedTab
        }
        selectedTab = .assistant
        assistantInputMode = mode
        activeAssistantRoute = entryRoute
        assistantEntryStyle = entryStyle
        assistantEntryDate = Date()
        shouldFocusComposer = focusComposer
        let unavailableReason = assistantEntryUnavailableReason(for: entryRoute, mode: mode)
        assistantExperienceState = unavailableReason.map(AssistantExperienceState.unavailable) ?? (mode == .voice ? .listening : .armed)
        statusText = unavailableReason ?? status
        if source == "route" {
            JarvisHaptics.selection()
        }
    }

    private func assistantEntryUnavailableReason(
        for route: JarvisAssistantEntryRoute,
        mode: AssistantInputMode
    ) -> String? {
        if needsModelSetup {
            return missingSupportedModelReason()
        }
        if !canRunInference {
            return runtimeBlockedReason
        }
        if route == .visual || mode == .visual, !canRunVisualAssistant {
            return visualAssistantStatusText
        }
        return nil
    }

    private func handleCommittedSpeechTranscript(_ transcript: String) {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        assistantLiveTranscript = clean
        assistantExperienceState = .processing
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
        case .failed(_, let failure):
            assistantExperienceState = .error(message: failure.message)
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
            assistantExperienceState = .processing
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
        return "Import and activate a local GGUF model to continue. Recommended target: \(supportedModelDisplayName)."
    }

    private func missingSupportedModelStatusText() -> String {
        hasReadyModel ? "Activate an imported model to continue" : "Import and activate a local model to continue"
    }

    private func importOutcomeMessage(for model: JarvisImportedModel) -> String {
        switch (model.importState, model.activationEligibility) {
        case (.imported, .eligible):
            if let profile = JarvisSupportedModelCatalog.profile(for: model.supportedProfileID) {
                return "Imported \(model.displayName). Local sandbox copy stored. It matches the \(profile.compatibilityClass.displayName.lowercased()) iPhone profile: \(profile.displayName). Activate it from Model Library."
            }
            return "Imported \(model.displayName). Local sandbox copy stored. It is a valid GGUF import and can be activated from Model Library, though device performance may vary."
        case (.imported, .unsupportedProfile):
            return model.statusMessage ?? "Imported \(model.displayName), but Jarvis still needs the file revalidated before activation."
        case (.imported, .accessLost):
            return model.statusMessage ?? "Imported \(model.displayName), but Jarvis lost access to the file."
        case (.imported, .validationFailed):
            return model.statusMessage ?? "Imported \(model.displayName), but validation failed before activation."
        case (.missing, _):
            return model.statusMessage ?? "Imported model file is missing."
        case (.invalid, _):
            return model.statusMessage ?? "Imported model failed GGUF validation."
        case (.failed, _):
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
                action: .task(.summarize, latestAssistant.text)
            ),
            AssistantSuggestion(
                title: "Draft a reply",
                icon: "arrowshape.turn.up.left",
                action: .task(.reply, latestAssistant.text)
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
