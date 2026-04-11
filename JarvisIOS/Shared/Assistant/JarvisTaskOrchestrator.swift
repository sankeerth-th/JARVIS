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

    public var finalizedTurnResult: JarvisAssistantTurnResult {
        turnResult
    }

    public var resultPlan: JarvisAssistantExecutionPlan {
        turnResult.plan
    }

    public var resultDiagnostics: JarvisAssistantDecisionTrace {
        turnResult.diagnostics
    }

    public var resultSuggestions: [JarvisAssistantSuggestionDescriptor] {
        turnResult.suggestions
    }

    public var resultMessageAttribution: JarvisMessageMemoryAttribution {
        turnResult.messageAttribution
    }

    public func finalizedResponseText(runtimeStreamingText: String = "") -> String {
        turnResult.finalizedResponseText(
            fallbackStreamingText: streamingText,
            runtimeStreamingText: runtimeStreamingText
        )
    }
    
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

@MainActor
struct JarvisCompletedTurnObservation: Equatable {
    let requestID: UUID
    let planID: UUID
    let conversationID: UUID
    let intent: String
    let mode: String
    let modelLane: String?
    let skillID: String?
    let trace: ExecutionTrace?
    let status: JarvisExecutionStatus
    let messageAttribution: JarvisMessageMemoryAttribution
    let summary: String

    init(_ result: JarvisOrchestrationResult) {
        let summarySource = result.finalizedResponseText().isEmpty
            ? (result.error?.localizedDescription ?? result.executionPlan.diagnostics.reasoning.joined(separator: " "))
            : result.finalizedResponseText()

        self.requestID = result.turnResult.requestID
        self.planID = result.turnResult.plan.id
        self.conversationID = result.request.conversation.id
        self.intent = result.turnResult.plan.routeDecision?.typedIntent.intent ?? result.turnResult.plan.elevatedRequest.elevatedIntent
        self.mode = result.turnResult.plan.mode.rawValue
        self.modelLane = result.turnResult.plan.selectedModelLane?.rawValue
        self.skillID = result.turnResult.messageAttribution.chosenSkillID
        self.trace = result.turnResult.executionTrace
        self.status = result.error == nil ? .success : .failed
        self.messageAttribution = result.turnResult.messageAttribution
        self.summary = String(summarySource.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
    }
}

@MainActor
protocol JarvisPassiveTurnObserving {
    func observe(_ observation: JarvisCompletedTurnObservation) async throws
}

@MainActor
struct JarvisExecutionHistoryObserver: JarvisPassiveTurnObserving {
    private let store: JarvisExecutionHistoryStore

    init(store: JarvisExecutionHistoryStore) {
        self.store = store
    }

