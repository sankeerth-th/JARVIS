import Foundation
import Combine

// MARK: - Orchestration Types

public struct JarvisOrchestrationRequest: Equatable {
    public let id: UUID
    public let createdAt: Date
    public let prompt: String
    public let task: JarvisAssistantTask
    public let source: String
    public let sourceKind: JarvisAssistantInvocationSourceKind
    public let mode: JarvisAssistantMode
    public let conversation: JarvisConversationRecord
    public let knowledgeResults: [JarvisKnowledgeResult]
    public let replyTargetText: String?
    public let inputMode: String
    public let routeContext: JarvisAssistantRouteContext
    public let attachments: [JarvisAssistantAttachmentPlaceholder]
    public let executionPreferences: JarvisAssistantExecutionPreferences
    public let settingsSnapshot: JarvisAssistantSettings
    
    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        prompt: String,
        task: JarvisAssistantTask = .chat,
        source: String = "orchestrator",
        sourceKind: JarvisAssistantInvocationSourceKind = .chat,
        mode: JarvisAssistantMode = .general,
        conversation: JarvisConversationRecord = JarvisConversationRecord(),
        knowledgeResults: [JarvisKnowledgeResult] = [],
        replyTargetText: String? = nil,
        inputMode: String = "text",
        routeContext: JarvisAssistantRouteContext = JarvisAssistantRouteContext(),
        attachments: [JarvisAssistantAttachmentPlaceholder] = [],
        executionPreferences: JarvisAssistantExecutionPreferences = .init(),
        settingsSnapshot: JarvisAssistantSettings = .default
    ) {
        self.id = id
        self.createdAt = createdAt
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.task = task
        self.source = source
        self.sourceKind = sourceKind
        self.mode = mode
        self.conversation = conversation
        self.knowledgeResults = knowledgeResults
        self.replyTargetText = replyTargetText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inputMode = inputMode
        self.routeContext = routeContext
        self.attachments = attachments
        self.executionPreferences = executionPreferences
        self.settingsSnapshot = settingsSnapshot
    }

    public var normalizedRequest: JarvisNormalizedAssistantRequest {
        JarvisNormalizedAssistantRequest(
            id: id,
            createdAt: createdAt,
            prompt: prompt,
            requestedTask: task,
            invocationSource: source,
            sourceKind: sourceKind,
            assistantMode: mode,
            conversationID: conversation.id,
            conversation: conversation,
            routeContext: routeContext,
            knowledgeResults: knowledgeResults,
            replyTargetText: replyTargetText,
            attachments: attachments,
            executionPreferences: executionPreferences,
            inputMode: inputMode,
            settingsSnapshot: settingsSnapshot
        )
    }
}

public struct JarvisOrchestrationResult: Equatable {
    public let request: JarvisOrchestrationRequest
    public let normalizedRequest: JarvisNormalizedAssistantRequest
    public let executionPlan: JarvisAssistantExecutionPlan
    public let turnResult: JarvisAssistantTurnResult
    public let classification: JarvisTaskClassification
    public let tuning: JarvisGenerationTuning
    public let assistantRequest: JarvisAssistantRequest
    public let memoryContext: MemoryContext
    public let selectedSkill: JarvisResolvedSkill?
    public let suggestions: [JarvisAssistantSuggestionDescriptor]
    public let streamingText: String
    public let isComplete: Bool
    public let error: JarvisOrchestrationError?
    
    public init(
        request: JarvisOrchestrationRequest,
        normalizedRequest: JarvisNormalizedAssistantRequest,
        executionPlan: JarvisAssistantExecutionPlan,
        turnResult: JarvisAssistantTurnResult,
        classification: JarvisTaskClassification = .default,
        tuning: JarvisGenerationTuning = .balanced,
        assistantRequest: JarvisAssistantRequest,
        memoryContext: MemoryContext = MemoryContext(),
        selectedSkill: JarvisResolvedSkill? = nil,
        suggestions: [JarvisAssistantSuggestionDescriptor] = [],
        streamingText: String = "",
        isComplete: Bool = false,
        error: JarvisOrchestrationError? = nil
    ) {
        self.request = request
        self.normalizedRequest = normalizedRequest
        self.executionPlan = executionPlan
        self.turnResult = turnResult
        self.classification = classification
        self.tuning = tuning
        self.assistantRequest = assistantRequest
        self.memoryContext = memoryContext
        self.selectedSkill = selectedSkill
        self.suggestions = suggestions
        self.streamingText = streamingText
        self.isComplete = isComplete
        self.error = error
    }
}

