import Foundation
import Combine
import os

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
    public var availableMemoryBytesAtLoad: UInt64?
    public var prefersMemoryMapping: Bool
    public var effectiveMemoryMappingKnown: Bool
    public var memoryMappingNote: String
    public var requestedGPUOffload: Bool
    public var requestedGPULayerCount: Int
    public var flashAttentionRequested: Bool

    public init(
        modelName: String,
        modelPath: String,
        fileExists: Bool,
        fileSizeBytes: Int64,
        pathExtension: String,
        usesSandboxCopy: Bool,
        runningOnSimulator: Bool,
        projectorPath: String? = nil,
        availableMemoryBytesAtLoad: UInt64? = nil,
        prefersMemoryMapping: Bool = true,
        effectiveMemoryMappingKnown: Bool = false,
        memoryMappingNote: String = "Runtime prefers mmap, but the current LocalLLMClient API does not surface whether fallback heap loading occurred.",
        requestedGPUOffload: Bool = false,
        requestedGPULayerCount: Int = 0,
        flashAttentionRequested: Bool = false
    ) {
        self.modelName = modelName
        self.modelPath = modelPath
        self.fileExists = fileExists
        self.fileSizeBytes = fileSizeBytes
        self.pathExtension = pathExtension
        self.usesSandboxCopy = usesSandboxCopy
        self.runningOnSimulator = runningOnSimulator
        self.projectorPath = projectorPath
        self.availableMemoryBytesAtLoad = availableMemoryBytesAtLoad
        self.prefersMemoryMapping = prefersMemoryMapping
        self.effectiveMemoryMappingKnown = effectiveMemoryMappingKnown
        self.memoryMappingNote = memoryMappingNote
        self.requestedGPUOffload = requestedGPUOffload
        self.requestedGPULayerCount = requestedGPULayerCount
        self.flashAttentionRequested = flashAttentionRequested
    }
}

public enum JarvisRuntimeDeviceTier: String, Equatable, Codable {
    case constrained
    case baseline
    case highMemory

    static func current(physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> JarvisRuntimeDeviceTier {
        if physicalMemoryBytes >= 12_000_000_000 {
            return .highMemory
        }
        if physicalMemoryBytes >= 8_000_000_000 {
            return .baseline
        }
        return .constrained
    }

    var diagnosticsName: String {
        switch self {
        case .constrained:
            return "constrained"
        case .baseline:
            return "baseline"
        case .highMemory:
            return "high_memory"
        }
    }
}

public enum JarvisRuntimeMemoryPressureLevel: String, Equatable, Codable {
    case normal
    case reduced
    case critical

    static func current(availableMemoryBytes: UInt64?) -> JarvisRuntimeMemoryPressureLevel {
        guard let availableMemoryBytes, availableMemoryBytes > 0 else {
            return .normal
        }
        switch availableMemoryBytes {
        case ..<900_000_000:
            return .critical
        case ..<1_400_000_000:
            return .reduced
        default:
            return .normal
        }
    }
}

public enum JarvisRuntimeGenerationStopReason: String, Equatable, Codable {
    case eos = "eos"
    case stopSequence = "stop_sequence"
    case maxTokens = "max_tokens"
    case repetitionAbort = "repetition_abort"
    case memoryAbort = "memory_abort"
    case thermalAbort = "thermal_abort"
    case externalCancel = "external_cancel"
    case validationFailure = "validation_failure"
    case unknown = "unknown"
}

public struct JarvisRuntimeGenerationOutcome: Equatable {
    public var stopReason: JarvisRuntimeGenerationStopReason
    public var requestedContextTokenLimit: Int
    public var effectiveContextTokenLimit: Int
    public var effectiveOutputTokenLimit: Int
    public var promptTokenEstimate: Int
    public var availableMemoryBytesAtStart: UInt64?
    public var memoryFallbackTriggered: Bool
    public var thermalFallbackTriggered: Bool
    public var speculativeDecodingRequested: Bool
    public var speculativeDecodingEligible: Bool
    public var gpuOffloadEnabled: Bool
    public var requestedGPULayerCount: Int
    public var flashAttentionEnabled: Bool
    public var estimatedKVCacheBytes: UInt64

    public init(
        stopReason: JarvisRuntimeGenerationStopReason = .eos,
        requestedContextTokenLimit: Int,
        effectiveContextTokenLimit: Int,
        effectiveOutputTokenLimit: Int,
        promptTokenEstimate: Int,
        availableMemoryBytesAtStart: UInt64? = nil,
        memoryFallbackTriggered: Bool = false,
        thermalFallbackTriggered: Bool = false,
        speculativeDecodingRequested: Bool = false,
        speculativeDecodingEligible: Bool = false,
        gpuOffloadEnabled: Bool = false,
        requestedGPULayerCount: Int = 0,
        flashAttentionEnabled: Bool = false,
        estimatedKVCacheBytes: UInt64 = 0
    ) {
        self.stopReason = stopReason
        self.requestedContextTokenLimit = requestedContextTokenLimit
        self.effectiveContextTokenLimit = effectiveContextTokenLimit
        self.effectiveOutputTokenLimit = effectiveOutputTokenLimit
        self.promptTokenEstimate = promptTokenEstimate
        self.availableMemoryBytesAtStart = availableMemoryBytesAtStart
        self.memoryFallbackTriggered = memoryFallbackTriggered
        self.thermalFallbackTriggered = thermalFallbackTriggered
        self.speculativeDecodingRequested = speculativeDecodingRequested
        self.speculativeDecodingEligible = speculativeDecodingEligible
        self.gpuOffloadEnabled = gpuOffloadEnabled
        self.requestedGPULayerCount = requestedGPULayerCount
        self.flashAttentionEnabled = flashAttentionEnabled
        self.estimatedKVCacheBytes = estimatedKVCacheBytes
    }
}

public struct JarvisRuntimeGenerationDiagnostics: Equatable {
    public var preset: String
    public var taskCategory: String
    public var deviceTier: JarvisRuntimeDeviceTier
    public var promptCharacterCount: Int
    public var historyMessageCount: Int
    public var groundedResultCount: Int
    public var outputCharacterCount: Int
    public var estimatedOutputTokens: Int
    public var totalEstimatedTokens: Int
    public var promptTokenEstimate: Int
    public var tokensPerSecond: Double
    public var timeToFirstTokenSeconds: Double?
    public var generationDurationSeconds: Double
    public var thermalState: ProcessInfo.ThermalState
    public var usedMemorySafeFallback: Bool
    public var memoryFallbackTriggered: Bool
    public var thermalFallbackTriggered: Bool
    public var stopReason: JarvisRuntimeGenerationStopReason
    public var availableMemoryBytesAtStart: UInt64?
    public var effectiveContextTokenLimit: Int
    public var effectiveOutputTokenLimit: Int
    public var gpuOffloadEnabled: Bool
    public var requestedGPULayerCount: Int
    public var flashAttentionEnabled: Bool
    public var estimatedKVCacheBytes: UInt64

