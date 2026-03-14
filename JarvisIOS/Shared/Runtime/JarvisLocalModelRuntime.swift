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

public struct JarvisRuntimeModelSelection: Equatable {
    public var displayName: String
    public var path: String

    public init(displayName: String, path: String) {
        self.displayName = displayName
        self.path = path
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

    func updateConfiguration(_ configuration: JarvisRuntimeConfiguration)
    func loadModel(at path: String) async throws
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

    public func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        _ = configuration
    }

    public func loadModel(at path: String) async throws {
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

    public func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        withLock {
            self.configuration = configuration
        }
    }

    public func loadModel(at path: String) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw JarvisModelError.unavailable("Selected model file could not be found at path: \(path)")
        }

        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard pathExtension == "gguf" else {
            throw JarvisModelError.runtimeFailure("Unsupported model format '.\(pathExtension)'. Jarvis iPhone supports GGUF only.")
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

    private let engine: JarvisGGUFEngine
    private var configuration: JarvisRuntimeConfiguration
    private var selectedModel: JarvisRuntimeModelSelection?
    private var activeGenerationTask: Task<Void, Never>?
    private var didLoadModel = false
    private var loadedModelPath: String?

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

    public var inferenceUnavailableReason: String {
        if !engine.isInstalled {
            return "Local GGUF engine is not installed."
        }
        if engine.capability != .fullInference {
            return "This build has no real GGUF inference adapter wired yet."
        }
        return ""
    }

    public func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        engine.updateConfiguration(configuration)

        guard let model = selectedModel else {
            state = .noModel
            return
        }

        if didLoadModel {
            resetLoadedModelState()
            unloadEngine()
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            return
        }

        state = .cold(modelName: model.displayName)
    }

    public func setSelectedModel(_ model: JarvisRuntimeModelSelection?) {
        let previousPath = selectedModel?.path
        activeGenerationTask?.cancel()
        selectedModel = model
        print("[JarvisRuntime] setSelectedModel previous=\(previousPath ?? "nil") next=\(model?.path ?? "nil")")

        guard let model else {
            resetLoadedModelState()
            unloadEngine()
            state = .noModel
            return
        }

        guard FileManager.default.fileExists(atPath: model.path) else {
            resetLoadedModelState()
            unloadEngine()
            state = .failed(modelName: model.displayName, message: "Selected model file is missing. Re-import \(model.displayName).")
            return
        }

        if let loadedModelPath, loadedModelPath != model.path {
            resetLoadedModelState()
            unloadEngine()
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            return
        }

        state = idleState(for: model)
    }

    public func prepareIfNeeded() async throws {
        guard let model = selectedModel else {
            state = .noModel
            throw JarvisModelError.unavailable("No active model selected. Import a GGUF model from Files.")
        }

        guard FileManager.default.fileExists(atPath: model.path) else {
            state = .failed(modelName: model.displayName, message: "Selected model file is missing. Re-import \(model.displayName).")
            throw JarvisModelError.unavailable("The active model file no longer exists.")
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            throw JarvisModelError.runtimeFailure(inferenceUnavailableReason)
        }

        if didLoadModel, loadedModelPath == model.path {
            state = .ready(modelName: model.displayName)
            return
        }

        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            let message = "Device thermal state is high. Let iPhone cool before running local inference."
            state = .paused(modelName: model.displayName, detail: message)
            throw JarvisModelError.runtimeFailure(message)
        }

        print("[JarvisRuntime] prepareIfNeeded model=\(model.displayName) path=\(model.path)")

        do {
            if let loadedModelPath, loadedModelPath != model.path {
                print("[JarvisRuntime] unloading previous model before reload")
                await engine.unloadModel()
                resetLoadedModelState()
            }

            state = .warming(modelName: model.displayName, progress: 0.15, detail: "Preparing runtime")
            try await Task.sleep(nanoseconds: 80_000_000)
            state = .warming(modelName: model.displayName, progress: 0.45, detail: "Loading \(model.displayName)")
            try await engine.loadModel(at: model.path)
            state = .warming(modelName: model.displayName, progress: 0.82, detail: "Finishing warm-up")
            try await Task.sleep(nanoseconds: 80_000_000)
            didLoadModel = true
            loadedModelPath = model.path
            state = .ready(modelName: model.displayName)
            print("[JarvisRuntime] model ready \(model.displayName)")
        } catch {
            await engine.unloadModel()
            resetLoadedModelState()
            let normalizedError = normalized(error, modelName: model.displayName)
            state = .failed(modelName: model.displayName, message: normalizedError.localizedDescription)
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
    }

    public func resumeFromForeground() {
        guard let model = selectedModel else {
            state = .noModel
            return
        }

        guard FileManager.default.fileExists(atPath: model.path) else {
            state = .failed(modelName: model.displayName, message: "Selected model file is missing. Re-import \(model.displayName).")
            return
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            return
        }

        state = idleState(for: model)
    }

    public func unload() async {
        print("[JarvisRuntime] unload requested")
        cancel()
        resetLoadedModelState()
        await engine.unloadModel()
        if let model = selectedModel {
            state = .cold(modelName: model.displayName)
        } else {
            state = .noModel
        }
    }

    private func idleState(for model: JarvisRuntimeModelSelection) -> JarvisModelRuntimeState {
        if didLoadModel, loadedModelPath == model.path {
            return .ready(modelName: model.displayName)
        }
        return .cold(modelName: model.displayName)
    }

    private func restoreIdleState() {
        guard let model = selectedModel else {
            state = .noModel
            return
        }
        state = idleState(for: model)
    }

    private func resetLoadedModelState() {
        didLoadModel = false
        loadedModelPath = nil
    }

    private func unloadEngine() {
        Task {
            await engine.unloadModel()
        }
    }

    private func isTerminalState(_ state: JarvisModelRuntimeState) -> Bool {
        switch state {
        case .noModel, .runtimeUnavailable, .failed, .paused:
            return true
        case .cold, .warming, .ready, .busy:
            return false
        }
    }

    private func normalized(_ error: Error, modelName: String) -> JarvisModelError {
        if let modelError = error as? JarvisModelError {
            return modelError
        }

        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("memory") || lowered.contains("allocation") {
            return .runtimeFailure("Out of memory while preparing \(modelName). Try a smaller GGUF model.")
        }

        return .runtimeFailure("Failed to prepare \(modelName): \(error.localizedDescription)")
    }
}
