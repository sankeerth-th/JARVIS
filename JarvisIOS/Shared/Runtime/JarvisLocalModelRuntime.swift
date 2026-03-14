import Foundation
import Combine

#if canImport(LocalLLMClientLlama)
import LocalLLMClientCore
import LocalLLMClientLlama
#endif

public enum JarvisGGUFEngineCapability: Equatable {
    case fullInference
    case placeholder
}

public enum JarvisModelFileAccessState: Equatable {
    case noImportedFile
    case bookmarkCreated(modelName: String, detail: String)
    case accessPending(modelName: String, detail: String)
    case accessGranted(modelName: String, detail: String)
    case accessLost(modelName: String?, reason: String)
    case bookmarkResolutionFailed(modelName: String?, reason: String)

    public var title: String {
        switch self {
        case .noImportedFile:
            return "No Imported File"
        case .bookmarkCreated:
            return "Bookmark Stored"
        case .accessPending:
            return "Access Pending"
        case .accessGranted:
            return "Access Granted"
        case .accessLost:
            return "Access Lost"
        case .bookmarkResolutionFailed:
            return "Bookmark Failed"
        }
    }

    public var detail: String {
        switch self {
        case .noImportedFile:
            return "Import a GGUF model from Files."
        case .bookmarkCreated(_, let detail),
                .accessPending(_, let detail),
                .accessGranted(_, let detail):
            return detail
        case .accessLost(_, let reason),
                .bookmarkResolutionFailed(_, let reason):
            return reason
        }
    }
}

public final class JarvisRuntimeResolvedModelResources {
    public let modelURL: URL
    public let projectorURL: URL?

    private let releaseHandler: () -> Void
    private var didRelease = false

    public init(modelURL: URL, projectorURL: URL?, releaseHandler: @escaping () -> Void) {
        self.modelURL = modelURL
        self.projectorURL = projectorURL
        self.releaseHandler = releaseHandler
    }

    public func release() {
        guard !didRelease else { return }
        didRelease = true
        releaseHandler()
    }

    deinit {
        release()
    }
}

public struct JarvisRuntimeModelSelection {
    public var id: UUID
    public var displayName: String
    public var family: JarvisModelFamily
    public var modality: JarvisModelModality
    public var capabilities: JarvisModelCapabilities
    public var projectorAttached: Bool
    public var inactiveAccessDetail: String
    public var acquireResources: () throws -> JarvisRuntimeResolvedModelResources

    public init(
        id: UUID,
        displayName: String,
        family: JarvisModelFamily,
        modality: JarvisModelModality,
        capabilities: JarvisModelCapabilities,
        projectorAttached: Bool,
        inactiveAccessDetail: String,
        acquireResources: @escaping () throws -> JarvisRuntimeResolvedModelResources
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.modality = modality
        self.capabilities = capabilities
        self.projectorAttached = projectorAttached
        self.inactiveAccessDetail = inactiveAccessDetail
        self.acquireResources = acquireResources
    }
}

public enum JarvisModelRuntimeState: Equatable {
    case noModel
    case runtimeUnavailable(reason: String)
    case cold(modelName: String)
    case warming(modelName: String, progress: Double, detail: String)
    case ready(modelName: String)
    case busy(modelName: String, detail: String)
    case paused(modelName: String?, detail: String)
    case failed(modelName: String?, message: String)

    public var title: String {
        switch self {
        case .noModel:
            return "No Model"
        case .runtimeUnavailable:
            return "Runtime Unavailable"
        case .cold:
            return "Model Cold"
        case .warming:
            return "Warming Model"
        case .ready:
            return "Ready"
        case .busy:
            return "Busy"
        case .paused:
            return "Paused"
        case .failed:
            return "Model Error"
        }
    }
}

public enum JarvisModelError: LocalizedError {
    case unavailable(String)
    case cancelled
    case runtimeFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .cancelled:
            return "Generation was cancelled"
        case .runtimeFailure(let message):
            return message
        }
    }
}