    func observe(_ observation: JarvisCompletedTurnObservation) async throws {
        store.append(
            JarvisExecutionHistoryRecord(
                conversationID: observation.conversationID,
                intent: observation.intent,
                mode: observation.mode,
                modelLane: observation.modelLane,
                skillID: observation.skillID,
                status: observation.status.rawValue,
                summary: observation.summary
            )
        )
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
    private let executionRuntime: any ExecutionRuntime
    private let memoryManager: ConversationMemoryManager
    private let contextBuilder: ContextBuilder
    private let suggestionEngine: SuggestionEngine
    private let streamingPipeline: StreamingPipeline
    private let executionPlanner: any ExecutionPlanner
    private let memoryProvider: JarvisAssistantMemoryProviding
    private let memoryBoundary: any MemoryBoundary
    private let requestElevator: JarvisRequestElevator
    private let intentRouter: JarvisIntentRouter
    private let policyEngine: JarvisPolicyEngine
    private let modelRouter: JarvisModelRouter
    private let executionHistoryStore: JarvisExecutionHistoryStore
    private let passiveTurnObserver: (any JarvisPassiveTurnObserving)?
    private let toolRegistry: any JarvisToolRegistryProviding
    private let capabilityRegistry: any CapabilityRegistry
    private let capabilityExecutor: any CapabilityExecutor
    
    // MARK: - State
    private var activeTask: Task<Void, Never>?
    private var currentRequest: JarvisOrchestrationRequest?
    private var cancellationRequested = false

    private enum GenerationDriver {
        case directRuntime
        case legacyRuntime
    }

    private struct StreamedGenerationResult {
        let finalText: String
        let streamedChunks: [String]
        let stopReason: JarvisAssistantGenerationStopReason
    }
    
    // MARK: - Initialization
    
    @MainActor
    init(
        runtime: JarvisLocalModelRuntime,
        executionRuntime: (any ExecutionRuntime)? = nil,
        memoryManager: ConversationMemoryManager? = nil,
        contextBuilder: ContextBuilder? = nil,
        suggestionEngine: SuggestionEngine? = nil,
        streamingPipeline: StreamingPipeline? = nil,
        executionPlanner: (any ExecutionPlanner)? = nil,
        memoryProvider: JarvisAssistantMemoryProviding = JarvisNullMemoryProvider(),
        memoryBoundary: (any MemoryBoundary)? = nil,
        requestElevator: JarvisRequestElevator? = nil,
        intentRouter: JarvisIntentRouter? = nil,
        policyEngine: JarvisPolicyEngine? = nil,
        modelRouter: JarvisModelRouter? = nil,
        executionHistoryStore: JarvisExecutionHistoryStore? = nil,
        passiveTurnObserver: (any JarvisPassiveTurnObserving)? = nil,
        toolRegistry: any JarvisToolRegistryProviding = JarvisToolRegistry(),
        capabilityRegistry: (any CapabilityRegistry)? = nil,
        capabilityExecutor: (any CapabilityExecutor)? = nil
    ) {
        let resolvedIntentRouter = intentRouter ?? JarvisIntentRouter()
        let resolvedPolicyEngine = policyEngine ?? JarvisPolicyEngine()
        let resolvedModelRouter = modelRouter ?? JarvisModelRouter()
        let resolvedExecutionHistoryStore = executionHistoryStore ?? JarvisExecutionHistoryStore()
        self.runtime = runtime
        self.executionRuntime = executionRuntime ?? JarvisLocalExecutionRuntimeAdapter(runtime: runtime)
        self.memoryManager = memoryManager ?? ConversationMemoryManager()
        self.contextBuilder = contextBuilder ?? ContextBuilder()
        self.suggestionEngine = suggestionEngine ?? SuggestionEngine()
        self.streamingPipeline = streamingPipeline ?? StreamingPipeline(configuration: .responsive)
        self.executionPlanner = executionPlanner ?? JarvisExecutionPlannerAdapter(
            intentRouter: resolvedIntentRouter,
            policyEngine: resolvedPolicyEngine,
            modelRouter: resolvedModelRouter
        )
        self.memoryProvider = memoryProvider
        self.memoryBoundary = memoryBoundary ?? JarvisExecutionMemoryBoundaryAdapter(
            memoryManager: self.memoryManager,
            memoryProvider: memoryProvider
        )
        self.requestElevator = requestElevator ?? JarvisRequestElevator()
        self.intentRouter = resolvedIntentRouter
        self.policyEngine = resolvedPolicyEngine
        self.modelRouter = resolvedModelRouter
        self.executionHistoryStore = resolvedExecutionHistoryStore
        self.passiveTurnObserver = passiveTurnObserver ?? JarvisExecutionHistoryObserver(store: resolvedExecutionHistoryStore)
        self.toolRegistry = toolRegistry
        let resolvedCapabilityRegistry = capabilityRegistry ?? JarvisToolBackedCapabilityRegistry(toolRegistry: toolRegistry)
        self.capabilityRegistry = resolvedCapabilityRegistry
        self.capabilityExecutor = capabilityExecutor ?? JarvisToolBackedCapabilityExecutor(registry: resolvedCapabilityRegistry)
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
        executionRuntime.cancel()
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
            return await finalizeAndObserveTurn(makeErrorResult(request, .cancelled))
        }

        // Step 1: Classify Task
        await updateState(.classifying)
        guard !Task.isCancelled && !cancellationRequested else {
            return await finalizeAndObserveTurn(makeErrorResult(request, .cancelled))
        }
        
        let classification = classifyTask(request: request)
        let resolvedSkill = JarvisSkillPolicyResolver.resolve(for: normalizedRequest, classification: classification)
        let elevatedRequest = requestElevator.elevate(
            prompt: request.prompt,
            requestedTask: classification.task,
            classification: classification
        )
        let planningMemoryContext = memoryManager.prepareContext(
            conversation: request.conversation,
            prompt: request.prompt,
            classification: classification,
            skill: resolvedSkill,
            taskBudget: classification.task.historyLimit
        )
        let plan = await executionPlanner.makePlan(
            for: normalizedRequest,
            classification: classification,
            memoryContextAvailable: !planningMemoryContext.recentMessages.isEmpty || planningMemoryContext.summary != nil,
            elevatedRequest: elevatedRequest,
            resolvedSkill: resolvedSkill
        )
        await updateState(.planning(plan: plan))

        let memoryBoundaryRequest = MemoryBoundaryRequest(
            request: request,
            normalizedRequest: normalizedRequest,
            classification: classification,
            resolvedSkill: resolvedSkill
        )

        let preparedMemorySnapshot: MemorySnapshot?
        let memoryContext: MemoryContext
        if plan.mode == .memoryAugmentedResponse {
            let snapshot = await memoryBoundary.prepare(request: memoryBoundaryRequest)
            preparedMemorySnapshot = snapshot
            memoryContext = snapshot.context
        } else {
            preparedMemorySnapshot = nil
            memoryContext = planningMemoryContext
        }

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
                messageAttribution: makeMessageAttribution(
                    memoryContext: memoryContext,
                    selectedSkill: resolvedSkill
                ),
                error: nil
            )
            return await finalizeAndObserveTurn(
                JarvisOrchestrationResult(
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
            )
        }

