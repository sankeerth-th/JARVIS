import Foundation

@MainActor
public final class JarvisExecutionPlanner {
    private let capabilityProvider: JarvisAssistantCapabilityProviding
    private let responseStrategy: JarvisAssistantResponseStrategyProviding

    public init(
        capabilityProvider: JarvisAssistantCapabilityProviding = JarvisNullCapabilityProvider(),
        responseStrategy: JarvisAssistantResponseStrategyProviding = JarvisDefaultResponseStrategy()
    ) {
        self.capabilityProvider = capabilityProvider
        self.responseStrategy = responseStrategy
    }

    public func makePlan(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest
    ) async -> JarvisAssistantExecutionPlan {
        let candidates = await capabilityProvider.candidates(for: request, classification: classification)
        let decision = decideMode(
            for: request,
            classification: classification,
            memoryContextAvailable: memoryContextAvailable,
            elevatedRequest: elevatedRequest,
            capabilityCandidates: candidates
        )
        let deliveryMode = responseStrategy.deliveryMode(
            for: request,
            classification: classification,
            executionMode: decision.mode
        )

        return JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: classification.task,
            classification: classification,
            elevatedRequest: elevatedRequest,
            mode: decision.mode,
            responseStyle: request.assistantMode.defaultResponseStyle,
            deliveryMode: deliveryMode,
            steps: buildSteps(
                for: decision.mode,
                classification: classification,
                capabilityCandidates: candidates
            ),
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: decision.mode,
                reasoning: decision.reasons + ["Elevated request: \(elevatedRequest.kind.rawValue) (\(elevatedRequest.elevatedIntent))"],
                usedExistingPromptPipeline: decision.usesExistingPromptPipeline,
                usedFallbackDirectResponse: decision.usedFallbackDirectResponse,
                memoryAugmentationAvailable: memoryContextAvailable,
                capabilityCandidates: candidates.map(\.name)
            )
        )
    }

    private func decideMode(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest,
        capabilityCandidates: [JarvisAssistantCapabilityCandidate]
    ) -> Decision {
        var reasons: [String] = []
        var fallbackToDirectResponse = false

        if request.sourceKind == .visual || request.requestedTask == .visualDescribe {
            reasons.append("Request entered through the visual path, so the orchestration plan preserves the visual route.")
            return Decision(mode: .visualRoute, reasons: reasons, usesExistingPromptPipeline: true, usedFallbackDirectResponse: false)
        }

        switch elevatedRequest.kind {
        case .deviceActionRequest:
            reasons.append("Device action intent was detected, so the request stops at capability routing instead of generic text generation.")
            return Decision(mode: .capabilityAction, reasons: reasons, usesExistingPromptPipeline: false, usedFallbackDirectResponse: false)
        case .appActionRequest:
            reasons.append("App action intent was detected, so the request is routed through capability handling before any response is generated.")
            return Decision(mode: .capabilityAction, reasons: reasons, usesExistingPromptPipeline: false, usedFallbackDirectResponse: false)
        case .searchRequest:
            reasons.append("Search intent was detected, so the request routes through the search capability instead of free-form guessing.")
            return Decision(mode: .capabilityAction, reasons: reasons, usesExistingPromptPipeline: false, usedFallbackDirectResponse: false)
        case .planningRequest:
            reasons.append("Planning intent was detected, so the assistant should produce a plan-first response.")
            return Decision(mode: .planOnly, reasons: reasons, usesExistingPromptPipeline: true, usedFallbackDirectResponse: false)
        default:
            break
        }

        if shouldClarify(request: request, classification: classification) {
            reasons.append("Prompt is too short or ambiguous for a direct answer, so the assistant should clarify before taking a stronger action path.")
            return Decision(mode: .clarify, reasons: reasons, usesExistingPromptPipeline: true, usedFallbackDirectResponse: false)
        }

        if !capabilityCandidates.isEmpty && request.executionPreferences.allowCapabilityExecution {
            if capabilityCandidates.contains(where: { $0.kind == .draftEmail }) {
                reasons.append("Draft email capability was detected, so the request reserves a drafting capability stage before finalizing the response.")
                return Decision(mode: .capabilityThenRespond, reasons: reasons, usesExistingPromptPipeline: true, usedFallbackDirectResponse: false)
            }
        }

        if request.assistantMode == .plan || classification.category == .planning {
            reasons.append("Planning intent was detected, so the assistant should produce a plan-first response.")
            return Decision(mode: .planOnly, reasons: reasons, usesExistingPromptPipeline: true, usedFallbackDirectResponse: false)
        }

        if memoryContextAvailable && request.executionPreferences.allowMemoryAugmentation {
            reasons.append("Conversation history is available, so the request should be treated as a memory-augmented response rather than a stateless chat turn.")
            return Decision(mode: .memoryAugmentedResponse, reasons: reasons, usesExistingPromptPipeline: true, usedFallbackDirectResponse: false)
        }

        if classification.task != request.requestedTask {
            fallbackToDirectResponse = true
            reasons.append("Classifier changed the task from the raw request, but the current implementation still answers through the prompt pipeline while preserving the detected task.")
        } else {
            reasons.append("No special execution path was required, so the request stays on the direct response path.")
        }

        return Decision(
            mode: .directResponse,
            reasons: reasons,
            usesExistingPromptPipeline: true,
            usedFallbackDirectResponse: fallbackToDirectResponse
        )
    }

    private func shouldClarify(
        request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) -> Bool {
        guard request.requestedTask == .chat else { return false }
        guard request.conversation.messages.isEmpty else { return false }
        guard request.replyTargetText == nil else { return false }

        let normalized = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count < 10 {
            return true
        }

        let wordCount = normalized.split(whereSeparator: \.isWhitespace).count
        return wordCount <= 2 && classification.confidence < 0.55
    }

    private func buildSteps(
        for mode: JarvisAssistantExecutionMode,
        classification: JarvisTaskClassification,
        capabilityCandidates: [JarvisAssistantCapabilityCandidate]
    ) -> [JarvisAssistantExecutionStep] {
        var steps: [JarvisAssistantExecutionStep] = [
            JarvisAssistantExecutionStep(
                kind: .normalizeRequest,
                title: "Normalize Request",
                detail: "Capture invocation metadata, route context, and placeholders for future attachments and execution preferences.",
                usesModel: false
            ),
            JarvisAssistantExecutionStep(
                kind: .classifyIntent,
                title: "Classify Intent",
                detail: "Map the raw input onto a concrete assistant task and preset using the existing intelligence layer.",
                usesModel: false
            ),
            JarvisAssistantExecutionStep(
                kind: .chooseMode,
                title: "Choose Execution Mode",
                detail: "Select the execution path for this turn before prompt assembly.",
                usesModel: false
            )
        ]

        if mode == .memoryAugmentedResponse {
            steps.append(
                JarvisAssistantExecutionStep(
                    kind: .consultMemory,
                    title: "Consult Memory",
                    detail: "Use recent conversation context to keep the response stateful without introducing persistent memory yet.",
                    usesModel: false
                )
            )
        }

        if mode == .capabilityAction || mode == .capabilityThenRespond {
            let detail = capabilityCandidates.isEmpty
                ? "Reserve a capability stage for later threads without executing any actions yet."
                : "Reserve a capability stage for \(capabilityCandidates.map(\.name).joined(separator: ", "))\(mode == .capabilityAction ? " and stop before generic generation." : " before generating the response.")."
            steps.append(
                JarvisAssistantExecutionStep(
                    kind: .inspectCapabilities,
                    title: "Inspect Capabilities",
                    detail: detail,
                    usesModel: false
                )
            )
        }

        if mode == .capabilityAction {
            steps.append(
                JarvisAssistantExecutionStep(
                    kind: .finalizeTurn,
                    title: "Finalize Routed Turn",
                    detail: "Return a structured fallback or routed action result without calling the model.",
                    usesModel: false
                )
            )
            return steps
        }

        steps.append(contentsOf: [
            JarvisAssistantExecutionStep(
                kind: .buildContext,
                title: "Build Context",
                detail: "Assemble prompt context blocks for \(classification.category.displayName.lowercased()) with the current conversation and knowledge inputs.",
                usesModel: false
            ),
            JarvisAssistantExecutionStep(
                kind: .preparePrompt,
                title: "Prepare Prompt",
                detail: "Construct the final assistant request and tuning envelope for the selected mode.",
                usesModel: false
            ),
            JarvisAssistantExecutionStep(
                kind: .warmRuntime,
                title: "Warm Runtime",
                detail: "Ensure the selected local model is ready before inference.",
                usesModel: false
            ),
            JarvisAssistantExecutionStep(
                kind: .infer,
                title: "Generate Response",
                detail: "Stream the assistant response through the runtime using the existing prompt pipeline.",
                usesModel: true
            ),
            JarvisAssistantExecutionStep(
                kind: .finalizeTurn,
                title: "Finalize Turn",
                detail: "Package the response, suggestions, and diagnostics into a UI-consumable assistant turn result.",
                usesModel: false
            )
        ])

        return steps
    }
}

private struct Decision {
    let mode: JarvisAssistantExecutionMode
    let reasons: [String]
    let usesExistingPromptPipeline: Bool
    let usedFallbackDirectResponse: Bool
}