    public init(
        preset: String,
        taskCategory: String,
        deviceTier: JarvisRuntimeDeviceTier,
        promptCharacterCount: Int,
        historyMessageCount: Int,
        groundedResultCount: Int,
        outputCharacterCount: Int,
        estimatedOutputTokens: Int,
        totalEstimatedTokens: Int,
        promptTokenEstimate: Int,
        tokensPerSecond: Double,
        timeToFirstTokenSeconds: Double?,
        generationDurationSeconds: Double,
        thermalState: ProcessInfo.ThermalState,
        usedMemorySafeFallback: Bool,
        memoryFallbackTriggered: Bool,
        thermalFallbackTriggered: Bool,
        stopReason: JarvisRuntimeGenerationStopReason,
        availableMemoryBytesAtStart: UInt64?,
        effectiveContextTokenLimit: Int,
        effectiveOutputTokenLimit: Int,
        gpuOffloadEnabled: Bool = false,
        requestedGPULayerCount: Int = 0,
        flashAttentionEnabled: Bool = false,
        estimatedKVCacheBytes: UInt64 = 0
    ) {
        self.preset = preset
        self.taskCategory = taskCategory
        self.deviceTier = deviceTier
        self.promptCharacterCount = promptCharacterCount
        self.historyMessageCount = historyMessageCount
        self.groundedResultCount = groundedResultCount
        self.outputCharacterCount = outputCharacterCount
        self.estimatedOutputTokens = estimatedOutputTokens
        self.totalEstimatedTokens = totalEstimatedTokens
        self.promptTokenEstimate = promptTokenEstimate
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        self.generationDurationSeconds = generationDurationSeconds
        self.thermalState = thermalState
        self.usedMemorySafeFallback = usedMemorySafeFallback
        self.memoryFallbackTriggered = memoryFallbackTriggered
        self.thermalFallbackTriggered = thermalFallbackTriggered
        self.stopReason = stopReason
        self.availableMemoryBytesAtStart = availableMemoryBytesAtStart
        self.effectiveContextTokenLimit = effectiveContextTokenLimit
        self.effectiveOutputTokenLimit = effectiveOutputTokenLimit
        self.gpuOffloadEnabled = gpuOffloadEnabled
        self.requestedGPULayerCount = requestedGPULayerCount
        self.flashAttentionEnabled = flashAttentionEnabled
        self.estimatedKVCacheBytes = estimatedKVCacheBytes
    }
}

enum JarvisRuntimeHeuristics {
    static func availableMemoryBytes() -> UInt64? {
        let bytes = os_proc_available_memory()
        return bytes > 0 ? UInt64(bytes) : nil
    }

    static func approximateTokenCount(for text: String) -> Int {
        max(1, Int((Double(text.utf8.count) / 4.0).rounded(.up)))
    }

    static func maxContextTokens(fileSizeBytes: Int64, kvBudgetMB: Int) -> Int {
        return max(384, Int(Double(kvBudgetMB) / kvMegabytesPerToken(fileSizeBytes: fileSizeBytes)))
    }

    static func kvMegabytesPerToken(fileSizeBytes: Int64) -> Double {
        switch fileSizeBytes {
        case 3_200_000_000...:
            return 1.0
        case 2_300_000_000...:
            return 0.75
        case 1_500_000_000...:
            return 0.5
        default:
            return 0.35
        }
    }

    static func estimatedKVCacheBytes(contextTokens: Int, fileSizeBytes: Int64) -> UInt64 {
        guard contextTokens > 0 else { return 0 }
        let megabytes = Double(contextTokens) * kvMegabytesPerToken(fileSizeBytes: fileSizeBytes)
        return UInt64((megabytes * 1_000_000).rounded())
    }