        if plan.mode == .capabilityAction {
            if let resolvedResult = await executeMigratedCapabilityAction(
                request: request,
                normalizedRequest: normalizedRequest,
                classification: classification,
                elevatedRequest: elevatedRequest,
                memoryContext: memoryContext,
                plan: plan
            ) {
                return await finalizeAndObserveTurn(resolvedResult)
            }
            return await finalizeAndObserveTurn(
                makeCapabilityFallbackResult(
                request: request,
                normalizedRequest: normalizedRequest,
                classification: classification,
                elevatedRequest: elevatedRequest,
                memoryContext: memoryContext,
                plan: plan
                )
            )
        }
        
        // Step 2: Gather Context
        await updateState(.gatheringContext)
        guard !Task.isCancelled && !cancellationRequested else {
            return await finalizeAndObserveTurn(makeErrorResult(request, .cancelled))
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
            return await finalizeAndObserveTurn(makeErrorResult(request, .cancelled))
        }

        let memoryAugmentation: JarvisAssistantMemoryAugmentation
        if let preparedMemorySnapshot {
            memoryAugmentation = preparedMemorySnapshot.augmentation
        } else {
            memoryAugmentation = await memoryProvider.augmentation(
                for: normalizedRequest,
                classification: classification
            )
        }

        let assistantRequest = buildAssistantRequest(
            request: request,
            classification: classification,
            contextAssembly: contextAssembly,
            memoryAugmentation: memoryAugmentation,
            elevatedRequest: elevatedRequest,
            plan: plan
        )
        let generationDriver = generationDriver(for: plan)
        
        // Step 4: Warm Runtime
        await updateState(.warmingRuntime)
        do {
            switch generationDriver {
            case .directRuntime:
                try await executionRuntime.prepareIfNeeded(tuning: assistantRequest.tuning)
            case .legacyRuntime:
                try await runtime.prepareIfNeeded(tuning: assistantRequest.tuning)
            }
        } catch {
            return await finalizeAndObserveTurn(makeErrorResult(request, .warmupFailed(error.localizedDescription)))
        }
        
        guard !Task.isCancelled && !cancellationRequested else {
            return await finalizeAndObserveTurn(makeErrorResult(request, .cancelled))
        }
        
        // Step 5: Generate, Validate, Retry Once If Needed
        await updateState(.generating)

        let generationOutcome = await generateValidatedResponse(
            orchestrationRequest: request,
            normalizedRequest: normalizedRequest,
            classification: classification,
            elevatedRequest: elevatedRequest,
            plan: plan,
            assistantRequest: assistantRequest,
            generationDriver: generationDriver,
            onToken: onToken
        )

        let finalAssistantRequest = generationOutcome.assistantRequest
        let finalText = generationOutcome.finalText
        let streamError = generationOutcome.error

        // Step 6: Generate Suggestions
        var suggestions: [JarvisAssistantSuggestionDescriptor] = []
        if streamError == nil && !finalText.isEmpty {
            suggestions = suggestionEngine.generateSuggestions(
                responseText: finalText,
                classification: classification,
                mode: request.mode
            )
        }

        let turnResult = JarvisAssistantTurnResult(
            request: normalizedRequest,
            plan: plan,
            assistantRequest: finalAssistantRequest,
            responseText: finalText,
            suggestions: suggestions,
            deliveryMode: plan.deliveryMode,
            diagnostics: plan.diagnostics,
            messageAttribution: makeMessageAttribution(
                memoryContext: memoryContext,
                selectedSkill: resolvedSkill
            ),
            responseDiagnostics: generationOutcome.responseDiagnostics,
            error: streamError
        )
        let result = JarvisOrchestrationResult(
            request: request,
            normalizedRequest: normalizedRequest,
            executionPlan: plan,
            turnResult: turnResult,
            classification: classification,
            tuning: finalAssistantRequest.tuning,
            assistantRequest: finalAssistantRequest,
            memoryContext: memoryContext,
            selectedSkill: resolvedSkill,
            suggestions: suggestions,
            streamingText: finalText,
            isComplete: streamError == nil,
            error: streamError
        )