public protocol JarvisGGUFEngine {
    var name: String { get }
    var isInstalled: Bool { get }
    var capability: JarvisGGUFEngineCapability { get }
    var supportsVisualInputs: Bool { get }

    func updateConfiguration(_ configuration: JarvisRuntimeConfiguration)
    func loadModel(at path: String, projectorPath: String?) async throws
    func unloadModel() async
    func generate(
        prompt: String,
        history: [JarvisChatMessage],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws
    func cancelGeneration()
}

public final class StubGGUFEngine: JarvisGGUFEngine {
    public init() {}

    public var name: String { "Stub GGUF Engine" }
    public var isInstalled: Bool { true }
    public var capability: JarvisGGUFEngineCapability { .placeholder }
    public var supportsVisualInputs: Bool { false }

    public func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        _ = configuration
    }

    public func loadModel(at path: String, projectorPath: String?) async throws {
        _ = projectorPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw JarvisModelError.unavailable("Model file not found at: \(path)")
        }
        try await Task.sleep(nanoseconds: 120_000_000)
    }

    public func unloadModel() async {}

    public func generate(
        prompt: String,
        history: [JarvisChatMessage],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        _ = prompt
        _ = history
        _ = onToken

        #if targetEnvironment(simulator)
        throw JarvisModelError.runtimeFailure(
            "GGUF inference is not available in the iOS Simulator. Test on a physical device."
        )
        #else
        throw JarvisModelError.runtimeFailure(
            "This build does not include a working GGUF inference engine. Ensure LocalLLMClient is linked."
        )
        #endif
    }

    public func cancelGeneration() {}
}

#if canImport(LocalLLMClientLlama)
@available(iOS 17.0, *)
public final class JarvisLocalLLMClientEngine: JarvisGGUFEngine {
    private static let baseSystemInstruction =
        "You are Jarvis, a concise and practical on-device iPhone assistant. Keep answers direct and useful."

    private let lock = NSLock()
    private var session: LLMSession?
    private var loadedModelPath: String?
    private var cancelRequested = false
    private var configuration = JarvisRuntimeConfiguration()

    public init() {}

    public var name: String { "LocalLLMClient (llama.cpp)" }
    public var isInstalled: Bool { true }
    public var capability: JarvisGGUFEngineCapability { .fullInference }
    public var supportsVisualInputs: Bool { false }