    static func gpuLayerTarget(
        for deviceTier: JarvisRuntimeDeviceTier,
        performanceProfile: JarvisRuntimePerformanceProfile,
        memoryPressure: JarvisRuntimeMemoryPressureLevel,
        batterySaverMode: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> Int {
        guard thermalState != .critical else { return 0 }

        let base: Int
        switch deviceTier {
        case .constrained:
            base = batterySaverMode ? 8 : 12
        case .baseline:
            switch performanceProfile {
            case .efficient:
                base = 32
            case .balanced:
                base = 40
            case .quality:
                base = 48
            }
        case .highMemory:
            base = 99
        }

        if batterySaverMode {
            return min(base, 32)
        }
        if memoryPressure == .reduced {
            switch deviceTier {
            case .constrained:
                return min(base, 8)
            case .baseline:
                return min(base, 24)
            case .highMemory:
                return min(base, 48)
            }
        }
        if thermalState == .serious {
            switch deviceTier {
            case .constrained:
                return min(base, 8)
            case .baseline:
                return min(base, 24)
            case .highMemory:
                return min(base, 40)
            }
        }

        return base
    }

    static func microBatchSize(
        for batchSize: Int,
        deviceTier: JarvisRuntimeDeviceTier,
        memoryPressure: JarvisRuntimeMemoryPressureLevel,
        thermalState: ProcessInfo.ThermalState
    ) -> Int {
        if thermalState == .serious || memoryPressure == .reduced {
            return max(4, min(batchSize, 8))
        }

        let target: Int
        switch deviceTier {
        case .constrained:
            target = 4
        case .baseline:
            target = 8
        case .highMemory:
            target = 12
        }
        return max(4, min(batchSize, target))
    }

    static func batchThreadCount(
        generationThreads: Int,
        deviceTier: JarvisRuntimeDeviceTier,
        thermalState: ProcessInfo.ThermalState
    ) -> Int {
        if thermalState == .serious {
            return 1
        }
        switch deviceTier {
        case .constrained:
            return max(1, min(generationThreads, 1))
        case .baseline:
            return max(1, min(generationThreads, 2))
        case .highMemory:
            return max(1, min(generationThreads + 1, 4))
        }
    }

    static func shouldEnableFlashAttention(
        for deviceTier: JarvisRuntimeDeviceTier,
        performanceProfile: JarvisRuntimePerformanceProfile,
        memoryPressure: JarvisRuntimeMemoryPressureLevel,
        batterySaverMode: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> Bool {
        guard deviceTier == .highMemory else { return false }
        guard performanceProfile != .efficient else { return false }
        guard memoryPressure == .normal else { return false }
        guard !batterySaverMode else { return false }
        return thermalState != .serious && thermalState != .critical
    }

    static func repeatedSuffixDetected(
        in text: String,
        windowCharacters: Int,
        threshold: Int
    ) -> Bool {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(normalized)
        let maxUnit = min(windowCharacters, max(24, characters.count / max(1, threshold)))
        guard maxUnit >= 24 else { return false }

        for unitLength in stride(from: maxUnit, through: 24, by: -8) {
            guard characters.count >= unitLength * threshold else { continue }
            let repeatedUnit = Array(characters.suffix(unitLength))
            var matches = 1
            var offset = unitLength * 2

            while offset <= characters.count, matches < threshold {
                let start = characters.count - offset
                let end = start + unitLength
                guard start >= 0 else { break }
                if Array(characters[start..<end]) == repeatedUnit {
                    matches += 1
                    offset += unitLength
                } else {
                    break
                }
            }

            if matches >= threshold {
                return true
            }
        }

        return false
    }

    static func repeatedPhraseDetected(
        in text: String,
        maxPhraseWords: Int = 12,
        threshold: Int
    ) -> Bool {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = normalized.split(separator: " ").map(String.init)
        guard words.count >= threshold * 3 else { return false }

        for phraseWordCount in stride(from: min(maxPhraseWords, words.count / max(1, threshold)), through: 3, by: -1) {
            guard words.count >= phraseWordCount * threshold else { continue }
            let repeatedPhrase = Array(words.suffix(phraseWordCount))
            var matches = 1
            var offset = phraseWordCount * 2

            while offset <= words.count, matches < threshold {
                let start = words.count - offset
                let end = start + phraseWordCount
                guard start >= 0 else { break }
                if Array(words[start..<end]) == repeatedPhrase {
                    matches += 1
                    offset += phraseWordCount
                } else {
                    break
                }
            }

            if matches >= threshold {
                return true
            }
        }

        return false
    }

    static func isGreetingLikePrompt(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        let greetings = ["hi", "hello", "hey", "yo", "good morning", "good afternoon", "good evening"]
        let wordCount = normalized.split(whereSeparator: \.isWhitespace).count
        return wordCount <= 6 && greetings.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") })
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
    func updateGenerationTuning(_ tuning: JarvisGenerationTuning?)
    func loadModel(at path: String, projectorPath: String?) async throws
    func unloadModel() async
    func generate(
        request: JarvisAssistantRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> JarvisRuntimeGenerationOutcome
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

    public func updateGenerationTuning(_ tuning: JarvisGenerationTuning?) {
        _ = tuning
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
    ) async throws -> JarvisRuntimeGenerationOutcome {
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
        "You are Jarvis, a sharp, reliable, on-device iPhone assistant. " +
        "Lead with the answer, stay concrete, and be useful immediately. " +
        "Do not repeat the user's message back as filler. " +
        "Do not mention the local runtime, model, or device limits unless the user asks or it directly blocks the task. " +
        "If a request is ambiguous, make one reasonable assumption and say so briefly. " +
        "Prefer clean structure, practical next steps, and strong writing."

    private struct RuntimePolicy: Equatable {
        let deviceTier: JarvisRuntimeDeviceTier
        let memoryPressure: JarvisRuntimeMemoryPressureLevel
        let contextSize: Int
        let threadCount: Int
        let batchThreadCount: Int
        let batchSize: Int
        let microBatchSize: Int
        let kvBudgetMB: Int
        let estimatedKVCacheBytes: UInt64
        let maxOutputTokens: Int
        let softStopDurationSeconds: Double
        let gpuLayerCount: Int
        let gpuOffloadEnabled: Bool
        let flashAttentionEnabled: Bool
        let availableMemoryBytes: UInt64?
        let memoryFallbackTriggered: Bool
        let thermalFallbackTriggered: Bool
        let speculativeDecodingRequested: Bool
        let speculativeDecodingEligible: Bool
    }

    private static let hiddenPlanningInstruction =
        "Think step-by-step internally before answering. Do not expose reasoning. Return only the final answer."

    private struct GenerationGuard {
        let maxOutputTokens: Int
        let softStopDurationSeconds: Double
        let repetitionWindowCharacters: Int
        let repetitionThreshold: Int
        let availableMemoryBytesProvider: () -> UInt64?

        private(set) var estimatedOutputTokens = 0
        private(set) var outputCharacterCount = 0
        private var normalizedTail = ""
        private let startedAt = CFAbsoluteTimeGetCurrent()

        init(
            maxOutputTokens: Int,
            softStopDurationSeconds: Double,
            repetitionWindowCharacters: Int,
            repetitionThreshold: Int,
            availableMemoryBytesProvider: @escaping () -> UInt64?
        ) {
            self.maxOutputTokens = maxOutputTokens
            self.softStopDurationSeconds = softStopDurationSeconds
            self.repetitionWindowCharacters = repetitionWindowCharacters
            self.repetitionThreshold = repetitionThreshold
            self.availableMemoryBytesProvider = availableMemoryBytesProvider
        }

        mutating func ingest(_ chunk: String) throws {
            let normalized = Self.normalize(chunk)
            guard !normalized.isEmpty else { return }

            outputCharacterCount += chunk.count
            estimatedOutputTokens += max(1, Int((Double(normalized.utf8.count) / 3.6).rounded(.up)))
            normalizedTail.append(normalized)
            if normalizedTail.count > repetitionWindowCharacters * repetitionThreshold {
                normalizedTail.removeFirst(normalizedTail.count - (repetitionWindowCharacters * repetitionThreshold))
            }

            if estimatedOutputTokens > maxOutputTokens {
                throw GuardStop.outputCap
            }

            if CFAbsoluteTimeGetCurrent() - startedAt > softStopDurationSeconds && estimatedOutputTokens > (maxOutputTokens / 2) {
                throw GuardStop.thermalGuard
            }

            if JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: availableMemoryBytesProvider()) == .critical {
                throw GuardStop.memoryGuard
            }

            if JarvisRuntimeHeuristics.repeatedSuffixDetected(
                in: normalizedTail,
                windowCharacters: repetitionWindowCharacters,
                threshold: repetitionThreshold
            ) || JarvisRuntimeHeuristics.repeatedPhraseDetected(
                in: normalizedTail,
                threshold: repetitionThreshold
            ) {
                throw GuardStop.repetitionGuard
            }
        }

        private static func normalize(_ text: String) -> String {
            text.lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private enum GuardStop: Error {
        case outputCap
        case repetitionGuard
        case thermalGuard
        case memoryGuard
    }

    private struct LoadAttempt: Equatable {
        let context: Int
        let threads: Int
        let batchThreads: Int
        let batch: Int
        let microBatch: Int
        let gpuLayerCount: Int
        let preferGPU: Bool
        let offloadKQV: Bool
        let offloadOperations: Bool
        let flashAttentionEnabled: Bool
    }

    private struct LoadedSessionProfile: Equatable {
        let context: Int
        let threads: Int
        let batchThreads: Int
        let batch: Int
        let microBatch: Int
        let gpuLayerCount: Int
        let gpuOffloadEnabled: Bool
        let flashAttentionEnabled: Bool
        let estimatedKVCacheBytes: UInt64
    }

    private let lock = NSLock()
    private var session: LLMSession?
    private var loadedModelPath: String?
    private var loadedProjectorPath: String?
    private var cancelRequested = false
    private var configuration = JarvisRuntimeConfiguration()
    private var requestTuning: JarvisGenerationTuning?
    private var loadedContextLimit: Int?
    private var loadedSessionProfile: LoadedSessionProfile?

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

    public func updateGenerationTuning(_ tuning: JarvisGenerationTuning?) {
        withLock {
            requestTuning = tuning
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

        let availableMemoryBytes = JarvisRuntimeHeuristics.availableMemoryBytes()
        if JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: availableMemoryBytes) == .critical {
            throw JarvisModelError.runtimeFailure(
                "Available memory is too low to warm the model safely. Unload the current model or retry after closing other apps."
            )
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
        let attempts = loadAttempts(
            using: config,
            fileSizeBytes: fileSize,
            filename: fileURL.lastPathComponent,
            availableMemoryBytes: availableMemoryBytes
        )

        var failureMessages: [String] = []
        for (index, attempt) in attempts.enumerated() {
            let parameter = parameter(for: attempt, configuration: config, tuning: withLock { requestTuning })
            print(
                "[JarvisRuntime] Load attempt \(index + 1)/\(attempts.count) " +
                "context=\(attempt.context) threads=\(attempt.threads) batch=\(attempt.batch) " +
                "ubatch=\(attempt.microBatch) gpu_layers=\(attempt.gpuLayerCount) flash=\(attempt.flashAttentionEnabled)"
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
                    loadedContextLimit = attempt.context
                    loadedSessionProfile = LoadedSessionProfile(
                        context: attempt.context,
                        threads: attempt.threads,
                        batchThreads: attempt.batchThreads,
                        batch: attempt.batch,
                        microBatch: attempt.microBatch,
                        gpuLayerCount: attempt.gpuLayerCount,
                        gpuOffloadEnabled: attempt.preferGPU && attempt.gpuLayerCount > 0,
                        flashAttentionEnabled: attempt.flashAttentionEnabled,
                        estimatedKVCacheBytes: JarvisRuntimeHeuristics.estimatedKVCacheBytes(
                            contextTokens: attempt.context,
                            fileSizeBytes: fileSize
                        )
                    )
                    cancelRequested = false
                }
                print("[JarvisRuntime] Model loaded successfully: \(path)")
                return
            } catch {
                let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedMessage = message.isEmpty ? "Unknown runtime error." : message
                failureMessages.append(
                    "Attempt \(index + 1): ctx \(attempt.context), threads \(attempt.threads), batch \(attempt.batch), ubatch \(attempt.microBatch), gpu \(attempt.gpuLayerCount) -> \(normalizedMessage)"
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
            loadedContextLimit = nil
            loadedSessionProfile = nil
            cancelRequested = false
        }
    }

    public func generate(
        request: JarvisAssistantRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> JarvisRuntimeGenerationOutcome {
        guard let session = withLock({ session }) else {
            throw JarvisModelError.unavailable("Model is not loaded. Warm the active model and try again.")
        }

        withLock {
            cancelRequested = false
        }

        let config = withLock { configuration }
        let modelPath = withLock { loadedModelPath } ?? ""
        let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? Int64) ?? 0
        let availableMemoryBytesAtStart = JarvisRuntimeHeuristics.availableMemoryBytes()
        let memoryPressure = JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: availableMemoryBytesAtStart)
        if config.memorySafetyGuardsEnabled && memoryPressure == .critical {
            throw JarvisModelError.runtimeFailure(
                "Available memory is too low to generate safely. Unload the model or retry after freeing memory."
            )
        }
        if config.thermalProtectionEnabled && ProcessInfo.processInfo.thermalState == .critical {
            throw JarvisModelError.runtimeFailure(
                "Device thermal state is critical. Let the phone cool before generating again."
            )
        }
        let policy = runtimePolicy(
            using: config,
            fileSizeBytes: fileSizeBytes,
            filename: URL(fileURLWithPath: modelPath).lastPathComponent,
            tuning: request.tuning,
            prompt: request.prompt,
            availableMemoryBytes: availableMemoryBytesAtStart
        )
        let mappedPromptMessages = mappedMessages(for: request, configuration: config)
        session.messages = mappedPromptMessages
        let blueprint = request.promptBlueprint
        let blueprintCharacters =
            blueprint.systemInstruction.count +
            blueprint.assistantRole.count +
            blueprint.taskTypeInstruction.count +
            blueprint.responseInstruction.count
        let contextBlockCharacters = blueprint.contextBlocks.reduce(0) { partialResult, block in
            partialResult + block.title.count + block.content.count
        }
        let historyCharacters = request.history.reduce(0) { partialResult, message in
            partialResult + message.text.count
        }
        let groundingCharacters = request.groundedResults.reduce(0) { partialResult, result in
            partialResult + result.item.title.count + result.snippet.count
        }
        let replyCharacters = request.replyTargetText?.count ?? 0
        let promptCharacterEstimate =
            request.prompt.count +
            blueprintCharacters +
            contextBlockCharacters +
            historyCharacters +
            groundingCharacters +
            replyCharacters
        let promptTokenEstimate = max(1, Int((Double(promptCharacterEstimate) / 4.0).rounded(.up)))
        let requestedContextLimit = request.tuning.maxContextTokens > 0
            ? request.tuning.maxContextTokens
            : (config.contextWindow.explicitContextSize ?? policy.contextSize)
        var guardrail = GenerationGuard(
            maxOutputTokens: policy.maxOutputTokens,
            softStopDurationSeconds: policy.softStopDurationSeconds,
            repetitionWindowCharacters: request.tuning.repetitionWindowCharacters,
            repetitionThreshold: request.tuning.repetitionThreshold,
            availableMemoryBytesProvider: JarvisRuntimeHeuristics.availableMemoryBytes
        )
        var stopReason: JarvisRuntimeGenerationStopReason = .eos

        do {
            let stream = session.streamResponse(to: request.prompt)
            for try await chunk in stream {
                try Task.checkCancellation()
                if withLock({ cancelRequested }) {
                    throw JarvisModelError.cancelled
                }
                if config.memorySafetyGuardsEnabled {
                    do {
                        try guardrail.ingest(chunk)
                    } catch let stop as GuardStop {
                        stopReason = mappedStopReason(for: stop)
                        break
                    }
                }
                if stopReason != .eos {
                    break
                }
                onToken(chunk)
            }

            if stopReason == .eos, withLock({ cancelRequested }) {
                throw JarvisModelError.cancelled
            }
            return JarvisRuntimeGenerationOutcome(
                stopReason: stopReason,
                requestedContextTokenLimit: requestedContextLimit,
                effectiveContextTokenLimit: policy.contextSize,
                effectiveOutputTokenLimit: policy.maxOutputTokens,
                promptTokenEstimate: promptTokenEstimate,
                availableMemoryBytesAtStart: availableMemoryBytesAtStart,
                memoryFallbackTriggered: policy.memoryFallbackTriggered,
                thermalFallbackTriggered: policy.thermalFallbackTriggered,
                speculativeDecodingRequested: policy.speculativeDecodingRequested,
                speculativeDecodingEligible: policy.speculativeDecodingEligible,
                gpuOffloadEnabled: policy.gpuOffloadEnabled,
                requestedGPULayerCount: policy.gpuLayerCount,
                flashAttentionEnabled: policy.flashAttentionEnabled,
                estimatedKVCacheBytes: policy.estimatedKVCacheBytes
            )
        } catch is CancellationError {
            throw JarvisModelError.cancelled
        } catch let modelError as JarvisModelError {
            throw modelError
        } catch let stop as GuardStop {
            return JarvisRuntimeGenerationOutcome(
                stopReason: mappedStopReason(for: stop),
                requestedContextTokenLimit: requestedContextLimit,
                effectiveContextTokenLimit: policy.contextSize,
                effectiveOutputTokenLimit: policy.maxOutputTokens,
                promptTokenEstimate: promptTokenEstimate,
                availableMemoryBytesAtStart: availableMemoryBytesAtStart,
                memoryFallbackTriggered: policy.memoryFallbackTriggered,
                thermalFallbackTriggered: policy.thermalFallbackTriggered,
                speculativeDecodingRequested: policy.speculativeDecodingRequested,
                speculativeDecodingEligible: policy.speculativeDecodingEligible,
                gpuOffloadEnabled: policy.gpuOffloadEnabled,
                requestedGPULayerCount: policy.gpuLayerCount,
                flashAttentionEnabled: policy.flashAttentionEnabled,
                estimatedKVCacheBytes: policy.estimatedKVCacheBytes
            )
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
        filename: String,
        tuning: JarvisGenerationTuning?,
        availableMemoryBytes: UInt64?
    ) -> LoadAttempt {
        let policy = runtimePolicy(
            using: configuration,
            fileSizeBytes: fileSizeBytes,
            filename: filename,
            tuning: tuning,
            prompt: "",
            availableMemoryBytes: availableMemoryBytes,
            enforceLoadedContextLimit: false
        )

        return LoadAttempt(
            context: policy.contextSize,
            threads: policy.threadCount,
            batchThreads: policy.batchThreadCount,
            batch: policy.batchSize,
            microBatch: policy.microBatchSize,
            gpuLayerCount: policy.gpuLayerCount,
            preferGPU: policy.gpuOffloadEnabled,
            offloadKQV: policy.gpuOffloadEnabled,
            offloadOperations: policy.gpuOffloadEnabled,
            flashAttentionEnabled: policy.flashAttentionEnabled
        )
    }

    private func loadAttempts(
        using configuration: JarvisRuntimeConfiguration,
        fileSizeBytes: Int64,
        filename: String,
        availableMemoryBytes: UInt64?
    ) -> [LoadAttempt] {
        let base = deviceAwareParameters(
            using: configuration,
            fileSizeBytes: fileSizeBytes,
            filename: filename,
            tuning: withLock { requestTuning },
            availableMemoryBytes: availableMemoryBytes
        )

        let candidates = [
            base,
            LoadAttempt(
                context: min(base.context, 768),
                threads: min(base.threads, 3),
                batchThreads: min(base.batchThreads, 2),
                batch: min(base.batch, 16),
                microBatch: min(base.microBatch, 8),
                gpuLayerCount: min(base.gpuLayerCount, max(16, base.gpuLayerCount / 2)),
                preferGPU: base.preferGPU && base.gpuLayerCount > 0,
                offloadKQV: base.preferGPU && base.gpuLayerCount > 0,
                offloadOperations: base.preferGPU && base.gpuLayerCount > 0,
                flashAttentionEnabled: false
            ),
            LoadAttempt(
                context: min(base.context, 512),
                threads: min(base.threads, 2),
                batchThreads: 1,
                batch: min(base.batch, 8),
                microBatch: min(base.microBatch, 4),
                gpuLayerCount: min(base.gpuLayerCount, max(8, base.gpuLayerCount / 4)),
                preferGPU: base.preferGPU && base.gpuLayerCount > 0,
                offloadKQV: base.preferGPU && base.gpuLayerCount > 0,
                offloadOperations: base.preferGPU && base.gpuLayerCount > 0,
                flashAttentionEnabled: false
            ),
            LoadAttempt(
                context: 384,
                threads: 1,
                batchThreads: 1,
                batch: 4,
                microBatch: 4,
                gpuLayerCount: 0,
                preferGPU: false,
                offloadKQV: false,
                offloadOperations: false,
                flashAttentionEnabled: false
            )
        ]

        var uniqueAttempts: [LoadAttempt] = []
        for candidate in candidates {
            if !uniqueAttempts.contains(candidate) {
                uniqueAttempts.append(candidate)
            }
        }
        return uniqueAttempts
    }

    private func runtimePolicy(
        using configuration: JarvisRuntimeConfiguration,
        fileSizeBytes: Int64,
        filename: String,
        tuning: JarvisGenerationTuning?,
        prompt: String,
        availableMemoryBytes: UInt64? = JarvisRuntimeHeuristics.availableMemoryBytes(),
        enforceLoadedContextLimit: Bool = true
    ) -> RuntimePolicy {
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let thermalState = ProcessInfo.processInfo.thermalState
        let deviceTier = configuration.adaptiveDeviceTieringEnabled ? JarvisRuntimeDeviceTier.current() : .baseline
        let memoryPressure = JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: availableMemoryBytes)

        let baseContext: Int
        let kvBudgetMB: Int
        let baseThreads: Int
        let baseBatch: Int
        switch deviceTier {
        case .constrained:
            kvBudgetMB = 768
            switch configuration.performanceProfile {
            case .efficient:
                baseContext = 512
                baseThreads = 1
                baseBatch = 4
            case .balanced:
                baseContext = 576
                baseThreads = min(2, max(1, processorCount / 2))
                baseBatch = 6
            case .quality:
                baseContext = 640
                baseThreads = min(2, max(1, processorCount / 2))
                baseBatch = 8
            }
        case .baseline:
            kvBudgetMB = 1_200
            switch configuration.performanceProfile {
            case .efficient:
                baseContext = 768
                baseThreads = min(2, max(1, processorCount / 2))
                baseBatch = 8
            case .balanced:
                baseContext = 896
                baseThreads = min(3, max(2, processorCount / 2))
                baseBatch = 12
            case .quality:
                baseContext = 1_024
                baseThreads = min(3, max(2, processorCount / 2))
                baseBatch = 16
            }
        case .highMemory:
            kvBudgetMB = 2_000
            switch configuration.performanceProfile {
            case .efficient:
                baseContext = 1_024
                baseThreads = min(3, max(2, processorCount / 2))
                baseBatch = 16
            case .balanced:
                baseContext = 1_280
                baseThreads = min(4, max(2, processorCount / 2))
                baseBatch = 20
            case .quality:
                baseContext = 1_536
                baseThreads = min(5, max(3, (processorCount / 2) + 1))
                baseBatch = 24
            }
        }

        let requestedContextLimit = tuning?.maxContextTokens ?? configuration.contextWindow.explicitContextSize ?? baseContext
        var contextSize = min(
            requestedContextLimit,
            baseContext,
            JarvisRuntimeHeuristics.maxContextTokens(fileSizeBytes: fileSizeBytes, kvBudgetMB: kvBudgetMB)
        )

        let loadedProfile = withLock { self.loadedSessionProfile }
        if enforceLoadedContextLimit, let loadedProfile {
            contextSize = min(contextSize, loadedProfile.context)
        }

        var threadCount = max(1, baseThreads)
        var batchSize = max(4, min(baseBatch, max(4, contextSize / 12)))
        var batchThreadCount = JarvisRuntimeHeuristics.batchThreadCount(
            generationThreads: threadCount,
            deviceTier: deviceTier,
            thermalState: thermalState
        )
        var maxOutputTokens = tuning?.maxOutputTokens ?? 220
        let defaultGreetingCap = JarvisRuntimeHeuristics.isGreetingLikePrompt(prompt) ? 40 : maxOutputTokens
        maxOutputTokens = min(maxOutputTokens, defaultGreetingCap)
        var gpuLayerCount = JarvisRuntimeHeuristics.gpuLayerTarget(
            for: deviceTier,
            performanceProfile: configuration.performanceProfile,
            memoryPressure: memoryPressure,
            batterySaverMode: configuration.batterySaverMode,
            thermalState: thermalState
        )
        var flashAttentionEnabled = JarvisRuntimeHeuristics.shouldEnableFlashAttention(
            for: deviceTier,
            performanceProfile: configuration.performanceProfile,
            memoryPressure: memoryPressure,
            batterySaverMode: configuration.batterySaverMode,
            thermalState: thermalState
        )

        var memoryFallbackTriggered = false
        var thermalFallbackTriggered = false

        if configuration.batterySaverMode {
            contextSize = min(contextSize, 640)
            batchSize = min(batchSize, 8)
            maxOutputTokens = min(maxOutputTokens, 180)
            gpuLayerCount = min(gpuLayerCount, deviceTier == .constrained ? 8 : 24)
            flashAttentionEnabled = false
            memoryFallbackTriggered = true
        }

        if configuration.memorySafetyGuardsEnabled && memoryPressure == .reduced {
            contextSize = min(contextSize, 512)
            batchSize = min(batchSize, 8)
            maxOutputTokens = Int(Double(maxOutputTokens) * 0.75)
            gpuLayerCount = min(gpuLayerCount, deviceTier == .constrained ? 8 : 24)
            flashAttentionEnabled = false
            memoryFallbackTriggered = true
        }

        if configuration.thermalProtectionEnabled && thermalState == .serious {
            contextSize = min(contextSize, 512)
            threadCount = 1
            batchSize = 4
            maxOutputTokens = min(maxOutputTokens, 180)
            batchThreadCount = 1
            gpuLayerCount = min(gpuLayerCount, deviceTier == .highMemory ? 40 : 16)
            flashAttentionEnabled = false
            thermalFallbackTriggered = true
        }

        var microBatchSize = JarvisRuntimeHeuristics.microBatchSize(
            for: batchSize,
            deviceTier: deviceTier,
            memoryPressure: memoryPressure,
            thermalState: thermalState
        )
        let estimatedKVCacheBytes = JarvisRuntimeHeuristics.estimatedKVCacheBytes(
            contextTokens: max(384, contextSize),
            fileSizeBytes: fileSizeBytes
        )
        if enforceLoadedContextLimit, let loadedProfile {
            gpuLayerCount = min(gpuLayerCount, loadedProfile.gpuLayerCount)
            flashAttentionEnabled = flashAttentionEnabled && loadedProfile.flashAttentionEnabled
            batchThreadCount = min(batchThreadCount, loadedProfile.batchThreads)
            batchSize = min(batchSize, loadedProfile.batch)
            microBatchSize = min(microBatchSize, loadedProfile.microBatch)
        }
        let gpuOffloadEnabled = gpuLayerCount > 0

        let softStopDurationSeconds: Double
        switch deviceTier {
        case .constrained, .baseline:
            softStopDurationSeconds = thermalFallbackTriggered ? 12 : 20
        case .highMemory:
            softStopDurationSeconds = thermalFallbackTriggered ? 18 : 28
        }

        let speculativeRequested = configuration.experimentalSpeculativeDecodingEnabled
        let speculativeEligible = speculativeRequested && deviceTier == .highMemory

        _ = filename
        return RuntimePolicy(
            deviceTier: deviceTier,
            memoryPressure: memoryPressure,
            contextSize: max(384, contextSize),
            threadCount: threadCount,
            batchThreadCount: max(1, batchThreadCount),
            batchSize: max(4, batchSize),
            microBatchSize: max(4, min(microBatchSize, batchSize)),
            kvBudgetMB: kvBudgetMB,
            estimatedKVCacheBytes: estimatedKVCacheBytes,
            maxOutputTokens: max(40, maxOutputTokens),
            softStopDurationSeconds: softStopDurationSeconds,
            gpuLayerCount: max(0, gpuLayerCount),
            gpuOffloadEnabled: gpuOffloadEnabled,
            flashAttentionEnabled: flashAttentionEnabled && gpuOffloadEnabled,
            availableMemoryBytes: availableMemoryBytes,
            memoryFallbackTriggered: memoryFallbackTriggered,
            thermalFallbackTriggered: thermalFallbackTriggered,
            speculativeDecodingRequested: speculativeRequested,
            speculativeDecodingEligible: speculativeEligible
        )
    }

    private func parameter(
        for attempt: LoadAttempt,
        configuration: JarvisRuntimeConfiguration,
        tuning: JarvisGenerationTuning?
    ) -> LlamaClient.Parameter {
        var parameter = LlamaClient.Parameter()
        parameter.context = attempt.context
        parameter.numberOfThreads = attempt.threads
        parameter.batch = attempt.batch
        let effectiveTemperature = tuning?.temperature ?? configuration.temperature
        let clampedTemperature = max(0.12, min(effectiveTemperature, 0.95))
        parameter.temperature = Float(clampedTemperature)

        if let tuning {
            parameter.context = tuning.maxContextTokens > 0 ? min(parameter.context, tuning.maxContextTokens) : parameter.context
            parameter.topK = tuning.topK
            parameter.topP = Float(tuning.topP)
            parameter.typicalP = Float(tuning.typicalP)
            parameter.penaltyRepeat = Float(tuning.repeatPenalty)
            parameter.penaltyLastN = tuning.penaltyLastN
        } else {
            switch configuration.responseStyle {
            case .concise:
                parameter.topK = 32
                parameter.topP = 0.86
                parameter.typicalP = 0.94
            case .balanced:
                parameter.topK = 40
                parameter.topP = 0.9
                parameter.typicalP = 0.96
            case .detailed:
                parameter.topK = 48
                parameter.topP = 0.94
                parameter.typicalP = 0.98
            }
        }

        if tuning == nil {
            switch configuration.responseStyle {
            case .concise:
                parameter.penaltyLastN = 48
            case .balanced:
                parameter.penaltyLastN = 64
            case .detailed:
                parameter.penaltyLastN = 80
            }
        }

        let effectiveOutputCap = tuning?.maxOutputTokens ?? 220
        if effectiveOutputCap >= 300 {
            parameter.penaltyRepeat = max(parameter.penaltyRepeat, 1.12)
            parameter.penaltyLastN = max(parameter.penaltyLastN, 96)
        }
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
        let blueprint = request.promptBlueprint
        let resolvedResponseStyle = request.tuning.responseStyle
        let fallbackTaskInstruction = taskInstruction(for: request, configuration: configuration)

        let combinedSystemInstruction = [
            blueprint.systemInstruction.isEmpty ? Self.baseSystemInstruction : blueprint.systemInstruction,
            blueprint.assistantRole.isEmpty ? "Act like a capable private iPhone assistant." : blueprint.assistantRole,
            blueprint.taskTypeInstruction.isEmpty ? fallbackTaskInstruction : blueprint.taskTypeInstruction,
            blueprint.responseInstruction.isEmpty ? responseStyleInstruction(for: resolvedResponseStyle) : blueprint.responseInstruction,
            request.tuning.usesReasoningPlan &&
                !(blueprint.taskTypeInstruction.contains(Self.hiddenPlanningInstruction) ||
                  fallbackTaskInstruction.contains(Self.hiddenPlanningInstruction))
                ? Self.hiddenPlanningInstruction
                : nil,
            request.tuning.requiresGroundedAnswers
                ? "Answer with high confidence only where supported by the prompt or local context. If something is uncertain, say so briefly instead of filling gaps."
                : nil
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        var messages: [LLMInput.Message] = [
            .system(combinedSystemInstruction)
        ]

        for block in blueprint.contextBlocks where !block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.system("\(block.title):\n\(block.content)"))
        }

        if blueprint.contextBlocks.isEmpty {
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
        }

        let normalizedCurrentPrompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in request.history {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if item.role == .user, text == normalizedCurrentPrompt {
                continue
            }

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

    private func responseStyleInstruction(for style: JarvisAssistantResponseStyle) -> String {
        switch style {
        case .concise:
            return "Default to compact answers. Use short paragraphs or tight bullets only when they improve clarity."
        case .balanced:
            return "Balance speed with usefulness. Give a direct answer first, then add the most relevant supporting detail."
        case .detailed:
            return "Be thorough when it adds value, but keep the structure easy to scan on a phone screen."
        }
    }

    private func taskInstruction(
        for request: JarvisAssistantRequest,
        configuration: JarvisRuntimeConfiguration
    ) -> String {
        switch request.classification.category {
        case .generalChat:
            return "Handle this as a high-quality assistant conversation. Answer directly, avoid fluff, and give a practical next step when it would help."
        case .questionAnswering:
            return "Answer the question directly, then add only the most useful clarifying detail."
        case .summarization:
            return "Summarize the content into a short overview, then key points, then concrete next actions if they are implied. Keep the summary faithful and do not pad."
        case .draftingMessage:
            return "Draft a concise message that sounds natural and is ready to send."
        case .draftingEmail:
            return "Draft a professional email with a clear opening, concise body, and strong close. Make it ready to send."
        case .rewritingText:
            return "Rewrite the text with the requested tone or compression while preserving the important meaning."
        case .explainingSomething:
            return "Explain the concept clearly. Lead with the core idea, then add the mechanism or example that makes it click."
        case .planning:
            return "Organize the answer into actionable steps, priorities, and next moves."
        case .coding:
            return "Reason carefully about the code path, likely issues, and the smallest high-confidence fix."
        case .contextAwareReply:
            return configuration.responseStyle == .detailed
                ? "Draft a polished, context-aware reply that is ready to send with minimal editing."
                : "Draft a concise, context-aware reply that is ready to send."
        }

        switch request.task {
        case .chat:
            return "Handle this as a high-quality assistant conversation. Answer directly, avoid fluff, and give a practical next step when it would help."
        case .summarize:
            return "Summarize the content into a short overview, then key points, then concrete next actions if they are implied. Keep the summary faithful and do not pad."
        case .quickCapture:
            return "Treat this as a quick capture. Organize the thought clearly, preserve intent, and return a compact structure the user can act on later."
        case .knowledgeAnswer:
            return "Use the provided local knowledge when it is relevant. Prefer grounded answers, mention source titles when helpful, and clearly say when the local context is insufficient."
        case .reply:
            return configuration.responseStyle == .detailed
                ? "Draft a polished, send-ready reply that matches the supplied context, preserves important details, and sounds natural."
                : "Draft a concise, send-ready reply that matches the supplied context and tone."
        case .draftEmail:
            return "Draft a professional email with a clear opening, concise body, and strong close. Make it ready to send."
        case .analyzeText:
            return "Analyze the text and focus on what matters: key takeaways, risks, decisions, and next steps."
        case .visualDescribe:
            return "Be ready to describe user-provided visual context when that pipeline is added."
        case .prioritizeNotifications:
            return "Rank the supplied updates by urgency, impact, and required follow-up. Make the ranking easy to scan quickly."
        }
    }

    func loadDiagnosticsSelection() -> (gpuOffloadEnabled: Bool, gpuLayerCount: Int, flashAttentionEnabled: Bool)? {
        withLock {
            guard let loadedSessionProfile else { return nil }
            return (
                gpuOffloadEnabled: loadedSessionProfile.gpuOffloadEnabled,
                gpuLayerCount: loadedSessionProfile.gpuLayerCount,
                flashAttentionEnabled: loadedSessionProfile.flashAttentionEnabled
            )
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func mappedStopReason(for guardStop: GuardStop) -> JarvisRuntimeGenerationStopReason {
        switch guardStop {
        case .outputCap:
            return .maxTokens
        case .repetitionGuard:
            return .repetitionAbort
        case .thermalGuard:
            return .thermalAbort
        case .memoryGuard:
            return .memoryAbort
        }
    }
}
#endif

enum JarvisGGUFEngineFactory {
    static func makeEngine(for backend: JarvisRuntimeBackend) -> JarvisGGUFEngine {
        switch backend {
        case .localGGUF:
            return makeDefault()
        case .remoteOllama:
            return JarvisOllamaRemoteEngine()
        }
    }

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
    private final class StreamingMetricsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var timeToFirstToken: Double?
        private var outputCharacterCount = 0
        private var estimatedOutputTokens = 0

        func recordToken(_ token: String, startedAt: CFAbsoluteTime) {
            lock.lock()
            defer { lock.unlock() }

            if timeToFirstToken == nil {
                timeToFirstToken = CFAbsoluteTimeGetCurrent() - startedAt
            }
            outputCharacterCount += token.count
            estimatedOutputTokens += max(1, Int((Double(token.utf8.count) / 3.6).rounded(.up)))
        }

        func snapshot() -> (Double?, Int, Int) {
            lock.lock()
            defer { lock.unlock() }
            return (timeToFirstToken, outputCharacterCount, estimatedOutputTokens)
        }
    }

    @Published public private(set) var state: JarvisModelRuntimeState = .noModel
    @Published public private(set) var fileAccessState: JarvisModelFileAccessState = .noImportedFile
    @Published public private(set) var lastFailure: JarvisRuntimeFailure?
    @Published public private(set) var lastLoadDiagnostics: JarvisRuntimeLoadDiagnostics?
    @Published public private(set) var lastGenerationDiagnostics: JarvisRuntimeGenerationDiagnostics?

    private var engine: JarvisGGUFEngine
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
        self.engine = engine ?? JarvisGGUFEngineFactory.makeEngine(for: configuration.backend)
        self.configuration = configuration
        self.engine.updateConfiguration(configuration)
    }

    public var engineName: String { engine.name }

    public var isInferenceAvailable: Bool {
        if configuration.backend == .remoteOllama {
            return configuration.ollama.isConfigured && engine.isInstalled && engine.capability == .fullInference
        }
        return engine.isInstalled && engine.capability == .fullInference
    }

    public var supportsVisualInputs: Bool {
        guard configuration.backend == .localGGUF else { return false }
        guard let selectedModel else { return false }
        return engine.supportsVisualInputs &&
            selectedModel.capabilities.supportsVisionInputs &&
            selectedModel.projectorAttached
    }

    public var inferenceUnavailableReason: String {
        if configuration.backend == .remoteOllama {
            if configuration.ollama.normalizedBaseURL == nil {
                return "Configure a valid Ollama server URL to use the remote backend."
            }
            if configuration.ollama.modelName.isEmpty {
                return "Configure the Ollama model name to use the remote backend."
            }
            if !engine.isInstalled || engine.capability != .fullInference {
                return "Ollama remote inference is unavailable in this build."
            }
            return ""
        }
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
        let backendChanged = self.configuration.backend != configuration.backend
        self.configuration = configuration
        if backendChanged {
            teardownLoadedModel()
            engine = JarvisGGUFEngineFactory.makeEngine(for: configuration.backend)
        }
        engine.updateConfiguration(configuration)

        if configuration.backend == .remoteOllama {
            selectedModel = nil
            lastGenerationDiagnostics = nil
            if isInferenceAvailable {
                state = .cold(modelName: remoteModelName)
                fileAccessState = .accessGranted(
                    modelName: remoteModelName,
                    detail: "Ollama server configured at \(configuration.ollama.normalizedBaseURL?.absoluteString ?? configuration.ollama.baseURLString)."
                )
                lastFailure = nil
            } else {
                state = .runtimeUnavailable(reason: inferenceUnavailableReason)
                fileAccessState = .accessPending(modelName: remoteModelName, detail: inferenceUnavailableReason)
                lastFailure = runtimeFailure(
                    kind: .runtimeUnavailable,
                    message: inferenceUnavailableReason,
                    suggestion: "Update the Ollama server URL and model name in Settings."
                )
            }
            return
        }

        guard let model = selectedModel else {
            state = .noModel
            fileAccessState = .noImportedFile
            lastFailure = nil
            lastGenerationDiagnostics = nil
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
        guard configuration.backend == .localGGUF else {
            selectedModel = nil
            if isInferenceAvailable {
                state = .cold(modelName: remoteModelName)
                fileAccessState = .accessGranted(modelName: remoteModelName, detail: "Ollama server configured for remote inference.")
                lastFailure = nil
            } else {
                state = .runtimeUnavailable(reason: inferenceUnavailableReason)
                fileAccessState = .accessPending(modelName: remoteModelName, detail: inferenceUnavailableReason)
                lastFailure = runtimeFailure(
                    kind: .runtimeUnavailable,
                    message: inferenceUnavailableReason,
                    suggestion: "Update the Ollama server URL and model name in Settings."
                )
            }
            return
        }

        let previousID = selectedModel?.id
        activeGenerationTask?.cancel()
        selectedModel = model
        print("[JarvisRuntime] setSelectedModel previous=\(previousID?.uuidString ?? "nil") next=\(model?.id.uuidString ?? "nil")")

        guard let model else {
            teardownLoadedModel()
            state = .noModel
            fileAccessState = .noImportedFile
            lastFailure = nil
            lastGenerationDiagnostics = nil
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

    public func prepareIfNeeded(tuning: JarvisGenerationTuning? = nil) async throws {
        if configuration.backend == .remoteOllama {
            engine.updateGenerationTuning(tuning)

            guard isInferenceAvailable else {
                state = .runtimeUnavailable(reason: inferenceUnavailableReason)
                fileAccessState = .accessPending(modelName: remoteModelName, detail: inferenceUnavailableReason)
                lastFailure = runtimeFailure(
                    kind: .runtimeUnavailable,
                    message: inferenceUnavailableReason,
                    suggestion: "Update the Ollama server URL and model name in Settings."
                )
                throw JarvisModelError.runtimeFailure(inferenceUnavailableReason)
            }

            if didLoadModel {
                state = .ready(modelName: remoteModelName)
                fileAccessState = .accessGranted(modelName: remoteModelName, detail: "Connected to Ollama server.")
                lastFailure = nil
                return
            }

            state = .warming(modelName: remoteModelName, progress: 0.3, detail: "Checking Ollama model")
            try await engine.loadModel(at: configuration.ollama.modelName, projectorPath: nil)
            didLoadModel = true
            state = .ready(modelName: remoteModelName)
            fileAccessState = .accessGranted(modelName: remoteModelName, detail: "Connected to Ollama server.")
            lastFailure = nil
            lastLoadDiagnostics = nil
            return
        }

        guard let model = selectedModel else {
            state = .noModel
            fileAccessState = .noImportedFile
            lastFailure = nil
            lastLoadDiagnostics = nil
            lastGenerationDiagnostics = nil
            throw JarvisModelError.unavailable("No active model selected. Import and activate a GGUF model from Files.")
        }

        engine.updateGenerationTuning(tuning)

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

        let availableMemoryBytes = JarvisRuntimeHeuristics.availableMemoryBytes()
        if configuration.memorySafetyGuardsEnabled,
           JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: availableMemoryBytes) == .critical {
            let message = "Available memory is too low to warm the model safely."
            state = .paused(modelName: model.displayName, detail: message)
            fileAccessState = restingFileAccessState(for: model)
            lastFailure = runtimeFailure(
                kind: .warmupFailed,
                message: message,
                suggestion: "Unload the active model or close other apps, then retry warmup."
            )
            throw JarvisModelError.runtimeFailure("\(message) Unload and retry.")
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
            lastLoadDiagnostics = makeLoadDiagnostics(
                modelName: model.displayName,
                modelURL: resources.modelURL,
                projectorURL: resources.projectorURL
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
                    let startedAt = CFAbsoluteTimeGetCurrent()
                    let metrics = StreamingMetricsBox()
                    try await self.prepareIfNeeded(tuning: request.tuning)
                    let modelName = self.selectedModel?.displayName ?? "model"
                    self.state = .busy(modelName: modelName, detail: "Generating response")
                    self.lastFailure = nil
                    let outcome = try await self.engine.generate(request: request) { token in
                        metrics.recordToken(token, startedAt: startedAt)
                        continuation.yield(token)
                    }
                    let snapshot = metrics.snapshot()
                    let generationDuration = CFAbsoluteTimeGetCurrent() - startedAt
                    let tokensPerSecond = generationDuration > 0
                        ? Double(snapshot.2) / generationDuration
                        : 0
                    self.lastGenerationDiagnostics = JarvisRuntimeGenerationDiagnostics(
                        preset: request.tuning.preset.rawValue,
                        taskCategory: request.classification.category.rawValue,
                        deviceTier: JarvisRuntimeDeviceTier.current(),
                        promptCharacterCount: request.prompt.count,
                        historyMessageCount: request.history.count,
                        groundedResultCount: request.groundedResults.count,
                        outputCharacterCount: snapshot.1,
                        estimatedOutputTokens: snapshot.2,
                        totalEstimatedTokens: snapshot.2 + outcome.promptTokenEstimate,
                        promptTokenEstimate: outcome.promptTokenEstimate,
                        tokensPerSecond: tokensPerSecond,
                        timeToFirstTokenSeconds: snapshot.0,
                        generationDurationSeconds: generationDuration,
                        thermalState: ProcessInfo.processInfo.thermalState,
                        usedMemorySafeFallback: outcome.memoryFallbackTriggered || outcome.thermalFallbackTriggered,
                        memoryFallbackTriggered: outcome.memoryFallbackTriggered,
                        thermalFallbackTriggered: outcome.thermalFallbackTriggered,
                        stopReason: outcome.stopReason,
                        availableMemoryBytesAtStart: outcome.availableMemoryBytesAtStart,
                        effectiveContextTokenLimit: outcome.effectiveContextTokenLimit,
                        effectiveOutputTokenLimit: outcome.effectiveOutputTokenLimit,
                        gpuOffloadEnabled: outcome.gpuOffloadEnabled,
                        requestedGPULayerCount: outcome.requestedGPULayerCount,
                        flashAttentionEnabled: outcome.flashAttentionEnabled,
                        estimatedKVCacheBytes: outcome.estimatedKVCacheBytes
                    )
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
        state = .paused(modelName: currentModelName, detail: "Runtime paused while Jarvis is backgrounded.")
        if let selectedModel, loadedResources != nil {
            fileAccessState = accessGrantedState(for: selectedModel)
        } else if configuration.backend == .remoteOllama {
            fileAccessState = .accessGranted(modelName: remoteModelName, detail: "Remote runtime paused while Jarvis is backgrounded.")
        }
    }

    public func resumeFromForeground() {
        if configuration.backend == .remoteOllama {
            if isInferenceAvailable {
                state = idleRemoteState()
                fileAccessState = .accessGranted(modelName: remoteModelName, detail: "Ollama server is configured.")
                lastFailure = nil
            } else {
                state = .runtimeUnavailable(reason: inferenceUnavailableReason)
                fileAccessState = .accessPending(modelName: remoteModelName, detail: inferenceUnavailableReason)
                lastFailure = runtimeFailure(
                    kind: .runtimeUnavailable,
                    message: inferenceUnavailableReason,
                    suggestion: "Update the Ollama server URL and model name in Settings."
                )
            }
            return
        }

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

        if configuration.backend == .remoteOllama {
            state = .cold(modelName: remoteModelName)
            fileAccessState = isInferenceAvailable
                ? .accessGranted(modelName: remoteModelName, detail: "Ollama server configured.")
                : .accessPending(modelName: remoteModelName, detail: inferenceUnavailableReason)
            lastFailure = nil
        } else if let model = selectedModel {
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

    private var remoteModelName: String {
        let configured = configuration.ollama.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? "Ollama" : configured
    }

    private var currentModelName: String? {
        configuration.backend == .remoteOllama ? remoteModelName : selectedModel?.displayName
    }

    private func idleRemoteState() -> JarvisModelRuntimeState {
        didLoadModel ? .ready(modelName: remoteModelName) : .cold(modelName: remoteModelName)
    }

    private func restoreIdleState() {
        if configuration.backend == .remoteOllama {
            state = isInferenceAvailable ? idleRemoteState() : .runtimeUnavailable(reason: inferenceUnavailableReason)
            fileAccessState = isInferenceAvailable
                ? .accessGranted(modelName: remoteModelName, detail: "Ollama server configured.")
                : .accessPending(modelName: remoteModelName, detail: inferenceUnavailableReason)
            lastFailure = nil
            lastLoadDiagnostics = nil
            return
        }

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
        let availableMemoryBytes = JarvisRuntimeHeuristics.availableMemoryBytes()
        let deviceTier = configuration.adaptiveDeviceTieringEnabled ? JarvisRuntimeDeviceTier.current() : .baseline
        let memoryPressure = JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: availableMemoryBytes)
        let predictedGPULayerCount = JarvisRuntimeHeuristics.gpuLayerTarget(
            for: deviceTier,
            performanceProfile: configuration.performanceProfile,
            memoryPressure: memoryPressure,
            batterySaverMode: configuration.batterySaverMode,
            thermalState: ProcessInfo.processInfo.thermalState
        )
        let predictedFlashAttentionEnabled = JarvisRuntimeHeuristics.shouldEnableFlashAttention(
            for: deviceTier,
            performanceProfile: configuration.performanceProfile,
            memoryPressure: memoryPressure,
            batterySaverMode: configuration.batterySaverMode,
            thermalState: ProcessInfo.processInfo.thermalState
        )
        let loadedSelection = (engine as? JarvisLocalLLMClientEngine)?.loadDiagnosticsSelection()
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
            projectorPath: projectorURL?.standardizedFileURL.path,
            availableMemoryBytesAtLoad: availableMemoryBytes,
            prefersMemoryMapping: true,
            effectiveMemoryMappingKnown: false,
            memoryMappingNote: "Jarvis requests mmap-preferred GGUF loading, but LocalLLMClient does not currently expose whether it fell back to heap-backed loading.",
            requestedGPUOffload: loadedSelection?.gpuOffloadEnabled ?? (predictedGPULayerCount > 0),
            requestedGPULayerCount: loadedSelection?.gpuLayerCount ?? predictedGPULayerCount,
            flashAttentionRequested: loadedSelection?.flashAttentionEnabled ?? predictedFlashAttentionEnabled
        )
    }
}