        if streamError == nil {
            if plan.mode == .memoryAugmentedResponse {
                await memoryBoundary.record(
                    request: memoryBoundaryRequest,
                    result: turnResult.coreAssistantTurnResult
                )
            } else {
                await updateMemory(request: request, response: finalText)
            }
        }
        return await finalizeAndObserveTurn(result)
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

    private func executeMigratedCapabilityAction(
        request: JarvisOrchestrationRequest,
        normalizedRequest: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest,
        memoryContext: MemoryContext,
        plan: JarvisAssistantExecutionPlan
    ) async -> JarvisOrchestrationResult? {
        let capabilityID = plan.selectedCapabilityID
            ?? plan.coreExecutionPlan.steps.first(where: { $0.kind == .capability })?.capability.map { CapabilityID(rawValue: $0.id) }
        guard let capabilityID else {
            return nil
        }
        guard let descriptor = capabilityRegistry.descriptor(for: capabilityID) else {
            return nil
        }

        let capabilityInput = capabilityInput(for: descriptor.id, request: request)
        let capabilityResult = await capabilityExecutor.execute(
            CapabilityInvocation(
                requestID: request.id,
                conversationID: normalizedRequest.conversationID,
                capabilityID: capabilityID,
                input: capabilityInput,
                typedIntent: plan.coreExecutionPlan.intent,
                policyDecision: plan.policyDecision,
                approvalState: descriptor.requiresApproval || plan.capabilityApprovalRequired ? .required : .notRequired
            )
        )

        let assistantRequest = makePlatformOnlyAssistantRequest(
            request: request,
            classification: classification,
            elevatedRequest: elevatedRequest
        )
        let turnResult = JarvisAssistantTurnResult(
            request: normalizedRequest,
            plan: plan,
            assistantRequest: assistantRequest,
            responseText: capabilityResult.userMessage,
            capabilitySurfaces: JarvisAssistantCapabilityFormatter.format(
                capabilityID: descriptor.id,
                input: capabilityInput,
                result: capabilityResult,
                platformAvailability: descriptor.platformAvailability
            ),
            suggestions: [],
            deliveryMode: .statusOnly,
            diagnostics: plan.diagnostics,
            messageAttribution: makeMessageAttribution(
                memoryContext: memoryContext,
                selectedSkill: nil
            ),
            capabilityState: capabilityResult.state,
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
            streamingText: capabilityResult.userMessage,
            isComplete: ![.failed, .cancelled].contains(capabilityResult.status),
            error: [.failed, .cancelled].contains(capabilityResult.status) ? .generationFailed(capabilityResult.userMessage) : nil
        )
    }