    public func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        withLock {
            self.configuration = configuration
        }
    }

    public func loadModel(at path: String, projectorPath: String?) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw JarvisModelError.unavailable("Selected model file could not be found at path: \(path)")
        }

        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard pathExtension == "gguf" else {
            throw JarvisModelError.runtimeFailure("Unsupported model format '.\(pathExtension)'. Jarvis iPhone supports GGUF only.")
        }

        if let projectorPath {
            if FileManager.default.fileExists(atPath: projectorPath) {
                print("[JarvisRuntime] Projector attached for future multimodal support: \(projectorPath)")
            } else {
                throw JarvisModelError.unavailable("Projector file could not be found at path: \(projectorPath)")
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        guard fileSize > 0 else {
            throw JarvisModelError.unavailable("Model file appears to be empty (0 bytes).")
        }

        let currentPath = withLock { loadedModelPath }
        let currentSession = withLock { session }
        if currentPath == path, currentSession != nil {
            print("[JarvisRuntime] Model already loaded at path: \(path)")
            return
        }

        withLock {
            cancelRequested = false
        }

        let config = withLock { configuration }
        let parameters = deviceAwareParameters(using: config)
        print("[JarvisRuntime] Loading model with context=\(parameters.context), threads=\(parameters.numberOfThreads ?? 0)")

        let fileURL = URL(fileURLWithPath: path)
        let model = LLMSession.LocalModel.llama(url: fileURL, parameter: parameters)
        let newSession = LLMSession(model: model)

        do {
            try await newSession.prewarm()
        } catch {
            throw JarvisModelError.runtimeFailure("Failed to prewarm model: \(error.localizedDescription)")
        }

        withLock {
            session = newSession
            loadedModelPath = path
            cancelRequested = false
        }
        print("[JarvisRuntime] Model loaded successfully: \(path)")
    }

    public func unloadModel() async {
        withLock {
            session = nil
            loadedModelPath = nil
            cancelRequested = false
        }
    }

    public func generate(
        prompt: String,
        history: [JarvisChatMessage],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let session = withLock({ session }) else {
            throw JarvisModelError.unavailable("Model is not loaded. Warm the active model and try again.")
        }

        withLock {
            cancelRequested = false
        }

        let config = withLock { configuration }
        session.messages = mappedMessages(from: history, configuration: config)

        do {
            let stream = session.streamResponse(to: prompt)
            for try await chunk in stream {
                try Task.checkCancellation()
                if withLock({ cancelRequested }) {
                    throw JarvisModelError.cancelled
                }
                onToken(chunk)
            }

            if withLock({ cancelRequested }) {
                throw JarvisModelError.cancelled
            }
        } catch is CancellationError {
            throw JarvisModelError.cancelled
        } catch let modelError as JarvisModelError {
            throw modelError
        } catch {
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("memory") || errorMessage.contains("allocation") {
                throw JarvisModelError.runtimeFailure("Out of memory while generating. Try a smaller GGUF model.")
            }
            if errorMessage.contains("context") {
                throw JarvisModelError.runtimeFailure("Context length exceeded. Reduce conversation length or use a smaller context preset.")
            }
            throw JarvisModelError.runtimeFailure("Generation failed: \(error.localizedDescription)")
        }
    }

    public func cancelGeneration() {
        withLock {
            cancelRequested = true
        }
    }

    private func deviceAwareParameters(using configuration: JarvisRuntimeConfiguration) -> LlamaClient.Parameter {
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let physicalMemoryMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000

        let autoContext: Int
        if physicalMemoryMB >= 8000 {
            autoContext = 4096
        } else if physicalMemoryMB >= 6000 {
            autoContext = 2048
        } else {
            autoContext = 1024
        }

        var contextSize = configuration.contextWindow.explicitContextSize ?? autoContext
        if configuration.batterySaverMode {
            contextSize = min(contextSize, 1024)
        }

        let threadCount: Int
        switch configuration.performanceProfile {
        case .efficient:
            threadCount = max(1, processorCount / 2)
        case .balanced:
            threadCount = max(1, processorCount - 1)
        case .quality:
            threadCount = max(2, processorCount - 1)
        }

        let batchSize: Int
        switch configuration.performanceProfile {
        case .efficient:
            batchSize = min(128, contextSize / 8)
        case .balanced:
            batchSize = min(256, contextSize / 4)
        case .quality:
            batchSize = min(384, contextSize / 3)
        }

        return LlamaClient.Parameter(
            context: contextSize,
            numberOfThreads: threadCount,
            batch: max(64, batchSize),
            temperature: Float(configuration.temperature),
            topK: configuration.responseStyle == .detailed ? 50 : 40,
            topP: configuration.responseStyle == .detailed ? 0.94 : 0.9,
            penaltyLastN: 64,
            penaltyRepeat: 1.1
        )
    }

    private func mappedMessages(
        from history: [JarvisChatMessage],
        configuration: JarvisRuntimeConfiguration
    ) -> [LLMInput.Message] {
        var messages: [LLMInput.Message] = [
            .system("\(Self.baseSystemInstruction) \(configuration.responseStyle.systemInstructionSuffix)")
        ]

        for item in history {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            switch item.role {
            case .system:
                messages.append(.system(text))
            case .user:
                messages.append(.user(text))
            case .assistant:
                messages.append(.assistant(text))
            }
        }

        return messages
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
#endif

enum JarvisGGUFEngineFactory {
    static func makeDefault() -> JarvisGGUFEngine {
        #if targetEnvironment(simulator)
        print("[JarvisRuntime] Simulator detected - GGUF requires Metal/ANE which is not available in Simulator")
        print("[JarvisRuntime] Use a physical device to test actual model inference")
        return StubGGUFEngine()
        #else
        #if canImport(LocalLLMClientLlama)
        if #available(iOS 17.0, *) {
            print("[JarvisRuntime] Using LocalLLMClient GGUF engine (device)")
            return JarvisLocalLLMClientEngine()
        } else {
            print("[JarvisRuntime] iOS 17+ required on device, falling back to stub")
        }
        #else
        print("[JarvisRuntime] LocalLLMClient not available, falling back to stub")
        #endif
        #endif
        print("[JarvisRuntime] Falling back to StubGGUFEngine")
        return StubGGUFEngine()
    }

    static func availabilityDiagnostics() -> String {
        var reasons: [String] = []

        #if targetEnvironment(simulator)
        reasons.append("Running in iOS Simulator - Metal/ANE not available")
        reasons.append("GGUF models require a physical iOS device")
        #endif

        if #unavailable(iOS 17.0) {
            reasons.append("iOS 17.0+ required for LocalLLMClient")
        }

        #if !canImport(LocalLLMClientLlama)
        reasons.append("LocalLLMClient package not linked")
        #endif

        return reasons.isEmpty ? "Engine should be available on device" : reasons.joined(separator: "; ")
    }
}