public enum JarvisOrchestrationState: Equatable {
    case idle
    case planning(plan: JarvisAssistantExecutionPlan?)
    case classifying
    case gatheringContext
    case preparingPrompt
    case warmingRuntime
    case generating
    case streaming(streamedText: String)
    case complete(result: JarvisOrchestrationResult)
    case error(JarvisOrchestrationError)
    
    public var isActive: Bool {
        switch self {
        case .idle, .complete, .error:
            return false
        default:
            return true
        }
    }
    
    public var displayTitle: String {
        switch self {
        case .idle:
            return "Ready"
        case .planning:
            return "Planning"
        case .classifying:
            return "Understanding"
        case .gatheringContext:
            return "Gathering Context"
        case .preparingPrompt:
            return "Preparing"
        case .warmingRuntime:
            return "Warming Up"
        case .generating:
            return "Generating"
        case .streaming:
            return "Responding"
        case .complete:
            return "Complete"
        case .error:
            return "Error"
        }
    }
}

public enum JarvisOrchestrationError: Error, Equatable {
    case noModelSelected
    case runtimeUnavailable(String)
    case warmupFailed(String)
    case generationFailed(String)
    case contextBuildingFailed(String)
    case cancelled
    
    public var localizedDescription: String {
        switch self {
        case .noModelSelected:
            return "No model selected. Please import and activate a model."
        case .runtimeUnavailable(let reason):
            return "Runtime unavailable: \(reason)"
        case .warmupFailed(let reason):
            return "Failed to warm model: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .contextBuildingFailed(let reason):
            return "Context building failed: \(reason)"
        case .cancelled:
            return "Request was cancelled"
        }
    }
}

// MARK: - Task Orchestrator

@MainActor
public final class JarvisTaskOrchestrator: ObservableObject {
    @Published public private(set) var state: JarvisOrchestrationState = .idle
    @Published public private(set) var currentResult: JarvisOrchestrationResult?
    @Published public private(set) var streamingText: String = ""
    
    // MARK: - Components
    private let runtime: JarvisLocalModelRuntime
    private let memoryManager: ConversationMemoryManager
    private let contextBuilder: ContextBuilder
    private let suggestionEngine: SuggestionEngine
    private let streamingPipeline: StreamingPipeline
    private let executionPlanner: JarvisExecutionPlanner
    private let memoryProvider: JarvisAssistantMemoryProviding
    private let requestElevator: JarvisRequestElevator
    
    // MARK: - State
    private var activeTask: Task<Void, Never>?
    private var currentRequest: JarvisOrchestrationRequest?
    private var cancellationRequested = false
    
    // MARK: - Initialization
    
    public init(
        runtime: JarvisLocalModelRuntime,
        memoryManager: ConversationMemoryManager? = nil,
        contextBuilder: ContextBuilder? = nil,
        suggestionEngine: SuggestionEngine? = nil,
        streamingPipeline: StreamingPipeline? = nil,
        executionPlanner: JarvisExecutionPlanner? = nil,
        memoryProvider: JarvisAssistantMemoryProviding = JarvisNullMemoryProvider(),
        requestElevator: JarvisRequestElevator? = nil
    ) {
        self.runtime = runtime
        self.memoryManager = memoryManager ?? ConversationMemoryManager()
        self.contextBuilder = contextBuilder ?? ContextBuilder()
        self.suggestionEngine = suggestionEngine ?? SuggestionEngine()
        self.streamingPipeline = streamingPipeline ?? StreamingPipeline()
        self.executionPlanner = executionPlanner ?? JarvisExecutionPlanner()
        self.memoryProvider = memoryProvider
        self.requestElevator = requestElevator ?? JarvisRequestElevator()
    }
    
    // MARK: - Public API
    
