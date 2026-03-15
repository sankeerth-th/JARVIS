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

public enum JarvisRuntimeFailureKind: String, Equatable {
    case fileAccess
    case invalidModel
    case unsupportedModel
    case runtimeUnavailable
    case loadFailed
    case warmupFailed
    case inferenceFailed
}

public struct JarvisRuntimeFailure: Equatable {
    public var kind: JarvisRuntimeFailureKind
    public var message: String
    public var recoverySuggestion: String?

    public init(kind: JarvisRuntimeFailureKind, message: String, recoverySuggestion: String? = nil) {
        self.kind = kind
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

public struct JarvisRuntimeLoadDiagnostics: Equatable {
    public var modelName: String
    public var modelPath: String
    public var fileExists: Bool
    public var fileSizeBytes: Int64
    public var pathExtension: String
    public var usesSandboxCopy: Bool
    public var runningOnSimulator: Bool
    public var projectorPath: String?

    public init(
        modelName: String,
        modelPath: String,
        fileExists: Bool,
        fileSizeBytes: Int64,
        pathExtension: String,
        usesSandboxCopy: Bool,
        runningOnSimulator: Bool,
        projectorPath: String? = nil
    ) {
        self.modelName = modelName
        self.modelPath = modelPath
        self.fileExists = fileExists
        self.fileSizeBytes = fileSizeBytes
        self.pathExtension = pathExtension
        self.usesSandboxCopy = usesSandboxCopy
        self.runningOnSimulator = runningOnSimulator
        self.projectorPath = projectorPath
    }
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
    case failed(modelName: String?, failure: JarvisRuntimeFailure)

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
        request: JarvisAssistantRequest,
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
        request: JarvisAssistantRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        _ = request
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

    private struct LoadAttempt: Equatable {
        let context: Int
        let threads: Int
        let batch: Int

        var parameter: LlamaClient.Parameter {
            LlamaClient.Parameter(
                context: context,
                numberOfThreads: threads,
                batch: batch,
                temperature: 0.7,
                topK: 40,
                topP: 0.9,
                penaltyLastN: 64,
                penaltyRepeat: 1.1
            )
        }
    }

    private let lock = NSLock()
    private var session: LLMSession?
    private var loadedModelPath: String?
    private var loadedProjectorPath: String?
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
        let currentProjectorPath = withLock { loadedProjectorPath }
        let currentSession = withLock { session }
        if currentPath == path, currentProjectorPath == projectorPath, currentSession != nil {
            print("[JarvisRuntime] Model already loaded at path: \(path)")
            return
        }

        withLock {
            cancelRequested = false
        }

        let fileURL = URL(fileURLWithPath: path)
        let projectorURL = projectorPath.map { URL(fileURLWithPath: $0) }
        let config = withLock { configuration }
        let attempts = loadAttempts(using: config, fileSizeBytes: fileSize, filename: fileURL.lastPathComponent)

        var failureMessages: [String] = []
        for (index, attempt) in attempts.enumerated() {
            let parameter = parameter(for: attempt, configuration: config)
            print(
                "[JarvisRuntime] Load attempt \(index + 1)/\(attempts.count) " +
                "context=\(attempt.context) threads=\(attempt.threads) batch=\(attempt.batch)"
            )

            let model = LLMSession.LocalModel.llama(
                url: fileURL,
                mmprojURL: projectorURL,
                parameter: parameter
            )
            let newSession = LLMSession(model: model)

            do {
                try await newSession.prewarm()
                withLock {
                    session = newSession
                    loadedModelPath = path
                    loadedProjectorPath = projectorPath
                    cancelRequested = false
                }
                print("[JarvisRuntime] Model loaded successfully: \(path)")
                return
            } catch {
                let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedMessage = message.isEmpty ? "Unknown runtime error." : message
                failureMessages.append(
                    "Attempt \(index + 1): ctx \(attempt.context), threads \(attempt.threads), batch \(attempt.batch) -> \(normalizedMessage)"
                )
                print("[JarvisRuntime] Load attempt \(index + 1) failed: \(normalizedMessage)")
            }
        }

        let finalMessage = warmupFailureMessage(
            modelFilename: fileURL.lastPathComponent,
            projectorPath: projectorPath,
            attemptMessages: failureMessages
        )
        throw JarvisModelError.runtimeFailure(finalMessage)
    }

    public func unloadModel() async {
        withLock {
            session = nil
            loadedModelPath = nil
            loadedProjectorPath = nil
            cancelRequested = false
        }
    }

    public func generate(
        request: JarvisAssistantRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let session = withLock({ session }) else {
            throw JarvisModelError.unavailable("Model is not loaded. Warm the active model and try again.")
        }

        withLock {
            cancelRequested = false
        }

        let config = withLock { configuration }
        session.messages = mappedMessages(for: request, configuration: config)

        do {
            let stream = session.streamResponse(to: request.prompt)
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

    private func deviceAwareParameters(
        using configuration: JarvisRuntimeConfiguration,
        fileSizeBytes: Int64,
        filename: String
    ) -> LoadAttempt {
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let physicalMemoryMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000
        let thermalState = ProcessInfo.processInfo.thermalState
        let lowerFilename = filename.lowercased()
        let isGemma3Family = lowerFilename.contains("gemma") && lowerFilename.contains("3")
        let isLargeModel = fileSizeBytes >= 2_000_000_000

        let autoContext: Int
        if physicalMemoryMB >= 10_000 {
            autoContext = 1536
        } else if physicalMemoryMB >= 7_000 {
            autoContext = 1024
        } else {
            autoContext = 768
        }

        var contextSize = configuration.contextWindow.explicitContextSize ?? autoContext
        if isLargeModel {
            contextSize = min(contextSize, 1024)
        }
        if isGemma3Family {
            contextSize = min(contextSize, 768)
        }
        if configuration.batterySaverMode {
            contextSize = min(contextSize, 512)
        }
        if thermalState == .serious {
            contextSize = min(contextSize, 512)
        }
        contextSize = max(384, contextSize)

        let threadCount: Int
        switch configuration.performanceProfile {
        case .efficient:
            threadCount = 1
        case .balanced:
            threadCount = min(3, max(2, processorCount / 2))
        case .quality:
            threadCount = min(4, max(2, (processorCount / 2) + 1))
        }

        let batchSize: Int
        switch configuration.performanceProfile {
        case .efficient:
            batchSize = 8
        case .balanced:
            batchSize = 16
        case .quality:
            batchSize = 32
        }

        let effectiveThreadCount: Int
        let effectiveBatchSize: Int
        if thermalState == .serious {
            effectiveThreadCount = 1
            effectiveBatchSize = 4
        } else {
            effectiveThreadCount = max(1, threadCount)
            effectiveBatchSize = max(4, min(batchSize, max(4, contextSize / 8)))
        }

        return LoadAttempt(
            context: contextSize,
            threads: effectiveThreadCount,
            batch: effectiveBatchSize
        )
    }

    private func loadAttempts(
        using configuration: JarvisRuntimeConfiguration,
        fileSizeBytes: Int64,
        filename: String
    ) -> [LoadAttempt] {
        let base = deviceAwareParameters(
            using: configuration,
            fileSizeBytes: fileSizeBytes,
            filename: filename
        )

        let candidates = [
            base,
            LoadAttempt(
                context: min(base.context, 768),
                threads: min(base.threads, 3),
                batch: min(base.batch, 16)
            ),
            LoadAttempt(
                context: min(base.context, 512),
                threads: min(base.threads, 2),
                batch: min(base.batch, 8)
            ),
            LoadAttempt(context: 384, threads: 1, batch: 4)
        ]

        var uniqueAttempts: [LoadAttempt] = []
        for candidate in candidates {
            if !uniqueAttempts.contains(candidate) {
                uniqueAttempts.append(candidate)
            }
        }
        return uniqueAttempts
    }

    private func parameter(
        for attempt: LoadAttempt,
        configuration: JarvisRuntimeConfiguration
    ) -> LlamaClient.Parameter {
        var parameter = attempt.parameter
        parameter.temperature = Float(configuration.temperature)
        parameter.topK = configuration.responseStyle == .detailed ? 50 : 40
        parameter.topP = configuration.responseStyle == .detailed ? 0.94 : 0.9
        parameter.options = .init(verbose: false, disableAutoPause: false)
        return parameter
    }

    private func warmupFailureMessage(
        modelFilename: String,
        projectorPath: String?,
        attemptMessages: [String]
    ) -> String {
        let summary = attemptMessages.last ?? "The runtime could not open the model file."
        _ = modelFilename
        _ = projectorPath
        return "Failed to warm the model. \(summary) The import path is valid, but the local runtime could not open the GGUF with safe iPhone settings."
    }

    private func mappedMessages(
        for request: JarvisAssistantRequest,
        configuration: JarvisRuntimeConfiguration
    ) -> [LLMInput.Message] {
        var instructions = [Self.baseSystemInstruction, configuration.responseStyle.systemInstructionSuffix]
        instructions.append(taskInstruction(for: request.task, configuration: configuration))

        var messages: [LLMInput.Message] = [
            .system(instructions.joined(separator: " "))
        ]

        if let replyTargetText = request.replyTargetText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !replyTargetText.isEmpty {
            messages.append(.system("Draft reply target context:\n\(replyTargetText)"))
        }

        if !request.groundedResults.isEmpty {
            let grounding = request.groundedResults.prefix(request.task.groundingLimit).map { result in
                "\(result.item.title): \(result.snippet)"
            }.joined(separator: "\n")
            messages.append(.system("Local knowledge context:\n\(grounding)"))
        }

        for item in request.history {
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

    private func taskInstruction(
        for task: JarvisAssistantTask,
        configuration: JarvisRuntimeConfiguration
    ) -> String {
        switch task {
        case .chat:
            return "Handle the request as an ongoing assistant conversation."
        case .summarize:
            return "Summarize the provided content into useful, compact points before expanding."
        case .quickCapture:
            return "Treat this as a quick capture. Organize the thought, preserve intent, and keep the response concise."
        case .knowledgeAnswer:
            return "Use grounded local knowledge context when it is relevant and cite titles when useful."
        case .reply:
            return configuration.responseStyle == .detailed
                ? "Draft a polished reply that matches the supplied context and preserves important details."
                : "Draft a concise reply that matches the supplied context and tone."
        case .draftEmail:
            return "Draft a concise email reply using the supplied context and keep the structure professional."
        case .analyzeText:
            return "Analyze the supplied text and focus on key takeaways, risks, and next steps."
        case .visualDescribe:
            return "Be ready to describe user-provided visual context when that pipeline is added."
        case .prioritizeNotifications:
            return "Rank the supplied updates by urgency, impact, and required follow-up."
        }
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
    @Published public private(set) var lastFailure: JarvisRuntimeFailure?
    @Published public private(set) var lastLoadDiagnostics: JarvisRuntimeLoadDiagnostics?

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
            lastFailure = nil
            return
        }

        if didLoadModel || loadedResources != nil {
            teardownLoadedModel()
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = restingFileAccessState(for: model)
            lastFailure = runtimeFailure(
                kind: .runtimeUnavailable,
                message: inferenceUnavailableReason,
                suggestion: "Run the app on a physical iPhone to test local inference."
            )
            return
        }

        state = .cold(modelName: model.displayName)
        fileAccessState = restingFileAccessState(for: model)
        lastFailure = nil
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
            lastFailure = nil
            return
        }

        if previousID != model.id {
            teardownLoadedModel()
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = restingFileAccessState(for: model)
            lastFailure = runtimeFailure(
                kind: .runtimeUnavailable,
                message: inferenceUnavailableReason,
                suggestion: "Run the local model on a physical device."
            )
            return
        }

        state = idleState(for: model)
        fileAccessState = restingFileAccessState(for: model)
        lastFailure = nil
    }

    public func prepareIfNeeded() async throws {
        guard let model = selectedModel else {
            state = .noModel
            fileAccessState = .noImportedFile
            lastFailure = nil
            lastLoadDiagnostics = nil
            throw JarvisModelError.unavailable("No active model selected. Import and activate a GGUF model from Files.")
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = restingFileAccessState(for: model)
            lastFailure = runtimeFailure(
                kind: .runtimeUnavailable,
                message: inferenceUnavailableReason,
                suggestion: "Use a physical iPhone build to test local inference."
            )
            throw JarvisModelError.runtimeFailure(inferenceUnavailableReason)
        }

        if didLoadModel, loadedModelID == model.id, loadedResources != nil {
            state = .ready(modelName: model.displayName)
            fileAccessState = accessGrantedState(for: model)
            lastFailure = nil
            return
        }

        if ProcessInfo.processInfo.thermalState == .critical {
            let message = "Device thermal state is critical. Let iPhone cool before running local inference."
            state = .paused(modelName: model.displayName, detail: message)
            fileAccessState = restingFileAccessState(for: model)
            lastFailure = runtimeFailure(
                kind: .warmupFailed,
                message: message,
                suggestion: "Wait for the phone to cool, then retry warmup."
            )
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

            let diagnostics = makeLoadDiagnostics(
                modelName: model.displayName,
                modelURL: resources.modelURL,
                projectorURL: resources.projectorURL
            )
            lastLoadDiagnostics = diagnostics
            print(
                "[JarvisRuntime] final-load-path model=\(diagnostics.modelName) " +
                "path=\(diagnostics.modelPath) exists=\(diagnostics.fileExists) " +
                "size=\(diagnostics.fileSizeBytes) ext=\(diagnostics.pathExtension) " +
                "sandbox=\(diagnostics.usesSandboxCopy) simulator=\(diagnostics.runningOnSimulator)"
            )
            guard diagnostics.fileExists else {
                throw JarvisModelError.unavailable("Local copied model file is missing at \(diagnostics.modelPath)")
            }
            guard diagnostics.fileSizeBytes > 0 else {
                throw JarvisModelError.unavailable("Local copied model file is empty at \(diagnostics.modelPath)")
            }
            guard diagnostics.pathExtension == "gguf" else {
                throw JarvisModelError.runtimeFailure("Local copied model file has unsupported extension '.\(diagnostics.pathExtension)'.")
            }

            let thermalDetail = ProcessInfo.processInfo.thermalState == .serious
                ? "Preparing runtime in cool-down mode"
                : "Preparing runtime"
            state = .warming(modelName: model.displayName, progress: 0.15, detail: thermalDetail)
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
            lastFailure = nil
            print("[JarvisRuntime] model ready \(model.displayName)")
        } catch let accessError as JarvisModelFileAccessError {
            releaseLoadedResources()
            resetLoadedModelState()
            let failure = runtimeFailure(
                kind: .fileAccess,
                message: accessError.localizedDescription,
                suggestion: "Revalidate the model file or re-import it from Files."
            )
            state = .failed(modelName: model.displayName, failure: failure)
            fileAccessState = mapFileAccessError(accessError, modelName: model.displayName)
            lastFailure = failure
            print("[JarvisRuntime] file access failed for \(model.displayName): \(accessError.localizedDescription)")
            throw accessError
        } catch {
            await engine.unloadModel()
            releaseLoadedResources()
            resetLoadedModelState()
            let normalizedError = normalized(error, modelName: model.displayName)
            let failure = runtimeFailure(
                kind: .warmupFailed,
                message: normalizedError.localizedDescription,
                suggestion: "Retry warmup, unload the model, or try a smaller/recommended GGUF if the device is running out of memory."
            )
            state = .failed(modelName: model.displayName, failure: failure)
            fileAccessState = restingFileAccessState(for: model)
            lastFailure = failure
            print("[JarvisRuntime] failed to load model \(model.displayName): \(normalizedError.localizedDescription)")
            throw normalizedError
        }
    }

    public func streamResponse(request: JarvisAssistantRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            activeGenerationTask?.cancel()
            activeGenerationTask = Task { [weak self] in
                guard let self else { return }

                do {
                    try await self.prepareIfNeeded()
                    let modelName = self.selectedModel?.displayName ?? "model"
                    self.state = .busy(modelName: modelName, detail: "Generating response")
                    self.lastFailure = nil
                    try await self.engine.generate(request: request) { token in
                        continuation.yield(token)
                    }
                    self.state = .ready(modelName: modelName)
                    if let selectedModel = self.selectedModel {
                        self.fileAccessState = self.accessGrantedState(for: selectedModel)
                    }
                    self.lastFailure = nil
                    continuation.finish()
                } catch {
                    if let modelError = error as? JarvisModelError, case .cancelled = modelError {
                        self.restoreIdleState()
                    } else if !self.isTerminalState(self.state) {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        let failure = self.runtimeFailure(
                            kind: .inferenceFailed,
                            message: message,
                            suggestion: "Retry the request or unload and warm the model again."
                        )
                        self.state = .failed(modelName: self.selectedModel?.displayName, failure: failure)
                        self.lastFailure = failure
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
            lastFailure = nil
            return
        }

        guard isInferenceAvailable else {
            state = .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = restingFileAccessState(for: model)
            lastFailure = runtimeFailure(
                kind: .runtimeUnavailable,
                message: inferenceUnavailableReason,
                suggestion: "Run the local model on a physical iPhone."
            )
            return
        }

        state = idleState(for: model)
        if didLoadModel, loadedResources != nil {
            fileAccessState = accessGrantedState(for: model)
        } else {
            fileAccessState = restingFileAccessState(for: model)
        }
        if case .failed = state {
            lastFailure = nil
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
            lastFailure = nil
        } else {
            state = .noModel
            fileAccessState = .noImportedFile
            lastFailure = nil
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
            lastFailure = nil
            lastLoadDiagnostics = nil
            return
        }

        state = idleState(for: model)
        if didLoadModel, loadedResources != nil {
            fileAccessState = accessGrantedState(for: model)
        } else {
            fileAccessState = restingFileAccessState(for: model)
        }
        lastFailure = nil
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

    private func runtimeFailure(
        kind: JarvisRuntimeFailureKind,
        message: String,
        suggestion: String? = nil
    ) -> JarvisRuntimeFailure {
        JarvisRuntimeFailure(kind: kind, message: message, recoverySuggestion: suggestion)
    }

    private func makeLoadDiagnostics(
        modelName: String,
        modelURL: URL,
        projectorURL: URL?
    ) -> JarvisRuntimeLoadDiagnostics {
        let fileExists = FileManager.default.fileExists(atPath: modelURL.path)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: modelURL.path)[.size] as? Int64) ?? 0
        let normalizedPath = modelURL.standardizedFileURL.path
        let documentsRoot = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "")
        return JarvisRuntimeLoadDiagnostics(
            modelName: modelName,
            modelPath: normalizedPath,
            fileExists: fileExists,
            fileSizeBytes: fileSize,
            pathExtension: modelURL.pathExtension.lowercased(),
            usesSandboxCopy: normalizedPath.hasPrefix(documentsRoot),
            runningOnSimulator: {
                #if targetEnvironment(simulator)
                true
                #else
                false
                #endif
            }(),
            projectorPath: projectorURL?.standardizedFileURL.path
        )
    }
}