    private func capabilityInput(
        for capabilityID: CapabilityID,
        request: JarvisOrchestrationRequest
    ) -> CapabilityInputPayload {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        switch capabilityID.rawValue {
        case "knowledge.lookup":
            return .memorySearch(.init(query: prompt, limit: 5))
        case "file.search":
            return .fileSearch(
                .init(
                    roots: [],
                    query: extractSearchQuery(from: prompt),
                    glob: nil,
                    extensions: [],
                    contentSearch: prompt.lowercased().contains("content"),
                    limit: 20
                )
            )
        case "file.read":
            if let path = extractPath(from: prompt) {
                return .fileRead(.init(path: ScopedPath(token: path, displayPath: path), lineRange: nil, maxBytes: nil))
            }
        case "file.preview":
            if let path = extractPath(from: prompt) {
                return .filePreview(.init(path: ScopedPath(token: path, displayPath: path)))
            }
        case "file.patch":
            if let path = extractPath(from: prompt) {
                return .filePatch(.init(path: ScopedPath(token: path, displayPath: path), unifiedDiff: ""))
            }
        case "file.create":
            if let path = extractPath(from: prompt) {
                let url = URL(fileURLWithPath: path)
                return .fileCreate(
                    .init(
                        parent: ScopedPath(token: url.deletingLastPathComponent().path, displayPath: url.deletingLastPathComponent().path),
                        name: url.lastPathComponent,
                        contents: ""
                    )
                )
            }
        case "app.open":
            return .appOpen(.init(bundleID: extractBundleLikeIdentifier(from: prompt), appURL: nil))
        case "app.focus":
            if let bundleID = extractBundleLikeIdentifier(from: prompt) {
                return .appFocus(.init(bundleID: bundleID))
            }
        case "finder.reveal":
            if let path = extractPath(from: prompt) {
                return .finderReveal(.init(path: ScopedPath(token: path, displayPath: path)))
            }
        case "system.open_url":
            if let url = extractURL(from: prompt) {
                return .systemOpenURL(.init(url: url))
            }
        case "project.open":
            if let path = extractPath(from: prompt) {
                return .projectOpen(.init(path: ScopedPath(token: path, displayPath: path, scopeKind: .project)))
            }
        case "project.analyze":
            if let path = extractPath(from: prompt) {
                return .projectAnalyze(.init(root: ScopedPath(token: path, displayPath: path, scopeKind: .project), mode: .summary))
            }
        case "project.scaffold":
            if let path = extractPath(from: prompt) {
                return .projectScaffold(.init(destination: ScopedPath(token: path, displayPath: path, scopeKind: .project), template: .unknown, name: "NewProject"))
            }
        default:
            break
        }

        return .none
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

    private func generationDriver(for plan: JarvisAssistantExecutionPlan) -> GenerationDriver {
        if let selectedLane = plan.selectedModelLane ?? plan.routeDecision?.lane {
            switch selectedLane {
            case .localFast:
                return .directRuntime
            case .remoteReasoning:
                return .legacyRuntime
            }
        }

        return plan.mode == .directResponse ? .directRuntime : .legacyRuntime
    }

    private func finalizeAndObserveTurn(_ result: JarvisOrchestrationResult) async -> JarvisOrchestrationResult {
        var finalizedTurnResult = result.turnResult
        finalizedTurnResult.executionTrace = makeExecutionTrace(for: result)

        let finalizedResult = JarvisOrchestrationResult(
            request: result.request,
            normalizedRequest: result.normalizedRequest,
            executionPlan: result.executionPlan,
            turnResult: finalizedTurnResult,
            classification: result.classification,
            tuning: result.tuning,
            assistantRequest: result.assistantRequest,
            memoryContext: result.memoryContext,
            selectedSkill: result.selectedSkill,
            suggestions: result.suggestions,
            streamingText: result.streamingText,
            isComplete: result.isComplete,
            error: result.error
        )

        await observeCompletedTurnIfNeeded(finalizedResult)
        return finalizedResult
    }

    private func recordExecution(_ result: JarvisOrchestrationResult) {
        let observation = JarvisCompletedTurnObservation(result)
        executionHistoryStore.append(
            JarvisExecutionHistoryRecord(
                conversationID: observation.conversationID,
                intent: observation.intent,
                mode: observation.mode,
                modelLane: observation.modelLane,
                skillID: observation.skillID,
                status: observation.status.rawValue,
                summary: observation.summary
            )
        )
    }

    private func observeCompletedTurnIfNeeded(_ result: JarvisOrchestrationResult) async {
        guard let passiveTurnObserver else {
            recordExecution(result)
            return
        }

        do {
            try await passiveTurnObserver.observe(JarvisCompletedTurnObservation(result))
        } catch {
            // Passive hooks must never interfere with turn completion.
            recordExecution(result)
        }
    }

    private func makeMessageAttribution(
        memoryContext: MemoryContext,
        selectedSkill: JarvisResolvedSkill?
    ) -> JarvisMessageMemoryAttribution {
        JarvisMessageMemoryAttribution(
            usedMemory: memoryContext.isMemoryInformed,
            memorySourceIDs: memoryContext.retrievedMemories.map(\.record.id),
            sourceKinds: memoryContext.sourceKinds,
            labels: memoryContext.memoryLabels,
            usedSummary: memoryContext.summary != nil,
            chosenSkillID: selectedSkill?.skill.id
        )
    }

    private func makeExecutionTrace(for result: JarvisOrchestrationResult) -> ExecutionTrace {
        let plan = result.executionPlan
        let failedStepKind = failedStepKind(for: result.error)
        let capabilityID = plan.coreExecutionPlan.steps.first(where: { $0.kind == .capability })?.capability?.id
        let lastStepID = plan.steps.last?.id
        let statuses = Dictionary(uniqueKeysWithValues: plan.steps.map { step in
            let status: JarvisExecutionStatus
            if let failedStepKind {
                if step.kind == failedStepKind {
                    status = .failed
                } else if stepComesAfterFailure(step.kind, failedStepKind: failedStepKind) {
                    status = .partial
                } else {
                    status = .success
                }
            } else if result.error != nil, step.id == lastStepID {
                status = .failed
            } else {
                status = .success
            }

            return (step.id, status)
        })

        return ExecutionTrace(
            requestID: plan.request.id,
            planID: plan.id,
            lane: plan.selectedModelLane ?? plan.routeDecision?.lane ?? .localFast,
            steps: plan.steps.map { step in
                StepTrace(
                    id: step.id,
                    stepID: step.id,
                    capabilityID: step.kind == .inspectCapabilities ? capabilityID : nil,
                    status: statuses[step.id] ?? .partial
                )
            },
            status: result.error == nil ? .success : .failed
        )
    }

    private func failedStepKind(for error: JarvisOrchestrationError?) -> JarvisAssistantExecutionStepKind? {
        switch error {
        case .warmupFailed(_):
            return .warmRuntime
        case .generationFailed(_), .cancelled:
            return .infer
        case .contextBuildingFailed(_):
            return .buildContext
        default:
            return nil
        }
    }

    private func stepComesAfterFailure(
        _ stepKind: JarvisAssistantExecutionStepKind,
        failedStepKind: JarvisAssistantExecutionStepKind
    ) -> Bool {
        executionStepOrder(stepKind) > executionStepOrder(failedStepKind)
    }

    private func executionStepOrder(_ kind: JarvisAssistantExecutionStepKind) -> Int {
        switch kind {
        case .normalizeRequest:
            0
        case .classifyIntent:
            1
        case .chooseMode:
            2
        case .consultMemory:
            3
        case .inspectCapabilities:
            4
        case .buildContext:
            5
        case .preparePrompt:
            6
        case .warmRuntime:
            7
        case .infer:
            8
        case .finalizeTurn:
            9
        }
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
            messageAttribution: .init(),
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
            selectedModelLane: nil,
            policyReason: nil,
            chosenSkillID: nil,
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
            routeDecision: nil,
            policyDecision: nil,
            selectedModelLane: nil,
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
            messageAttribution: makeMessageAttribution(
                memoryContext: memoryContext,
                selectedSkill: nil
            ),
            capabilityState: plan.selectedCapabilityID.map {
                CapabilityExecutionState(
                    capabilityID: $0,
                    kind: .unsupported,
                    approvalState: .notRequired,
                    verification: .notApplicable,
                    output: .none,
                    statusMessage: responseText,
                    traceDetails: ["capability_id": $0.rawValue]
                )
            },
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

    private func normalizedGenerationFailure(_ error: Error) -> String {
        let message = error.localizedDescription
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

    private func extractSearchQuery(from prompt: String) -> String {
        let lowered = prompt.lowercased()
        let prefixes = [
            "search files for ",
            "search my files for ",
            "find file ",
            "find files ",
            "grep "
        ]
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            return String(prompt.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prompt
    }

    private func extractPath(from prompt: String) -> String? {
        let patterns = [
            #"`([^`]+)`"#,
            #"\"([^\"]+)\""#,
            #"(/[^\s]+)"#
        ]

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(prompt.startIndex..., in: prompt)
            guard let match = expression.firstMatch(in: prompt, options: [], range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: prompt) else {
                continue
            }

            let candidate = String(prompt[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.contains("/") || candidate.contains(".") {
                return candidate
            }
        }

        return nil
    }

    private func extractURL(from prompt: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(prompt.startIndex..., in: prompt)
        return detector?.matches(in: prompt, options: [], range: range).compactMap(\.url).first
    }

    private func extractBundleLikeIdentifier(from prompt: String) -> String? {
        let tokens = prompt
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?")) }

        return tokens.first(where: { $0.contains(".") && !$0.contains("/") })
    }

    private func stream(
        request: JarvisAssistantRequest,
        driver: GenerationDriver,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> StreamedGenerationResult {
        streamingPipeline.reset()
        let stream: AsyncThrowingStream<String, Error>
        switch driver {
        case .directRuntime:
            stream = executionRuntime.streamResponse(request: request)
        case .legacyRuntime:
            stream = runtime.streamResponse(request: request)
        }
        for try await token in stream {
            guard !Task.isCancelled && !cancellationRequested else {
                throw JarvisOrchestrationError.cancelled
            }
            let processedTokens = streamingPipeline.ingest(token)
            for _ in processedTokens {
                let draftText = streamingPipeline.authoritativeText
                await MainActor.run {
                    self.streamingText = draftText
                    self.state = .streaming(streamedText: draftText)
                }
                onToken(draftText)
            }
        }
        let completion = streamingPipeline.finish()
        if completion.finalText != streamingText {
            let finalText = completion.finalText
            await MainActor.run {
                self.streamingText = finalText
                self.state = .streaming(streamedText: finalText)
            }
            onToken(finalText)
        }
        let runtimeStopReason: JarvisRuntimeGenerationStopReason?
        switch driver {
        case .directRuntime:
            runtimeStopReason = executionRuntime.lastGenerationStopReason
        case .legacyRuntime:
            runtimeStopReason = runtime.lastGenerationDiagnostics?.stopReason
        }
        return StreamedGenerationResult(
            finalText: completion.finalText,
            streamedChunks: completion.streamedChunks,
            stopReason: mapStopReason(runtimeStopReason)
        )
    }

    private func generateValidatedResponse(
        orchestrationRequest: JarvisOrchestrationRequest,
        normalizedRequest: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest,
        plan: JarvisAssistantExecutionPlan,
        assistantRequest: JarvisAssistantRequest,
        generationDriver: GenerationDriver,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> (
        assistantRequest: JarvisAssistantRequest,
        finalText: String,
        responseDiagnostics: JarvisAssistantResponseDiagnostics,
        error: JarvisOrchestrationError?
    ) {
        let firstAttempt = await executeGenerationAttempt(
            request: assistantRequest,
            classification: classification,
            elevatedRequest: elevatedRequest,
            generationDriver: generationDriver,
            retryUsed: false,
            onToken: onToken
        )

        if firstAttempt.validation.isValid {
            return firstAttempt.result
        }

        guard firstAttempt.result.error == nil else {
            return firstAttempt.result
        }

        guard JarvisAssistantOutputValidator.isHighValueRetryTask(classification) else {
            return buildValidationFailureResult(
                orchestrationRequest: orchestrationRequest,
                normalizedRequest: normalizedRequest,
                plan: plan,
                assistantRequest: assistantRequest,
                elevatedRequest: elevatedRequest,
                finalText: firstAttempt.streamed.finalText,
                streamedChunks: firstAttempt.streamed.streamedChunks,
                validation: firstAttempt.validation,
                retryUsed: false
            )
        }

        let retryRequest = makeValidationRetryRequest(
            from: assistantRequest,
            elevatedRequest: elevatedRequest
        )
        streamingText = ""
        onToken("")
        let retryAttempt = await executeGenerationAttempt(
            request: retryRequest,
            classification: classification,
            elevatedRequest: elevatedRequest,
            generationDriver: generationDriver,
            retryUsed: true,
            onToken: onToken
        )

        if retryAttempt.validation.isValid {
            return retryAttempt.result
        }

        guard retryAttempt.result.error == nil else {
            return retryAttempt.result
        }

        return buildValidationFailureResult(
            orchestrationRequest: orchestrationRequest,
            normalizedRequest: normalizedRequest,
            plan: plan,
            assistantRequest: retryRequest,
            elevatedRequest: elevatedRequest,
            finalText: retryAttempt.streamed.finalText,
            streamedChunks: retryAttempt.streamed.streamedChunks,
            validation: retryAttempt.validation,
            retryUsed: true
        )
    }

    private func executeGenerationAttempt(
        request: JarvisAssistantRequest,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest,
        generationDriver: GenerationDriver,
        retryUsed: Bool,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> (
        streamed: StreamedGenerationResult,
        validation: JarvisAssistantOutputValidationResult,
        result: (
            assistantRequest: JarvisAssistantRequest,
            finalText: String,
            responseDiagnostics: JarvisAssistantResponseDiagnostics,
            error: JarvisOrchestrationError?
        )
    ) {
        do {
            let streamed = try await stream(
                request: request,
                driver: generationDriver,
                onToken: onToken
            )
            let validation = JarvisAssistantOutputValidator.validate(
                text: streamed.finalText,
                classification: classification
            )
            let stopReason: JarvisAssistantGenerationStopReason = validation.isValid
                ? streamed.stopReason
                : .validationFailure
            let finalText = validation.isValid ? validation.normalizedText : streamed.finalText
            return (
                streamed,
                validation,
                (
                    assistantRequest: request,
                    finalText: finalText,
                    responseDiagnostics: makeResponseDiagnostics(
                        request: request,
                        elevatedRequest: elevatedRequest,
                        streamedChunks: streamed.streamedChunks,
                        finalText: finalText,
                        stopReason: stopReason,
                        retryUsed: retryUsed,
                        validation: validation
                    ),
                    error: nil
                )
            )
        } catch {
            let stopReason: JarvisAssistantGenerationStopReason = (error as? JarvisOrchestrationError) == .cancelled
                ? .externalCancel
                : .unknown
            let validation = JarvisAssistantOutputValidationResult(
                status: .empty,
                normalizedText: "",
                failureDetail: normalizedGenerationFailure(error)
            )
            return (
                StreamedGenerationResult(
                    finalText: "",
                    streamedChunks: [],
                    stopReason: stopReason
                ),
                validation,
                (
                    assistantRequest: request,
                    finalText: "",
                    responseDiagnostics: makeResponseDiagnostics(
                        request: request,
                        elevatedRequest: elevatedRequest,
                        streamedChunks: [],
                        finalText: "",
                        stopReason: stopReason,
                        retryUsed: retryUsed,
                        validation: validation
                    ),
                    error: (error as? JarvisOrchestrationError) ?? .generationFailed(normalizedGenerationFailure(error))
                )
            )
        }
    }

    private func buildValidationFailureResult(
        orchestrationRequest: JarvisOrchestrationRequest,
        normalizedRequest: JarvisNormalizedAssistantRequest,
        plan: JarvisAssistantExecutionPlan,
        assistantRequest: JarvisAssistantRequest,
        elevatedRequest: JarvisElevatedRequest,
        finalText: String,
        streamedChunks: [String],
        validation: JarvisAssistantOutputValidationResult,
        retryUsed: Bool
    ) -> (
        assistantRequest: JarvisAssistantRequest,
        finalText: String,
        responseDiagnostics: JarvisAssistantResponseDiagnostics,
        error: JarvisOrchestrationError?
    ) {
        _ = normalizedRequest
        _ = orchestrationRequest
        _ = plan
        return (
            assistantRequest: assistantRequest,
            finalText: "",
            responseDiagnostics: makeResponseDiagnostics(
                request: assistantRequest,
                elevatedRequest: elevatedRequest,
                streamedChunks: streamedChunks,
                finalText: finalText,
                stopReason: .validationFailure,
                retryUsed: retryUsed,
                validation: validation
            ),
            error: .generationFailed(validation.failureDetail ?? "The model returned invalid output.")
        )
    }

    private func makeValidationRetryRequest(
        from request: JarvisAssistantRequest,
        elevatedRequest: JarvisElevatedRequest
    ) -> JarvisAssistantRequest {
        var retryRequest = request
        var retryTuning = retryRequest.tuning
        retryTuning.temperature = min(retryTuning.temperature, 0.32)
        retryTuning.topP = min(retryTuning.topP, 0.88)
        retryTuning.repeatPenalty = max(retryTuning.repeatPenalty, 1.12)
        retryTuning.penaltyLastN = max(retryTuning.penaltyLastN, 96)
        retryTuning.responseStyle = .balanced
        retryTuning.usesReasoningPlan = true
        retryRequest.tuning = retryTuning
        retryRequest.prompt = """
        \(stricterRetryInstruction(for: request.classification))

        User request:
        \(elevatedRequest.elevatedPrompt)
        """
        retryRequest.promptBlueprint = JarvisPromptBlueprint(
            systemInstruction: request.promptBlueprint.systemInstruction,
            assistantRole: request.promptBlueprint.assistantRole,
            taskTypeInstruction: request.promptBlueprint.taskTypeInstruction,
            responseInstruction: stricterRetryInstruction(for: request.classification),
            contextBlocks: request.promptBlueprint.contextBlocks,
            userInputPrefix: "User request:"
        )
        retryRequest.debugSummary = request.debugSummary + " retry=strict_validation"
        return retryRequest
    }

    private func stricterRetryInstruction(for classification: JarvisTaskClassification) -> String {
        switch classification.category {
        case .coding:
            return "Return a concrete coding answer. Include code or an explicit fix. Do not answer with punctuation, fragments, or placeholder text."
        case .planning:
            return "Return a usable plan with numbered steps and concrete next actions. Do not answer with punctuation, fragments, or placeholder text."
        case .draftingEmail, .draftingMessage, .contextAwareReply:
            return "Return ready-to-send text that reads complete and natural. Do not answer with punctuation, fragments, or placeholder text."
        default:
            return "Return a complete useful answer. Do not answer with punctuation, fragments, or placeholder text."
        }
    }

    private func makeResponseDiagnostics(
        request: JarvisAssistantRequest,
        elevatedRequest: JarvisElevatedRequest,
        streamedChunks: [String],
        finalText: String,
        stopReason: JarvisAssistantGenerationStopReason,
        retryUsed: Bool,
        validation: JarvisAssistantOutputValidationResult
    ) -> JarvisAssistantResponseDiagnostics {
        JarvisAssistantResponseDiagnostics(
            elevatedRequestType: elevatedRequest.kind.rawValue,
            promptPreview: String(request.prompt.prefix(240)),
            presetUsed: request.tuning.preset.rawValue,
            streamedChunks: streamedChunks,
            finalTextLength: finalText.count,
            stopReason: stopReason,
            retryUsed: retryUsed,
            validation: validation.status,
            validationDetail: validation.failureDetail
        )
    }

    private func mapStopReason(_ runtimeStopReason: JarvisRuntimeGenerationStopReason?) -> JarvisAssistantGenerationStopReason {
        guard let runtimeStopReason else { return .unknown }
        switch runtimeStopReason {
        case .eos:
            return .eos
        case .stopSequence:
            return .stopSequence
        case .maxTokens:
            return .maxTokens
        case .repetitionAbort:
            return .repetitionAbort
        case .memoryAbort:
            return .memoryAbort
        case .thermalAbort:
            return .thermalAbort
        case .externalCancel:
            return .externalCancel
        case .validationFailure:
            return .validationFailure
        case .unknown:
            return .unknown
        }
    }
}