    public func orchestrate(
        request: JarvisOrchestrationRequest,
        onToken: @escaping @Sendable (String) -> Void = { _ in },
        onComplete: @escaping @Sendable (JarvisOrchestrationResult) -> Void = { _ in }
    ) {
        guard !state.isActive else {
            let plan = fallbackPlan(for: request)
            let turnResult = JarvisAssistantTurnResult(
                request: request.normalizedRequest,
                plan: plan,
                assistantRequest: nil,
                responseText: "",
                deliveryMode: plan.deliveryMode,
                diagnostics: plan.diagnostics,
                error: .generationFailed("Orchestrator is already processing a request")
            )
            onComplete(JarvisOrchestrationResult(
                request: request,
                normalizedRequest: request.normalizedRequest,
                executionPlan: plan,
                turnResult: turnResult,
                assistantRequest: JarvisAssistantRequest(
                    task: request.task,
                    prompt: request.prompt,
                    source: request.source,
                    history: []
                ),
                memoryContext: MemoryContext(),
                error: .generationFailed("Orchestrator is already processing a request")
            ))
            return
        }
        
        cancellationRequested = false
        currentRequest = request
        streamingText = ""
        
        activeTask = Task { [weak self] in
            guard let self = self else { return }
            
            let result = await self.executeOrchestration(
                request: request,
                onToken: onToken
            )
            
            await MainActor.run {
                self.currentResult = result
                self.state = result.error != nil ? .error(result.error!) : .complete(result: result)
                onComplete(result)
            }
        }
    }
    
    public func cancel() {
        cancellationRequested = true
        activeTask?.cancel()
        runtime.cancel()
        streamingPipeline.reset()
        state = .idle
    }
    
    public func reset() {
        cancel()
        currentResult = nil
        streamingText = ""
        currentRequest = nil
    }
    
    // MARK: - Private Implementation
    
