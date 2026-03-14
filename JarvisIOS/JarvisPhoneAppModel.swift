import Foundation
import SwiftUI
import UIKit
import Combine

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

    @Published var conversation: JarvisConversationRecord
    @Published var conversations: [JarvisConversationRecord]
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var statusText: String = "Ready"
    @Published var runtimeState: JarvisModelRuntimeState
    @Published var knowledgeQuery: String = ""
    @Published var knowledgeResults: [JarvisKnowledgeResult] = []
    @Published var knowledgeItems: [JarvisKnowledgeItem] = []

    @Published var models: [JarvisImportedModel] = []
    @Published var activeModelID: UUID?
    @Published var modelImportState: ModelImportState = .idle

    @Published var isAssistantPresented = false
    @Published var isKnowledgePresented = false
    @Published var isSettingsPresented = false
    @Published var isModelLibraryPresented = false
    @Published var isModelImporterPresented = false
    @Published var showSetupFlow = false
    @Published var shouldFocusComposer = false

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

    private let store: JarvisConversationStore
    private let modelLibrary: JarvisModelLibrary
    private let launchStore: JarvisLaunchRouteStore
    private let runtime: JarvisLocalModelRuntime
    private var streamTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: JarvisConversationStore = JarvisConversationStore(),
        modelLibrary: JarvisModelLibrary = JarvisModelLibrary(),
        launchStore: JarvisLaunchRouteStore = .shared
    ) {
        self.store = store
        self.modelLibrary = modelLibrary
        self.launchStore = launchStore

        self.runtime = JarvisLocalModelRuntime()
        self.runtimeState = runtime.state

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

        runtime.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.runtimeState = state
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
    }

    func bootstrap() {
        reloadModelLibrary()
        runtimeState = runtime.state
        showSetupFlow = needsModelSetup
        consumePendingRouteIfNeeded()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            runtime.resumeFromForeground()
            runtimeState = runtime.state
            consumePendingRouteIfNeeded()
        case .background:
            runtime.pauseForBackground()
            runtimeState = runtime.state
            persistCurrentConversation()
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

    func apply(route: JarvisLaunchRoute) {
        if routeRequiresModel(route.action), needsModelSetup {
            showSetupFlow = true
            isModelLibraryPresented = false
            isAssistantPresented = false
            statusText = "Import a GGUF model to continue"
            JarvisHaptics.error()
            return
        }

        switch route.action {
        case .home:
            isAssistantPresented = false
            isKnowledgePresented = false
            isSettingsPresented = false
            showSetupFlow = needsModelSetup
            statusText = "Ready"
        case .ask:
            if let payload = route.payload, !payload.isEmpty {
                draft = payload
            }
            isAssistantPresented = true
            shouldFocusComposer = true
            statusText = "Ask Jarvis"
        case .quickCapture:
            let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            draft = (clipboard?.isEmpty == false) ? (clipboard ?? "") : ""
            isAssistantPresented = true
            shouldFocusComposer = true
            statusText = "Quick capture"
        case .summarize:
            let seed = route.payload ?? UIPasteboard.general.string ?? ""
            if seed.isEmpty {
                draft = ""
            } else {
                draft = "Summarize this into concise bullets:\n\(seed)"
            }
            isAssistantPresented = true
            shouldFocusComposer = true
            statusText = "Summarize text"
        case .search:
            knowledgeQuery = route.payload ?? ""
            refreshKnowledgeResults()
            isKnowledgePresented = true
            statusText = "Search local knowledge"
        case .continueConversation:
            if let latest = conversations.first {
                conversation = latest
            }
            isAssistantPresented = true
            shouldFocusComposer = true
            statusText = "Continue conversation"
        }

        JarvisHaptics.selection()
    }

    func beginModelImport() {
        modelImportState = .idle
        isModelImporterPresented = true
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
            importModel(from: source)
        }
    }

    func importModel(from sourceURL: URL) {
        Task {
            do {
                print("[JarvisPhoneAppModel] importModel source=\(sourceURL.path)")
                modelImportState = .importing(progress: 0.04, message: "Starting import")
                let imported = try modelLibrary.importModel(from: sourceURL) { progress, message in
                    Task { @MainActor in
                        self.modelImportState = .importing(progress: progress, message: message)
                    }
                }
                reloadModelLibrary()
                if imported.status == .ready {
                    let importedFileURL = modelLibrary.modelFileURL(for: imported)
                    guard FileManager.default.fileExists(atPath: importedFileURL.path) else {
                        throw JarvisModelError.unavailable("Imported model file is missing from local storage.")
                    }
                    try? modelLibrary.setActiveModel(id: imported.id)
                    reloadModelLibrary()
                    let warmed = await warmActiveModelIfPossible()
                    guard warmed else {
                        throw JarvisModelError.runtimeFailure(runtimeFailureMessage())
                    }
                }

                let successText = "Imported \(imported.displayName)"
                statusText = successText
                modelImportState = .success(message: successText)
                showSetupFlow = needsModelSetup
                JarvisHaptics.success()
            } catch {
                statusText = "Model import failed"
                modelImportState = .failure(message: error.localizedDescription)
                JarvisHaptics.error()
            }
        }
    }

    func setActiveModel(id: UUID) {
        Task {
            do {
                print("[JarvisPhoneAppModel] setActiveModel id=\(id)")
                try modelLibrary.setActiveModel(id: id)
                reloadModelLibrary()
                guard let activeModel else {
                    throw JarvisModelError.unavailable("No active model selected.")
                }
                let modelURL = modelLibrary.modelFileURL(for: activeModel)
                guard FileManager.default.fileExists(atPath: modelURL.path) else {
                    throw JarvisModelError.unavailable("The selected model file is missing. Re-import it.")
                }
                let warmed = await warmActiveModelIfPossible()
                guard warmed else {
                    throw JarvisModelError.runtimeFailure(runtimeFailureMessage())
                }
                showSetupFlow = needsModelSetup
                statusText = "Using \(activeModel.displayName)"
                modelImportState = .idle
                JarvisHaptics.selection()
            } catch {
                statusText = "Could not activate model"
                modelImportState = .failure(message: error.localizedDescription)
            }
        }
    }

    func removeModel(id: UUID) {
        do {
            try modelLibrary.removeModel(id: id)
            reloadModelLibrary()
            showSetupFlow = needsModelSetup
            statusText = needsModelSetup ? "Import a GGUF model to continue" : "Model removed"
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
            showSetupFlow = true
            statusText = "Import a GGUF model to continue"
            JarvisHaptics.error()
            return
        }

        if !canRunInference {
            statusText = runtimeBlockedReason
            JarvisHaptics.error()
            return
        }

        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        streamTask?.cancel()
        runtimeState = runtime.state

        // Keep only prior messages as model context; the current prompt is passed separately.
        let historyForRuntime = conversation.messages

        var updated = conversation
        updated.updatedAt = Date()
        updated.messages.append(JarvisChatMessage(role: .user, text: cleanPrompt))
        let streamingID = UUID()
        updated.messages.append(JarvisChatMessage(id: streamingID, role: .assistant, text: "", isStreaming: true))
        conversation = updated
        persistCurrentConversation()

        isSending = true
        statusText = "Thinking locally"
        JarvisHaptics.softImpact()

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.runtime.streamResponse(prompt: cleanPrompt, history: historyForRuntime)
                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    await self.appendStreamingToken(token, id: streamingID)
                }
                await self.finalizeStreamingMessage(id: streamingID)
                await MainActor.run {
                    self.isSending = false
                    self.statusText = "Ready"
                    self.runtimeState = self.runtime.state
                    self.persistCurrentConversation()
                    JarvisHaptics.success()
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.runtimeState = self.runtime.state
                    self.statusText = error.localizedDescription
                    self.replaceStreamingMessage(id: streamingID, with: "I couldn't complete that request: \(error.localizedDescription)")
                    self.persistCurrentConversation()
                    JarvisHaptics.error()
                }
            }
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        runtime.cancel()
        isSending = false
        runtimeState = runtime.state
        statusText = "Cancelled"
        JarvisHaptics.selection()
    }

    func warmModel() {
        if needsModelSetup {
            showSetupFlow = true
            statusText = "Import a GGUF model first"
            return
        }

        if !canRunInference {
            statusText = runtimeBlockedReason
            return
        }

        Task {
            do {
                try await runtime.prepareIfNeeded()
                await MainActor.run {
                    runtimeState = runtime.state
                    statusText = "Model warmed"
                }
            } catch {
                await MainActor.run {
                    runtimeState = runtime.state
                    statusText = error.localizedDescription
                }
            }
        }
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

    private func consumePendingRouteIfNeeded() {
        if let pending = launchStore.consumePendingRoute() {
            apply(route: pending)
        }
    }

    private func reloadModelLibrary() {
        models = modelLibrary.loadModels()
        activeModelID = modelLibrary.activeModelID()

        if activeModelID == nil,
           let firstReady = models.first(where: { $0.status == .ready }) {
            try? modelLibrary.setActiveModel(id: firstReady.id)
            models = modelLibrary.loadModels()
            activeModelID = modelLibrary.activeModelID()
        }

        if let activeModel, activeModel.status == .ready {
            let modelURL = modelLibrary.modelFileURL(for: activeModel)
            if FileManager.default.fileExists(atPath: modelURL.path) {
                let selection = JarvisRuntimeModelSelection(
                    displayName: activeModel.displayName,
                    path: modelURL.path
                )
                print("[JarvisPhoneAppModel] runtime selection ready model=\(activeModel.displayName) path=\(modelURL.path)")
                runtime.setSelectedModel(selection)
            } else {
                print("[JarvisPhoneAppModel] active model missing on disk path=\(modelURL.path)")
                runtime.setSelectedModel(nil)
            }
        } else {
            runtime.setSelectedModel(nil)
        }
        runtimeState = runtime.state
    }

    private func warmActiveModelIfPossible() async -> Bool {
        guard let activeModel, activeModel.status == .ready else { return false }
        let modelURL = modelLibrary.modelFileURL(for: activeModel)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            await MainActor.run {
                self.runtime.setSelectedModel(nil)
                self.runtimeState = .unavailable(reason: "Selected model file is missing. Re-import \(activeModel.displayName).")
            }
            return false
        }

        print("[JarvisPhoneAppModel] warming active model \(activeModel.displayName)")
        do {
            try await runtime.prepareIfNeeded()
            await MainActor.run {
                self.runtimeState = self.runtime.state
            }
            return true
        } catch {
            await MainActor.run {
                self.runtimeState = self.runtime.state
                self.modelImportState = .failure(message: error.localizedDescription)
            }
            return false
        }
    }

    private func runtimeFailureMessage() -> String {
        switch runtime.state {
        case .failed(let message):
            return message
        case .unavailable(let reason):
            return reason
        default:
            return "Model could not be prepared."
        }
    }

    private func routeRequiresModel(_ action: JarvisLaunchAction) -> Bool {
        switch action {
        case .ask, .quickCapture, .summarize, .continueConversation:
            return true
        case .home, .search:
            return false
        }
    }

    private func persistCurrentConversation() {
        var copy = conversation
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
