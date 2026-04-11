import Foundation

public protocol ExecutionPlanner {
    @MainActor
    func makePlan(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest,
        resolvedSkill: JarvisResolvedSkill
    ) async -> JarvisAssistantExecutionPlan
}

protocol JarvisExecutionPlanBuilding {
    @MainActor
    func makePlan(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest,
        routeDecision: JarvisRouteDecision?,
        policyDecision: JarvisPolicyDecision?,
        selectedModelLane: JarvisModelLane?,
        selectedSkillID: String?
    ) async -> JarvisAssistantExecutionPlan
}

@MainActor
public final class JarvisExecutionPlanner: JarvisExecutionPlanBuilding {
    private let capabilityProvider: JarvisAssistantCapabilityProviding
    private let responseStrategy: JarvisAssistantResponseStrategyProviding

    public init(
        capabilityProvider: JarvisAssistantCapabilityProviding = JarvisNullCapabilityProvider(),
        responseStrategy: JarvisAssistantResponseStrategyProviding = JarvisDefaultResponseStrategy()
    ) {
        self.capabilityProvider = capabilityProvider
        self.responseStrategy = responseStrategy
    }

    @MainActor
    public func makePlan(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest,
        routeDecision: JarvisRouteDecision? = nil,
        policyDecision: JarvisPolicyDecision? = nil,
        selectedModelLane: JarvisModelLane? = nil,
        selectedSkillID: String? = nil
    ) async -> JarvisAssistantExecutionPlan {
        let candidates = await capabilityProvider.candidates(for: request, classification: classification)
        let selectedCapability = selectedCapability(
            for: request,
            classification: classification,
            elevatedRequest: elevatedRequest,
            capabilityCandidates: candidates
        )
        let decision = decideMode(
            for: request,
            classification: classification,
            memoryContextAvailable: memoryContextAvailable,
            elevatedRequest: elevatedRequest,
            capabilityCandidates: candidates,
            selectedCapability: selectedCapability
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
            routeDecision: routeDecision,
            policyDecision: policyDecision,
            selectedModelLane: selectedModelLane,
            selectedCapabilityID: selectedCapability?.id,
            capabilityApprovalRequired: selectedCapability?.requiresApproval ?? false,
            capabilityPlatformAvailability: selectedCapability?.platformAvailability,
            steps: buildSteps(
                for: decision.mode,
                classification: classification,
                capabilityCandidates: candidates,
                selectedCapability: selectedCapability
            ),
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: decision.mode,
                selectedModelLane: selectedModelLane?.rawValue,
                policyReason: policyDecision?.reason,
                chosenSkillID: selectedSkillID,
                reasoning: decision.reasons + ["Elevated request: \(elevatedRequest.kind.rawValue) (\(elevatedRequest.elevatedIntent))"],
                usedExistingPromptPipeline: decision.usesExistingPromptPipeline,
                usedFallbackDirectResponse: decision.usedFallbackDirectResponse,
                memoryAugmentationAvailable: memoryContextAvailable,
                capabilityCandidates: capabilityDiagnostics(candidates: candidates, selectedCapability: selectedCapability)
            )
        )
    }

    private func decideMode(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest,
        capabilityCandidates: [JarvisAssistantCapabilityCandidate],
        selectedCapability: SelectedCapability?
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

        if let selectedCapability, request.executionPreferences.allowCapabilityExecution {
            reasons.append("Planner matched the request to capability \(selectedCapability.id.rawValue), so the turn should route through capability execution instead of generic generation.")
            return Decision(mode: selectedCapability.mode, reasons: reasons, usesExistingPromptPipeline: selectedCapability.mode == .capabilityThenRespond, usedFallbackDirectResponse: false)
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
        capabilityCandidates: [JarvisAssistantCapabilityCandidate],
        selectedCapability: SelectedCapability?
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
            let detail: String
            if let selectedCapability {
                detail = "Reserve capability execution for \(selectedCapability.id.rawValue)\(mode == .capabilityAction ? " and stop before generic generation." : " before generating the response.")."
            } else if capabilityCandidates.isEmpty {
                detail = "Reserve a capability stage for later threads without executing any actions yet."
            } else {
                detail = "Reserve a capability stage for \(capabilityCandidates.map(\.name).joined(separator: ", "))\(mode == .capabilityAction ? " and stop before generic generation." : " before generating the response.")."
            }
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

    private func capabilityDiagnostics(
        candidates: [JarvisAssistantCapabilityCandidate],
        selectedCapability: SelectedCapability?
    ) -> [String] {
        var values = candidates.map(\.name)
        if let selectedCapability {
            values.insert(selectedCapability.id.rawValue, at: 0)
        }
        return values
    }

    private func selectedCapability(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest,
        capabilityCandidates: [JarvisAssistantCapabilityCandidate]
    ) -> SelectedCapability? {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedPrompt = prompt.lowercased()

        if elevatedRequest.capabilityHint == .searchKnowledge || capabilityCandidates.contains(where: { $0.kind == .searchKnowledge }) {
            return SelectedCapability(
                id: "knowledge.lookup",
                requiresApproval: false,
                platformAvailability: .shared,
                mode: .capabilityAction
            )
        }

        if lowercasedPrompt.contains("search files")
            || lowercasedPrompt.contains("search my files")
            || lowercasedPrompt.contains("find file")
            || lowercasedPrompt.contains("find files")
            || lowercasedPrompt.contains("grep") {
            return SelectedCapability(
                id: "file.search",
                requiresApproval: false,
                platformAvailability: .shared,
                mode: .capabilityAction
            )
        }

        if lowercasedPrompt.contains("analyze project")
            || lowercasedPrompt.contains("analyze repo")
            || lowercasedPrompt.contains("analyze codebase") {
            return SelectedCapability(
                id: "project.analyze",
                requiresApproval: false,
                platformAvailability: .shared,
                mode: .capabilityAction
            )
        }

        if lowercasedPrompt.contains("open project"), extractPath(from: prompt) != nil {
            return SelectedCapability(
                id: "project.open",
                requiresApproval: false,
                platformAvailability: .macOSOnly,
                mode: .capabilityAction
            )
        }

        if lowercasedPrompt.contains("create project")
            || lowercasedPrompt.contains("scaffold project")
            || lowercasedPrompt.contains("new xcode project") {
            return SelectedCapability(
                id: "project.scaffold",
                requiresApproval: true,
                platformAvailability: .shared,
                mode: .capabilityThenRespond
            )
        }

        if (lowercasedPrompt.contains("preview file") || lowercasedPrompt.contains("preview "))
            && extractPath(from: prompt) != nil {
            return SelectedCapability(
                id: "file.preview",
                requiresApproval: false,
                platformAvailability: .shared,
                mode: .capabilityAction
            )
        }

        if (lowercasedPrompt.contains("read file")
            || lowercasedPrompt.contains("open file")
            || lowercasedPrompt.contains("show file")
            || lowercasedPrompt.contains("view file"))
            && extractPath(from: prompt) != nil {
            return SelectedCapability(
                id: "file.read",
                requiresApproval: false,
                platformAvailability: .shared,
                mode: .capabilityAction
            )
        }

        if (lowercasedPrompt.contains("patch file")
            || lowercasedPrompt.contains("apply patch")
            || lowercasedPrompt.contains("edit file")
            || lowercasedPrompt.contains("change file"))
            && extractPath(from: prompt) != nil {
            return SelectedCapability(
                id: "file.patch",
                requiresApproval: true,
                platformAvailability: .shared,
                mode: .capabilityAction
            )
        }

        if (lowercasedPrompt.contains("create file")
            || lowercasedPrompt.contains("new file"))
            && extractPath(from: prompt) != nil {
            return SelectedCapability(
                id: "file.create",
                requiresApproval: true,
                platformAvailability: .shared,
                mode: .capabilityAction
            )
        }

        if let url = extractURL(from: prompt), lowercasedPrompt.contains("open ") {
            _ = url
            return SelectedCapability(
                id: "system.open_url",
                requiresApproval: false,
                platformAvailability: .macOSOnly,
                mode: .capabilityAction
            )
        }

        if lowercasedPrompt.contains("show in finder") || lowercasedPrompt.contains("reveal in finder") {
            return SelectedCapability(
                id: "finder.reveal",
                requiresApproval: false,
                platformAvailability: .macOSOnly,
                mode: .capabilityAction
            )
        }

        if lowercasedPrompt.contains("focus ")
            || lowercasedPrompt.contains("switch to ") {
            return SelectedCapability(
                id: "app.focus",
                requiresApproval: false,
                platformAvailability: .macOSOnly,
                mode: .capabilityAction
            )
        }

        if lowercasedPrompt.contains("open ")
            && classification.category != .questionAnswering
            && extractURL(from: prompt) == nil {
            return SelectedCapability(
                id: "app.open",
                requiresApproval: false,
                platformAvailability: .macOSOnly,
                mode: .capabilityAction
            )
        }

        return nil
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
}

@MainActor
public struct JarvisExecutionPlannerAdapter: ExecutionPlanner {
    private let planner: any JarvisExecutionPlanBuilding
    private let intentRouter: JarvisIntentRouter
    private let policyEngine: JarvisPolicyEngine
    private let modelRouter: JarvisModelRouter

    @MainActor
    init(
        planner: (any JarvisExecutionPlanBuilding)? = nil,
        intentRouter: JarvisIntentRouter? = nil,
        policyEngine: JarvisPolicyEngine? = nil,
        modelRouter: JarvisModelRouter? = nil
    ) {
        self.planner = planner ?? JarvisExecutionPlanner()
        self.intentRouter = intentRouter ?? JarvisIntentRouter()
        self.policyEngine = policyEngine ?? JarvisPolicyEngine()
        self.modelRouter = modelRouter ?? JarvisModelRouter()
    }

    @MainActor
    public func makePlan(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest,
        resolvedSkill: JarvisResolvedSkill
    ) async -> JarvisAssistantExecutionPlan {
        let routeDecision = intentRouter.route(
            request: request,
            classification: classification,
            elevatedRequest: elevatedRequest,
            skill: resolvedSkill
        )
        let policyDecision = policyEngine.evaluate(routeDecision)
        let selectedModelLane = modelRouter.lane(for: routeDecision, request: request)

        return await planner.makePlan(
            for: request,
            classification: classification,
            memoryContextAvailable: memoryContextAvailable,
            elevatedRequest: elevatedRequest,
            routeDecision: routeDecision,
            policyDecision: policyDecision,
            selectedModelLane: selectedModelLane,
            selectedSkillID: resolvedSkill.skill.id
        )
    }
}

private struct Decision {
    let mode: JarvisAssistantExecutionMode
    let reasons: [String]
    let usesExistingPromptPipeline: Bool
    let usedFallbackDirectResponse: Bool
}

private struct SelectedCapability {
    let id: CapabilityID
    let requiresApproval: Bool
    let platformAvailability: CapabilityPlatformAvailability
    let mode: JarvisAssistantExecutionMode
}