@MainActor
public final class JarvisLocalModelRuntime: ObservableObject {
    @Published public private(set) var state: JarvisModelRuntimeState = .noModel
    @Published public private(set) var fileAccessState: JarvisModelFileAccessState = .noImportedFile

    private let engine: JarvisGGUFEngine
    private var configuration: JarvisRuntimeConfiguration
    private var selectedModel: JarvisRuntimeModelSelection?
    private var activeGenerationTask: Task<Void, Never>?
    private var didLoadModel = false
    private var loadedModelID: UUID?
    private var loadedResources: JarvisRuntimeResolvedModelResources?

    public init(
        engine: JarvisGGUFEngine? = nil,
        configuration: JarvisRuntimeConfiguration = JarvisRuntimeConfiguration()
    ) {
        self.engine = engine ?? JarvisGGUFEngineFactory.makeDefault()
        self.configuration = configuration
        self.engine.updateConfiguration(configuration)
    }

    public var engineName: String { engine.name }

    public var isInferenceAvailable: Bool {
        engine.isInstalled && engine.capability == .fullInference
    }

    public var supportsVisualInputs: Bool {
        guard let selectedModel else { return false }
        return engine.supportsVisualInputs &&
            selectedModel.capabilities.supportsVisionInputs &&
            selectedModel.projectorAttached
    }

    public var inferenceUnavailableReason: String {
        if !engine.isInstalled {
            return "Local GGUF engine is not installed."
        }
        if engine.capability != .fullInference {
            return "This environment cannot run local GGUF inference. Use a physical iPhone build."
        }
        return ""
    }

    public func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        engine.updateConfiguration(configuration)

        guard let model = selectedModel else {
            state = .noModel
            fileAccessState = .noImportedFile
            return
        }

        if didLoadModel || loadedResources != nil {
            teardownLoadedModel()
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = restingFileAccessState(for: model)
            return
        }

