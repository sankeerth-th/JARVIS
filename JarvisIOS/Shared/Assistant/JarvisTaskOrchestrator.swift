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
        executionPreferences: JarvisAssistantExecutionPreferences = .init()
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
            inputMode: inputMode
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
        memoryProvider: JarvisAssistantMemoryProviding = JarvisNullMemoryProvider()
    ) {
        self.runtime = runtime
        self.memoryManager = memoryManager ?? ConversationMemoryManager()
        self.contextBuilder = contextBuilder ?? ContextBuilder()
        self.suggestionEngine = suggestionEngine ?? SuggestionEngine()
        self.streamingPipeline = streamingPipeline ?? StreamingPipeline()
        self.executionPlanner = executionPlanner ?? JarvisExecutionPlanner()
        self.memoryProvider = memoryProvider
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
        let memoryContext = memoryManager.prepareContext(
            conversation: request.conversation,
            prompt: request.prompt,
            task: classification.task,
            taskBudget: classification.task.historyLimit
        )
        let plan = await executionPlanner.makePlan(
            for: normalizedRequest,
            classification: classification,
            memoryContextAvailable: !memoryContext.recentMessages.isEmpty || memoryContext.summary != nil
        )
        await updateState(.planning(plan: plan))
        
        // Step 2: Gather Context
        await updateState(.gatheringContext)
        guard !Task.isCancelled && !cancellationRequested else {
            return makeErrorResult(request, .cancelled)
        }
        
        let contextAssembly = await buildContext(
            request: request,
            classification: classification,
            memoryContext: memoryContext
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
            let stream = runtime.streamResponse(request: assistantRequest)
            
            for try await token in stream {
                guard !Task.isCancelled && !cancellationRequested else {
                    streamError = .cancelled
                    break
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
            
            // Flush any remaining tokens
            let finalTokens = streamingPipeline.finish()
            for token in finalTokens {
                accumulatedText.append(token)
                await MainActor.run {
                    self.streamingText = accumulatedText
                    self.state = .streaming(streamedText: accumulatedText)
                }
                onToken(token)
            }
            
        } catch {
            streamError = .generationFailed(error.localizedDescription)
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
        memoryContext: MemoryContext
    ) async -> ContextAssembly {
        return contextBuilder.build(
            request: request,
            classification: classification,
            memoryContext: memoryContext
        )
    }
    
    private func buildAssistantRequest(
        request: JarvisOrchestrationRequest,
        classification: JarvisTaskClassification,
        contextAssembly: ContextAssembly,
        memoryAugmentation: JarvisAssistantMemoryAugmentation,
        plan: JarvisAssistantExecutionPlan
    ) -> JarvisAssistantRequest {
        let tuning = JarvisAssistantIntelligence.tuning(for: classification, settings: .default)
        let contextBlocks = contextAssembly.contextBlocks + memoryAugmentation.supplementalContext
        
        let blueprint = JarvisPromptBlueprint(
            systemInstruction: contextAssembly.systemInstruction,
            assistantRole: contextAssembly.assistantRole,
            taskTypeInstruction: contextAssembly.taskInstruction,
            responseInstruction: contextAssembly.responseInstruction,
            contextBlocks: contextBlocks,
            userInputPrefix: classification.shouldPreferStructuredOutput 
                ? "User request. Use structure when it improves speed or clarity:"
                : "User request:"
        )
        
        let finalPrompt = "\(blueprint.userInputPrefix)\n\(request.prompt)"
        let debugSummary = "task=\(classification.category.rawValue) mode=\(plan.mode.rawValue) preset=\(tuning.preset.rawValue) history=\(contextAssembly.recentMessages.count) knowledge=\(contextAssembly.knowledgeResults.count) memory=\(memoryAugmentation.summary == nil ? 0 : 1)"
        
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
            debugSummary: debugSummary
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
}