    private func executeOrchestration(
        request: JarvisOrchestrationRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> JarvisOrchestrationResult {
        let normalizedRequest = request.normalizedRequest

        await updateState(.planning(plan: nil))
        guard !Task.isCancelled && !cancellationRequested else {
            return makeErrorResult(request, .cancelled)
        }

        // Step 1: Classify Task
        await updateState(.classifying)
        guard !Task.isCancelled && !cancellationRequested else {
            return makeErrorResult(request, .cancelled)
        }
        
        let classification = classifyTask(request: request)
        let resolvedSkill = JarvisSkillPolicyResolver.resolve(for: normalizedRequest, classification: classification)
        let elevatedRequest = requestElevator.elevate(
            prompt: request.prompt,
            requestedTask: classification.task,
            classification: classification
        )
        let memoryContext = memoryManager.prepareContext(
            conversation: request.conversation,
            prompt: request.prompt,
            classification: classification,
            skill: resolvedSkill,
            taskBudget: classification.task.historyLimit
        )
        let plan = await executionPlanner.makePlan(
            for: normalizedRequest,
            classification: classification,
            memoryContextAvailable: !memoryContext.recentMessages.isEmpty || memoryContext.summary != nil,
            elevatedRequest: elevatedRequest
        )
        await updateState(.planning(plan: plan))

        if let platformResponse = elevatedRequest.platformResponse {
            let assistantRequest = makePlatformOnlyAssistantRequest(
                request: request,
                classification: classification,
                elevatedRequest: elevatedRequest
            )
            let turnResult = JarvisAssistantTurnResult(
                request: normalizedRequest,
                plan: plan,
                assistantRequest: assistantRequest,
                responseText: platformResponse,
                suggestions: [],
                deliveryMode: .streamingText,
                diagnostics: plan.diagnostics,
                error: nil
            )
            return JarvisOrchestrationResult(
                request: request,
                normalizedRequest: normalizedRequest,
                executionPlan: plan,
                turnResult: turnResult,
                classification: classification,
                tuning: assistantRequest.tuning,
                assistantRequest: assistantRequest,
                memoryContext: memoryContext,
                selectedSkill: resolvedSkill,
                suggestions: [],
                streamingText: platformResponse,
                isComplete: true,
                error: nil
            )
        }

        if plan.mode == .capabilityAction {
            return makeCapabilityFallbackResult(
                request: request,
                normalizedRequest: normalizedRequest,
                classification: classification,
                elevatedRequest: elevatedRequest,
                memoryContext: memoryContext,
                plan: plan
            )
        }
        
        // Step 2: Gather Context
        await updateState(.gatheringContext)
        guard !Task.isCancelled && !cancellationRequested else {
            return makeErrorResult(request, .cancelled)
        }
        
        let contextAssembly = await buildContext(
            request: request,
            classification: classification,
            memoryContext: memoryContext,
            resolvedSkill: resolvedSkill
        )
        
        // Step 3: Prepare Prompt
        await updateState(.preparingPrompt)
        guard !Task.isCancelled && !cancellationRequested else {
            return makeErrorResult(request, .cancelled)
        }

        let memoryAugmentation = await memoryProvider.augmentation(
            for: normalizedRequest,
            classification: classification
        )

        let assistantRequest = buildAssistantRequest(
            request: request,
            classification: classification,
            contextAssembly: contextAssembly,
            memoryAugmentation: memoryAugmentation,
            elevatedRequest: elevatedRequest,
            plan: plan
        )
        
        // Step 4: Warm Runtime
        await updateState(.warmingRuntime)
        do {
            try await runtime.prepareIfNeeded(tuning: assistantRequest.tuning)
        } catch {
            return makeErrorResult(request, .warmupFailed(error.localizedDescription))
        }
        
        guard !Task.isCancelled && !cancellationRequested else {
            return makeErrorResult(request, .cancelled)
        }
        
        // Step 5: Generate & Stream
        await updateState(.generating)
        
        var accumulatedText = ""
        var streamError: JarvisOrchestrationError?
        
        do {
            try await stream(
                request: assistantRequest,
                accumulatedText: &accumulatedText,
                onToken: onToken
            )
        } catch {
            if shouldRetryWithSafePrompt(error: error, request: assistantRequest) {
                let safeRequest = makeSafePromptRequest(
                    request: request,
                    classification: classification,
                    contextAssembly: contextAssembly,
                    memoryAugmentation: memoryAugmentation,
                    elevatedRequest: elevatedRequest
                )

                accumulatedText = ""
                streamingPipeline.reset()
                do {
                    try await stream(
                        request: safeRequest,
                        accumulatedText: &accumulatedText,
                        onToken: onToken
                    )
                } catch {
                    streamError = .generationFailed(normalizedGenerationFailure(error))
                }
            } else {
                streamError = .generationFailed(normalizedGenerationFailure(error))
            }
        }
        
        // Step 6: Generate Suggestions
        var suggestions: [JarvisAssistantSuggestionDescriptor] = []
        if streamError == nil && !accumulatedText.isEmpty {
            suggestions = suggestionEngine.generateSuggestions(
                responseText: accumulatedText,
                classification: classification,
                mode: request.mode
            )
        }

        let turnResult = JarvisAssistantTurnResult(
            request: normalizedRequest,
            plan: plan,
            assistantRequest: assistantRequest,
            responseText: accumulatedText,
            suggestions: suggestions,
            deliveryMode: plan.deliveryMode,
            diagnostics: plan.diagnostics,
            error: streamError
        )
        
        // Build final result
        let result = JarvisOrchestrationResult(
            request: request,
            normalizedRequest: normalizedRequest,
            executionPlan: plan,
            turnResult: turnResult,
            classification: classification,
            tuning: assistantRequest.tuning,
            assistantRequest: assistantRequest,
            memoryContext: memoryContext,
            selectedSkill: resolvedSkill,
            suggestions: suggestions,
            streamingText: accumulatedText,
            isComplete: streamError == nil,
            error: streamError
        )
        
        // Update memory with this interaction
        await updateMemory(request: request, response: accumulatedText)
        
        return result
    }
    
    // MARK: - Helper Methods
    
    private func updateState(_ newState: JarvisOrchestrationState) async {
        await MainActor.run {
            self.state = newState
        }
    }
    
    private func classifyTask(request: JarvisOrchestrationRequest) -> JarvisTaskClassification {
        // Use existing intelligence but enhance with mode context
        var classification = JarvisAssistantIntelligence.classify(
            prompt: request.prompt,
            requestedTask: request.task,
            context: JarvisAssistantTaskContext(
                task: request.task,
                source: request.source,
                seedText: request.prompt,
                replyTargetText: request.replyTargetText
            ),
            conversation: request.conversation
        )
        
        // Override preset based on mode
        classification = applyModeToClassification(classification, mode: request.mode)
        
        return classification
    }
    
    private func applyModeToClassification(_ classification: JarvisTaskClassification, mode: JarvisAssistantMode) -> JarvisTaskClassification {
        let modePreset: JarvisGenerationPreset
        switch mode {
        case .general:
            modePreset = classification.preset
        case .explain:
            modePreset = .precise
        case .summarize:
            modePreset = .precise
        case .write:
            modePreset = .drafting
        case .plan:
            modePreset = .balanced
        case .code:
            modePreset = .coding
        case .reply:
            modePreset = .drafting
        }
        
        return JarvisTaskClassification(
            category: classification.category,
            task: classification.task,
            preset: modePreset,
            confidence: classification.confidence,
            reasoningHint: mode.reasoningHint,
            responseHint: mode.responseHint,
            shouldInjectKnowledge: classification.shouldInjectKnowledge,
            shouldPreferStructuredOutput: classification.shouldPreferStructuredOutput
        )
    }
    
    private func buildContext(
        request: JarvisOrchestrationRequest,
        classification: JarvisTaskClassification,
        memoryContext: MemoryContext,
        resolvedSkill: JarvisResolvedSkill
    ) async -> ContextAssembly {
        return contextBuilder.build(
            request: request,
            classification: classification,
            memoryContext: memoryContext,
            resolvedSkill: resolvedSkill
        )
    }
    
    private func buildAssistantRequest(
        request: JarvisOrchestrationRequest,
        classification: JarvisTaskClassification,
        contextAssembly: ContextAssembly,
        memoryAugmentation: JarvisAssistantMemoryAugmentation,
        elevatedRequest: JarvisElevatedRequest,
        plan: JarvisAssistantExecutionPlan
    ) -> JarvisAssistantRequest {
        let tuning = tunedGenerationSettings(
            base: JarvisAssistantIntelligence.tuning(for: classification, settings: request.settingsSnapshot),
            settings: request.settingsSnapshot,
            contract: elevatedRequest.responseContract
        )
        let contextBlocks = contextAssembly.contextBlocks + memoryAugmentation.supplementalContext

        let blueprint = JarvisPromptBlueprint(
            systemInstruction: contextAssembly.systemInstruction,
            assistantRole: contextAssembly.assistantRole,
            taskTypeInstruction: "\(contextAssembly.taskInstruction)\nIntent: \(elevatedRequest.elevatedIntent)",
            responseInstruction: responseInstruction(
                base: contextAssembly.responseInstruction,
                contract: elevatedRequest.responseContract
            ),
            contextBlocks: contextBlocks,
            userInputPrefix: classification.shouldPreferStructuredOutput 
                ? "User request. Use structure when it improves speed or clarity:"
                : "User request:"
        )

        let finalPrompt = "\(blueprint.userInputPrefix)\n\(elevatedRequest.elevatedPrompt)"
        let resolvedPromptMode: JarvisAssistantPromptMode = request.settingsSnapshot.promptMode == .safe || elevatedRequest.prefersSafePrompt
            ? .safe
            : .advanced
        let resolvedSkill = JarvisSkillPolicyResolver.resolve(for: request.normalizedRequest, classification: classification)
        let debugSummary = "task=\(classification.category.rawValue) skill=\(resolvedSkill.skill.id) mode=\(plan.mode.rawValue) elevated=\(elevatedRequest.kind.rawValue) preset=\(tuning.preset.rawValue) history=\(contextAssembly.recentMessages.count) knowledge=\(contextAssembly.knowledgeResults.count) memory=\(memoryAugmentation.summary == nil ? 0 : 1)"

        if resolvedPromptMode == .safe {
            return makeSafePromptRequest(
                request: request,
                classification: classification,
                contextAssembly: contextAssembly,
                memoryAugmentation: memoryAugmentation,
                elevatedRequest: elevatedRequest,
                tuningOverride: tuning,
                debugSummary: debugSummary
            )
        }

        return JarvisAssistantRequest(
            task: classification.task,
            prompt: finalPrompt,
            source: request.source,
            history: contextAssembly.recentMessages,
            groundedResults: contextAssembly.knowledgeResults,
            replyTargetText: request.replyTargetText,
            classification: classification,
            promptBlueprint: blueprint,
            tuning: tuning,
            debugSummary: debugSummary,
            promptMode: resolvedPromptMode
        )
    }
    
    private func updateMemory(request: JarvisOrchestrationRequest, response: String) async {
        let userMessage = JarvisChatMessage(role: .user, text: request.prompt)
        let assistantMessage = JarvisChatMessage(role: .assistant, text: response)

        memoryManager.recordInteraction(
            conversationID: request.conversation.id,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            task: request.task,
            classification: classifyTask(request: request)
        )
    }
    
    private func makeErrorResult(_ request: JarvisOrchestrationRequest, _ error: JarvisOrchestrationError) -> JarvisOrchestrationResult {
        let plan = fallbackPlan(for: request)
        let assistantRequest = JarvisAssistantRequest(
            task: request.task,
            prompt: request.prompt,
            source: request.source,
            history: []
        )
        let turnResult = JarvisAssistantTurnResult(
            request: request.normalizedRequest,
            plan: plan,
            assistantRequest: assistantRequest,
            responseText: "",
            deliveryMode: plan.deliveryMode,
            diagnostics: plan.diagnostics,
            error: error
        )

        return JarvisOrchestrationResult(
            request: request,
            normalizedRequest: request.normalizedRequest,
            executionPlan: plan,
            turnResult: turnResult,
            assistantRequest: assistantRequest,
            memoryContext: MemoryContext(),
            error: error
        )
    }

    private func fallbackPlan(for request: JarvisOrchestrationRequest) -> JarvisAssistantExecutionPlan {
        let normalizedRequest = request.normalizedRequest
        let classification = JarvisTaskClassification.default
        let elevatedRequest = JarvisElevatedRequest(
            kind: .actionRequest,
            elevatedIntent: "fallback",
            elevatedPrompt: request.prompt,
            responseContract: JarvisResponseContract()
        )
        let diagnostics = JarvisAssistantDecisionTrace(
            selectedMode: .directResponse,
            reasoning: ["Fallback orchestration plan was used because the request ended early before full planning completed."],
            usedExistingPromptPipeline: true,
            usedFallbackDirectResponse: true,
            memoryAugmentationAvailable: false,
            capabilityCandidates: []
        )

        return JarvisAssistantExecutionPlan(
            request: normalizedRequest,
            detectedTask: request.task,
            classification: classification,
            elevatedRequest: elevatedRequest,
            mode: .directResponse,
            responseStyle: request.mode.defaultResponseStyle,
            deliveryMode: .streamingText,
            steps: [
                JarvisAssistantExecutionStep(
                    kind: .normalizeRequest,
                    title: "Normalize Request",
                    detail: "Fallback normalization for an interrupted assistant turn.",
                    usesModel: false
                )
            ],
            diagnostics: diagnostics
        )
    }

    private func makePlatformOnlyAssistantRequest(
        request: JarvisOrchestrationRequest,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest
    ) -> JarvisAssistantRequest {
        JarvisAssistantRequest(
            task: classification.task,
            prompt: elevatedRequest.elevatedPrompt,
            source: request.source,
            history: [],
            groundedResults: [],
            replyTargetText: request.replyTargetText,
            classification: classification,
            promptBlueprint: .default,
            tuning: JarvisAssistantIntelligence.tuning(for: classification, settings: request.settingsSnapshot),
            debugSummary: "platform=\(elevatedRequest.kind.rawValue)",
            promptMode: .safe
        )
    }

    private func makeCapabilityFallbackResult(
        request: JarvisOrchestrationRequest,
        normalizedRequest: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest,
        memoryContext: MemoryContext,
        plan: JarvisAssistantExecutionPlan
    ) -> JarvisOrchestrationResult {
        let responseText = capabilityFallbackMessage(for: elevatedRequest.capabilityHint)
        let assistantRequest = makePlatformOnlyAssistantRequest(
            request: request,
            classification: classification,
            elevatedRequest: elevatedRequest
        )
        let turnResult = JarvisAssistantTurnResult(
            request: normalizedRequest,
            plan: plan,
            assistantRequest: assistantRequest,
            responseText: responseText,
            suggestions: [],
            deliveryMode: .statusOnly,
            diagnostics: plan.diagnostics,
            error: nil
        )

        return JarvisOrchestrationResult(
            request: request,
            normalizedRequest: normalizedRequest,
            executionPlan: plan,
            turnResult: turnResult,
            classification: classification,
            tuning: assistantRequest.tuning,
            assistantRequest: assistantRequest,
            memoryContext: memoryContext,
            suggestions: [],
            streamingText: responseText,
            isComplete: true,
            error: nil
        )
    }

    private func makeSafePromptRequest(
        request: JarvisOrchestrationRequest,
        classification: JarvisTaskClassification,
        contextAssembly: ContextAssembly,
        memoryAugmentation: JarvisAssistantMemoryAugmentation,
        elevatedRequest: JarvisElevatedRequest,
        tuningOverride: JarvisGenerationTuning? = nil,
        debugSummary: String? = nil
    ) -> JarvisAssistantRequest {
        let baseTuning = tuningOverride ?? tunedGenerationSettings(
            base: JarvisAssistantIntelligence.tuning(for: classification, settings: request.settingsSnapshot),
            settings: request.settingsSnapshot,
            contract: elevatedRequest.responseContract
        )
        let compactContext = makeSafePromptContext(
            contextAssembly: contextAssembly,
            memoryAugmentation: memoryAugmentation,
            contract: elevatedRequest.responseContract
        )
        let safePrompt = """
        User request:
        \(elevatedRequest.elevatedPrompt)

        \(compactContext)
        """
        let safeBlueprint = JarvisPromptBlueprint(
            systemInstruction: "You are Jarvis, a private on-device assistant. Answer naturally, directly, and never mention prompt templates or internal rendering.",
            assistantRole: "Act like a capable private iPhone assistant.",
            taskTypeInstruction: "Intent: \(elevatedRequest.elevatedIntent).",
            responseInstruction: responseInstruction(base: classification.responseHint, contract: elevatedRequest.responseContract),
            contextBlocks: [],
            userInputPrefix: "User request:"
        )

        return JarvisAssistantRequest(
            task: classification.task,
            prompt: safePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            source: request.source,
            history: [],
            groundedResults: [],
            replyTargetText: request.replyTargetText,
            classification: classification,
            promptBlueprint: safeBlueprint,
            tuning: baseTuning,
            debugSummary: debugSummary ?? "safe-prompt elevated=\(elevatedRequest.kind.rawValue)",
            promptMode: .safe
        )
    }

    private func makeSafePromptContext(
        contextAssembly: ContextAssembly,
        memoryAugmentation: JarvisAssistantMemoryAugmentation,
        contract: JarvisResponseContract
    ) -> String {
        var lines: [String] = []
        if !contextAssembly.taskInstruction.isEmpty {
            lines.append("Task framing:\n\(contextAssembly.taskInstruction)")
        }
        let firstHistory = contextAssembly.recentMessages
            .suffix(4)
            .map { "\($0.role == .assistant ? "Jarvis" : "User"): \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
        if !firstHistory.isEmpty {
            lines.append("Recent context:\n\(firstHistory)")
        }
        if !contextAssembly.knowledgeResults.isEmpty {
            let grounding = contextAssembly.knowledgeResults.prefix(2).map { "\($0.item.title): \($0.snippet)" }.joined(separator: "\n")
            lines.append("Local context:\n\(grounding)")
        }
        if let summary = memoryAugmentation.summary, !summary.isEmpty {
            lines.append("Memory:\n\(summary)")
        }
        if contract.prefersChecklist {
            lines.append("Format as a short checklist or numbered steps when that improves clarity.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func responseInstruction(base: String, contract: JarvisResponseContract) -> String {
        var instructions: [String] = [base]
        if contract.directAnswerFirst {
            instructions.append("Give the answer or fix first.")
        }
        if contract.prefersCodeFirst {
            instructions.append("Put code first.")
        }
        if contract.prefersRunnableOutput {
            instructions.append("Prefer a complete runnable small solution over vague discussion.")
        }
        if contract.prefersReadyToSend {
            instructions.append("Return ready-to-send text first.")
        }
        if contract.prefersMinimalExplanation {
            instructions.append("Keep any explanation brief and only after the main output.")
        }
        if contract.asksSingleQuestion {
            instructions.append("Ask exactly one precise follow-up question.")
        }
        if let maxSentences = contract.maxSentences {
            instructions.append("Keep it within \(maxSentences) sentences.")
        }
        if contract.prefersChecklist {
            instructions.append("Prefer a checklist or ordered list over a wall of text.")
        }
        if contract.forbidsHallucinatedCompletion {
            instructions.append("Do not claim an action completed unless the capability actually ran.")
        }
        if contract.avoidRoboticFiller {
            instructions.append("Avoid filler and robotic phrasing.")
        }
        return instructions.joined(separator: " ")
    }

    private func tunedGenerationSettings(
        base: JarvisGenerationTuning,
        settings: JarvisAssistantSettings,
        contract: JarvisResponseContract
    ) -> JarvisGenerationTuning {
        var tuned = base
        switch settings.assistantQualityMode {
        case .compact:
            tuned.maxOutputTokens = min(tuned.maxOutputTokens, 180)
            tuned.maxHistoryCharacters = min(tuned.maxHistoryCharacters, 1_400)
            tuned.responseStyle = .concise
        case .balanced:
            break
        case .highQuality:
            tuned.maxOutputTokens += 80
            tuned.maxHistoryCharacters += 500
        }
        if contract.asksSingleQuestion {
            tuned.maxOutputTokens = min(tuned.maxOutputTokens, 80)
            tuned.temperature = min(tuned.temperature, 0.38)
        }
        return tuned
    }

    private func shouldRetryWithSafePrompt(error: Error, request: JarvisAssistantRequest) -> Bool {
        guard request.promptMode != .safe else { return false }
        let message = error.localizedDescription.lowercased()
        return message.contains("template")
            || message.contains("jinja")
            || message.contains("invalid parameter")
            || message.contains("failed to decode response")
            || message.contains("failed to render")
    }

    private func normalizedGenerationFailure(_ error: Error) -> String {
        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if lowercased.contains("template") || lowercased.contains("jinja") || lowercased.contains("invalid parameter") {
            return "Jarvis could not prepare the advanced prompt path, and the safe fallback also failed."
        }
        return message
    }

    private func capabilityFallbackMessage(for kind: JarvisAssistantCapabilityCandidate.Kind?) -> String {
        switch kind {
        case .screenshot:
            return "Jarvis recognized this as a screenshot action. The screenshot capability is not wired in this build yet, so I am not claiming it completed."
        case .openRoute:
            return "Jarvis recognized this as an app route action. The route capability is not fully wired in this build yet, so I am not claiming it opened."
        case .searchKnowledge:
            return "Jarvis recognized this as a knowledge search request. The direct search capability is not wired in this build yet, so I am not guessing a result."
        case .saveContent:
            return "Jarvis recognized this as a save action. The save capability is not wired in this build yet, so I am not claiming it saved anything."
        case .copyContent:
            return "Jarvis recognized this as a copy action. The copy capability is not wired in this build yet, so I am not claiming it copied anything."
        case .newChat:
            return "Jarvis recognized this as a new chat action. The control plane routed it correctly, but the chat-reset capability is not wired in this build yet."
        case .draftEmail:
            return "Jarvis recognized this as an email drafting task. This build still completes it through the drafting path rather than a dedicated capability action."
        case .generic, .none:
            return "Jarvis recognized this as a capability-oriented request, but that capability is not wired in this build yet."
        }
    }

    private func stream(
        request: JarvisAssistantRequest,
        accumulatedText: inout String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        let stream = runtime.streamResponse(request: request)
        for try await token in stream {
            guard !Task.isCancelled && !cancellationRequested else {
                throw JarvisOrchestrationError.cancelled
            }
            let processedTokens = streamingPipeline.ingest(token)
            for processedToken in processedTokens {
                accumulatedText.append(processedToken)
                await MainActor.run {
                    self.streamingText = accumulatedText
                    self.state = .streaming(streamedText: accumulatedText)
                }
                onToken(processedToken)
            }
        }
        let finalTokens = streamingPipeline.finish()
        for token in finalTokens {
            accumulatedText.append(token)
            await MainActor.run {
                self.streamingText = accumulatedText
                self.state = .streaming(streamedText: accumulatedText)
            }
            onToken(token)
        }
    }
}