        state = .cold(modelName: model.displayName)
        fileAccessState = restingFileAccessState(for: model)
    }

    public func setSelectedModel(_ model: JarvisRuntimeModelSelection?) {
        let previousID = selectedModel?.id
        activeGenerationTask?.cancel()
        selectedModel = model
        print("[JarvisRuntime] setSelectedModel previous=\(previousID?.uuidString ?? "nil") next=\(model?.id.uuidString ?? "nil")")

        guard let model else {
            teardownLoadedModel()
            state = .noModel
            fileAccessState = .noImportedFile
            return
        }

        if previousID != model.id {
            teardownLoadedModel()
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = restingFileAccessState(for: model)
            return
        }

        state = idleState(for: model)
        fileAccessState = restingFileAccessState(for: model)
    }

    public func prepareIfNeeded() async throws {
        guard let model = selectedModel else {
            state = .noModel
            fileAccessState = .noImportedFile
            throw JarvisModelError.unavailable("No active model selected. Import and activate a GGUF model from Files.")
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = restingFileAccessState(for: model)
            throw JarvisModelError.runtimeFailure(inferenceUnavailableReason)
        }

        if didLoadModel, loadedModelID == model.id, loadedResources != nil {
            state = .ready(modelName: model.displayName)
            fileAccessState = accessGrantedState(for: model)
            return
        }

        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            let message = "Device thermal state is high. Let iPhone cool before running local inference."
            state = .paused(modelName: model.displayName, detail: message)
            fileAccessState = restingFileAccessState(for: model)
            throw JarvisModelError.runtimeFailure(message)
        }

        do {
            let resources: JarvisRuntimeResolvedModelResources
            if let loadedResources, loadedModelID == model.id {
                resources = loadedResources
                fileAccessState = accessGrantedState(for: model)
            } else {
                fileAccessState = .accessPending(
                    modelName: model.displayName,
                    detail: "Resolving persistent file access for \(model.displayName)."
                )
                resources = try model.acquireResources()
                loadedResources = resources
                loadedModelID = model.id
                fileAccessState = accessGrantedState(for: model)
            }

            state = .warming(modelName: model.displayName, progress: 0.15, detail: "Preparing runtime")
            try await Task.sleep(nanoseconds: 80_000_000)
            state = .warming(modelName: model.displayName, progress: 0.45, detail: "Opening model file")
            try await engine.loadModel(
                at: resources.modelURL.path,
                projectorPath: resources.projectorURL?.path
            )
            state = .warming(modelName: model.displayName, progress: 0.82, detail: "Finishing warm-up")
            try await Task.sleep(nanoseconds: 80_000_000)
            didLoadModel = true
            state = .ready(modelName: model.displayName)
            fileAccessState = accessGrantedState(for: model)
            print("[JarvisRuntime] model ready \(model.displayName)")
        } catch let accessError as JarvisModelFileAccessError {
            releaseLoadedResources()
            resetLoadedModelState()
            state = .failed(modelName: model.displayName, message: accessError.localizedDescription)
            fileAccessState = mapFileAccessError(accessError, modelName: model.displayName)
            print("[JarvisRuntime] file access failed for \(model.displayName): \(accessError.localizedDescription)")
            throw accessError
        } catch {
            await engine.unloadModel()
            releaseLoadedResources()
            resetLoadedModelState()
            let normalizedError = normalized(error, modelName: model.displayName)
            state = .failed(modelName: model.displayName, message: normalizedError.localizedDescription)
            fileAccessState = restingFileAccessState(for: model)
            print("[JarvisRuntime] failed to load model \(model.displayName): \(normalizedError.localizedDescription)")
            throw normalizedError
        }
    }

    public func streamResponse(prompt: String, history: [JarvisChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            activeGenerationTask?.cancel()
            activeGenerationTask = Task { [weak self] in
                guard let self else { return }

                do {
                    try await self.prepareIfNeeded()
                    let modelName = self.selectedModel?.displayName ?? "model"
                    self.state = .busy(modelName: modelName, detail: "Generating response")
                    try await self.engine.generate(prompt: prompt, history: history) { token in
                        continuation.yield(token)
                    }
                    self.state = .ready(modelName: modelName)
                    if let selectedModel = self.selectedModel {
                        self.fileAccessState = self.accessGrantedState(for: selectedModel)
                    }
                    continuation.finish()
                } catch {
                    if let modelError = error as? JarvisModelError, case .cancelled = modelError {
                        self.restoreIdleState()
                    } else if !self.isTerminalState(self.state) {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        self.state = .failed(modelName: self.selectedModel?.displayName, message: message)
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] termination in
                guard let self else { return }
                Task { @MainActor in
                    guard case .cancelled = termination else { return }
                    self.engine.cancelGeneration()
                    self.activeGenerationTask?.cancel()
                    self.restoreIdleState()
                }
            }
        }
    }

    public func cancel() {
        engine.cancelGeneration()
        activeGenerationTask?.cancel()
        restoreIdleState()
    }

    public func pauseForBackground() {
        cancel()
        state = .paused(modelName: selectedModel?.displayName, detail: "Runtime paused while Jarvis is backgrounded.")
        if let selectedModel, loadedResources != nil {
            fileAccessState = accessGrantedState(for: selectedModel)
        }
    }

    public func resumeFromForeground() {
        guard let model = selectedModel else {
            state = .noModel
            fileAccessState = .noImportedFile
            return
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = restingFileAccessState(for: model)
            return
        }

        state = idleState(for: model)
        if didLoadModel, loadedResources != nil {
            fileAccessState = accessGrantedState(for: model)
        } else {
            fileAccessState = restingFileAccessState(for: model)
        }
    }

    public func unload() async {
        print("[JarvisRuntime] unload requested")
        cancel()
        resetLoadedModelState()

        let resources = loadedResources
        loadedResources = nil
        await engine.unloadModel()
        resources?.release()

        if let model = selectedModel {
            state = .cold(modelName: model.displayName)
            fileAccessState = restingFileAccessState(for: model)
        } else {
            state = .noModel
            fileAccessState = .noImportedFile
        }
    }

    private func idleState(for model: JarvisRuntimeModelSelection) -> JarvisModelRuntimeState {
        if didLoadModel, loadedModelID == model.id {
            return .ready(modelName: model.displayName)
        }
        return .cold(modelName: model.displayName)
    }

    private func restoreIdleState() {
        guard let model = selectedModel else {
            state = .noModel
            fileAccessState = .noImportedFile
            return
        }

        state = idleState(for: model)
        if didLoadModel, loadedResources != nil {
            fileAccessState = accessGrantedState(for: model)
        } else {
            fileAccessState = restingFileAccessState(for: model)
        }
    }

    private func resetLoadedModelState() {
        didLoadModel = false
        loadedModelID = nil
    }

    private func releaseLoadedResources() {
        let resources = loadedResources
        loadedResources = nil
        resources?.release()
    }

    private func teardownLoadedModel() {
        let resources = loadedResources
        loadedResources = nil
        resetLoadedModelState()

        Task {
            await engine.unloadModel()
            resources?.release()
        }
    }

    private func normalized(_ error: Error, modelName: String) -> JarvisModelError {
        if let modelError = error as? JarvisModelError {
            return modelError
        }
        if let accessError = error as? JarvisModelFileAccessError {
            return .runtimeFailure(accessError.localizedDescription)
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return .runtimeFailure("Failed to load \(modelName).")
        }
        return .runtimeFailure(message)
    }

    private func isTerminalState(_ state: JarvisModelRuntimeState) -> Bool {
        switch state {
        case .failed, .runtimeUnavailable:
            return true
        case .noModel, .cold, .warming, .ready, .busy, .paused:
            return false
        }
    }

    private func restingFileAccessState(for model: JarvisRuntimeModelSelection) -> JarvisModelFileAccessState {
        if model.capabilities.supportsVisionInputs && model.capabilities.requiresProjectorForVision && !model.projectorAttached {
            return .accessPending(
                modelName: model.displayName,
                detail: "\(model.inactiveAccessDetail) Projector missing for future visual input."
            )
        }
        return .accessPending(modelName: model.displayName, detail: model.inactiveAccessDetail)
    }

    private func accessGrantedState(for model: JarvisRuntimeModelSelection) -> JarvisModelFileAccessState {
        if model.capabilities.supportsVisionInputs && model.projectorAttached {
            return .accessGranted(
                modelName: model.displayName,
                detail: engine.supportsVisualInputs
                    ? "Model and projector access granted."
                    : "Model and projector access granted. Current runtime is still text-only."
            )
        }
        return .accessGranted(modelName: model.displayName, detail: "Model file access granted.")
    }

    private func mapFileAccessError(_ error: JarvisModelFileAccessError, modelName: String) -> JarvisModelFileAccessState {
        switch error {
        case .missingBookmark, .bookmarkResolutionFailed:
            return .bookmarkResolutionFailed(modelName: modelName, reason: error.localizedDescription)
        case .accessDenied, .fileMissing, .invalidResolvedFile:
            return .accessLost(modelName: modelName, reason: error.localizedDescription)
        }
    }
}
