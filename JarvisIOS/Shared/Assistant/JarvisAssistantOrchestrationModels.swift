import Foundation

public enum JarvisAssistantInvocationSourceKind: String, Codable, Equatable {
    case chat
    case voice
    case shortcut
    case visual
    case knowledge
    case settings
    case deepLink
    case inApp
    case unknown

    public init(source: String, route: JarvisAssistantEntryRoute?) {
        if let entrySource = JarvisAssistantEntrySource(rawValue: source) {
            switch entrySource {
            case .shortcut:
                self = .shortcut
                return
            case .deepLink:
                self = .deepLink
                return
            case .settings:
                self = .settings
                return
            case .inApp, .legacy, .normalLaunch:
                break
            }
        }

        switch route {
        case .voice:
            self = .voice
        case .visual:
            self = .visual
        case .knowledge:
            self = .knowledge
        case .assistant, .chat, .draftReply, .continueConversation, .systemAssistant:
            self = .chat
        case .none:
            self = .unknown
        }
    }
}

public struct JarvisAssistantRouteContext: Equatable, Codable {
    public let tabIdentifier: String
    public let entryRouteIdentifier: String
    public let entryStyleIdentifier: String
    public let isFocusedExperience: Bool
    public let shouldFocusComposer: Bool

    public init(
        tabIdentifier: String = "assistant",
        entryRouteIdentifier: String = JarvisAssistantEntryRoute.assistant.rawValue,
        entryStyleIdentifier: String = "standard",
        isFocusedExperience: Bool = false,
        shouldFocusComposer: Bool = true
    ) {
        self.tabIdentifier = tabIdentifier
        self.entryRouteIdentifier = entryRouteIdentifier
        self.entryStyleIdentifier = entryStyleIdentifier
        self.isFocusedExperience = isFocusedExperience
        self.shouldFocusComposer = shouldFocusComposer
    }
}

public struct JarvisAssistantAttachmentPlaceholder: Equatable, Codable, Identifiable {
    public enum Kind: String, Codable, Equatable {
        case image
        case document
        case audio
        case unknown
    }

    public let id: UUID
    public let kind: Kind
    public let name: String
    public let mimeType: String?

    public init(id: UUID = UUID(), kind: Kind, name: String, mimeType: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.mimeType = mimeType
    }
}

public enum JarvisAssistantDeliveryMode: String, Codable, Equatable {
    case streamingText
    case structuredCard
    case statusOnly
}

public struct JarvisAssistantExecutionPreferences: Equatable, Codable {
    public var preferredDeliveryMode: JarvisAssistantDeliveryMode?
    public var prefersStructuredOutput: Bool?
    public var allowCapabilityExecution: Bool
    public var allowMemoryAugmentation: Bool

    public init(
        preferredDeliveryMode: JarvisAssistantDeliveryMode? = nil,
        prefersStructuredOutput: Bool? = nil,
        allowCapabilityExecution: Bool = true,
        allowMemoryAugmentation: Bool = true
    ) {
        self.preferredDeliveryMode = preferredDeliveryMode
        self.prefersStructuredOutput = prefersStructuredOutput
        self.allowCapabilityExecution = allowCapabilityExecution
        self.allowMemoryAugmentation = allowMemoryAugmentation
    }
}

public struct JarvisNormalizedAssistantRequest: Equatable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let prompt: String
    public let requestedTask: JarvisAssistantTask
    public let invocationSource: String
    public let sourceKind: JarvisAssistantInvocationSourceKind
    public let assistantMode: JarvisAssistantMode
    public let conversationID: UUID
    public let conversation: JarvisConversationRecord
    public let routeContext: JarvisAssistantRouteContext
    public let knowledgeResults: [JarvisKnowledgeResult]
    public let replyTargetText: String?
    public let attachments: [JarvisAssistantAttachmentPlaceholder]
    public let executionPreferences: JarvisAssistantExecutionPreferences
    public let inputMode: String
    public let settingsSnapshot: JarvisAssistantSettings

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        prompt: String,
        requestedTask: JarvisAssistantTask,
        invocationSource: String,
        sourceKind: JarvisAssistantInvocationSourceKind,
        assistantMode: JarvisAssistantMode,
        conversationID: UUID,
        conversation: JarvisConversationRecord,
        routeContext: JarvisAssistantRouteContext,
        knowledgeResults: [JarvisKnowledgeResult] = [],
        replyTargetText: String? = nil,
        attachments: [JarvisAssistantAttachmentPlaceholder] = [],
        executionPreferences: JarvisAssistantExecutionPreferences = .init(),
        inputMode: String = "text",
        settingsSnapshot: JarvisAssistantSettings = .default
    ) {
        self.id = id
        self.createdAt = createdAt
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requestedTask = requestedTask
        self.invocationSource = invocationSource
        self.sourceKind = sourceKind
        self.assistantMode = assistantMode
        self.conversationID = conversationID
        self.conversation = conversation
        self.routeContext = routeContext
        self.knowledgeResults = knowledgeResults
        self.replyTargetText = replyTargetText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.attachments = attachments
        self.executionPreferences = executionPreferences
        self.inputMode = inputMode
        self.settingsSnapshot = settingsSnapshot
    }
}

public enum JarvisAssistantExecutionMode: String, Codable, Equatable {
    case directResponse
    case clarify
    case planOnly
    case memoryAugmentedResponse
    case capabilityAction
    case capabilityThenRespond
    case visualRoute
}

public enum JarvisAssistantExecutionStepKind: String, Codable, Equatable {
    case normalizeRequest
    case classifyIntent
    case chooseMode
    case consultMemory
    case inspectCapabilities
    case buildContext
    case preparePrompt
    case warmRuntime
    case infer
    case finalizeTurn
}

public struct JarvisAssistantExecutionStep: Equatable, Identifiable {
    public let id: UUID
    public let kind: JarvisAssistantExecutionStepKind
    public let title: String
    public let detail: String
    public let usesModel: Bool

    public init(
        id: UUID = UUID(),
        kind: JarvisAssistantExecutionStepKind,
        title: String,
        detail: String,
        usesModel: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.usesModel = usesModel
    }
}

public struct JarvisAssistantDecisionTrace: Equatable, Codable {
    public let selectedMode: JarvisAssistantExecutionMode
    public let selectedModelLane: String?
    public let policyReason: String?
    public let chosenSkillID: String?
    public let reasoning: [String]
    public let usedExistingPromptPipeline: Bool
    public let usedFallbackDirectResponse: Bool
    public let memoryAugmentationAvailable: Bool
    public let capabilityCandidates: [String]

    public init(
        selectedMode: JarvisAssistantExecutionMode,
        selectedModelLane: String? = nil,
        policyReason: String? = nil,
        chosenSkillID: String? = nil,
        reasoning: [String] = [],
        usedExistingPromptPipeline: Bool = true,
        usedFallbackDirectResponse: Bool = false,
        memoryAugmentationAvailable: Bool = false,
        capabilityCandidates: [String] = []
    ) {
        self.selectedMode = selectedMode
        self.selectedModelLane = selectedModelLane
        self.policyReason = policyReason
        self.chosenSkillID = chosenSkillID
        self.reasoning = reasoning
        self.usedExistingPromptPipeline = usedExistingPromptPipeline
        self.usedFallbackDirectResponse = usedFallbackDirectResponse
        self.memoryAugmentationAvailable = memoryAugmentationAvailable
        self.capabilityCandidates = capabilityCandidates
    }
}

public struct JarvisAssistantExecutionPlan: Equatable, Identifiable {
    public let id: UUID
    public let request: JarvisNormalizedAssistantRequest
    public let detectedTask: JarvisAssistantTask
    public let classification: JarvisTaskClassification
    public let elevatedRequest: JarvisElevatedRequest
    public let mode: JarvisAssistantExecutionMode
    public let responseStyle: JarvisAssistantResponseStyle
    public let deliveryMode: JarvisAssistantDeliveryMode
    public let routeDecision: JarvisRouteDecision?
    public let policyDecision: JarvisPolicyDecision?
    public let selectedModelLane: JarvisModelLane?
    public let selectedCapabilityID: CapabilityID?
    public let capabilityApprovalRequired: Bool
    public let capabilityPlatformAvailability: CapabilityPlatformAvailability?
    public let steps: [JarvisAssistantExecutionStep]
    public let diagnostics: JarvisAssistantDecisionTrace

    public init(
        id: UUID = UUID(),
        request: JarvisNormalizedAssistantRequest,
        detectedTask: JarvisAssistantTask,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest,
        mode: JarvisAssistantExecutionMode,
        responseStyle: JarvisAssistantResponseStyle,
        deliveryMode: JarvisAssistantDeliveryMode,
        routeDecision: JarvisRouteDecision? = nil,
        policyDecision: JarvisPolicyDecision? = nil,
        selectedModelLane: JarvisModelLane? = nil,
        selectedCapabilityID: CapabilityID? = nil,
        capabilityApprovalRequired: Bool = false,
        capabilityPlatformAvailability: CapabilityPlatformAvailability? = nil,
        steps: [JarvisAssistantExecutionStep],
        diagnostics: JarvisAssistantDecisionTrace
    ) {
        self.id = id
        self.request = request
        self.detectedTask = detectedTask
        self.classification = classification
        self.elevatedRequest = elevatedRequest
        self.mode = mode
        self.responseStyle = responseStyle
        self.deliveryMode = deliveryMode
        self.routeDecision = routeDecision
        self.policyDecision = policyDecision
        self.selectedModelLane = selectedModelLane
        self.selectedCapabilityID = selectedCapabilityID
        self.capabilityApprovalRequired = capabilityApprovalRequired
        self.capabilityPlatformAvailability = capabilityPlatformAvailability
        self.steps = steps
        self.diagnostics = diagnostics
    }
}

public struct JarvisAssistantMemoryAugmentation: Equatable {
    public let supplementalContext: [JarvisPromptContextBlock]
    public let summary: String?

    public init(
        supplementalContext: [JarvisPromptContextBlock] = [],
        summary: String? = nil
    ) {
        self.supplementalContext = supplementalContext
        self.summary = summary
    }

    public static let none = JarvisAssistantMemoryAugmentation()
}

public struct JarvisAssistantCapabilityCandidate: Equatable, Identifiable {
    public enum Kind: String, Codable, Equatable {
        case screenshot
        case openRoute
        case searchKnowledge
        case draftEmail
        case saveContent
        case copyContent
        case newChat
        case generic
    }

    public enum Availability: String, Codable, Equatable {
        case placeholder
        case available
    }

    public let id: UUID
    public let name: String
    public let summary: String
    public let kind: Kind
    public let availability: Availability

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        kind: Kind = .generic,
        availability: Availability = .placeholder
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.kind = kind
        self.availability = availability
    }
}

public protocol JarvisAssistantMemoryProviding {
    func augmentation(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) async -> JarvisAssistantMemoryAugmentation
}

public protocol JarvisAssistantCapabilityProviding {
    func candidates(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) async -> [JarvisAssistantCapabilityCandidate]
}

public protocol JarvisAssistantResponseStrategyProviding {
    func deliveryMode(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        executionMode: JarvisAssistantExecutionMode
    ) -> JarvisAssistantDeliveryMode
}

public struct JarvisAssistantTurnResult: Equatable {
    public let request: JarvisNormalizedAssistantRequest
    public let plan: JarvisAssistantExecutionPlan
    public let assistantRequest: JarvisAssistantRequest?
    public let responseText: String
    public let capabilitySurfaces: [JarvisAssistantCapabilitySurface]
    public let suggestions: [JarvisAssistantSuggestionDescriptor]
    public let deliveryMode: JarvisAssistantDeliveryMode
    public let diagnostics: JarvisAssistantDecisionTrace
    public let messageAttribution: JarvisMessageMemoryAttribution
    let capabilityState: CapabilityExecutionState?
    public let responseDiagnostics: JarvisAssistantResponseDiagnostics
    public let error: JarvisOrchestrationError?
    var executionTrace: ExecutionTrace?

    public var requestID: UUID {
        request.id
    }

    init(
        request: JarvisNormalizedAssistantRequest,
        plan: JarvisAssistantExecutionPlan,
        assistantRequest: JarvisAssistantRequest?,
        responseText: String,
        capabilitySurfaces: [JarvisAssistantCapabilitySurface] = [],
        suggestions: [JarvisAssistantSuggestionDescriptor] = [],
        deliveryMode: JarvisAssistantDeliveryMode,
        diagnostics: JarvisAssistantDecisionTrace,
        messageAttribution: JarvisMessageMemoryAttribution = .init(),
        capabilityState: CapabilityExecutionState? = nil,
        responseDiagnostics: JarvisAssistantResponseDiagnostics = .empty,
        error: JarvisOrchestrationError? = nil
    ) {
        self.request = request
        self.plan = plan
        self.assistantRequest = assistantRequest
        self.responseText = responseText
        self.capabilitySurfaces = capabilitySurfaces
        self.suggestions = suggestions
        self.deliveryMode = deliveryMode
        self.diagnostics = diagnostics
        self.messageAttribution = messageAttribution
        self.capabilityState = capabilityState
        self.responseDiagnostics = responseDiagnostics
        self.error = error
        self.executionTrace = nil
    }

    public func finalizedResponseText(
        fallbackStreamingText: String = "",
        runtimeStreamingText: String = ""
    ) -> String {
        [responseText, fallbackStreamingText, runtimeStreamingText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}

public struct JarvisAssistantResponseDiagnostics: Equatable, Codable {
    public let elevatedRequestType: String
    public let promptPreview: String
    public let presetUsed: String
    public let streamedChunks: [String]
    public let finalTextLength: Int
    public let stopReason: JarvisAssistantGenerationStopReason
    public let retryUsed: Bool
    public let validation: JarvisAssistantOutputValidationStatus
    public let validationDetail: String?

    public init(
        elevatedRequestType: String,
        promptPreview: String,
        presetUsed: String,
        streamedChunks: [String],
        finalTextLength: Int,
        stopReason: JarvisAssistantGenerationStopReason,
        retryUsed: Bool,
        validation: JarvisAssistantOutputValidationStatus,
        validationDetail: String? = nil
    ) {
        self.elevatedRequestType = elevatedRequestType
        self.promptPreview = promptPreview
        self.presetUsed = presetUsed
        self.streamedChunks = streamedChunks
        self.finalTextLength = finalTextLength
        self.stopReason = stopReason
        self.retryUsed = retryUsed
        self.validation = validation
        self.validationDetail = validationDetail
    }

    public static let empty = JarvisAssistantResponseDiagnostics(
        elevatedRequestType: "",
        promptPreview: "",
        presetUsed: "",
        streamedChunks: [],
        finalTextLength: 0,
        stopReason: .unknown,
        retryUsed: false,
        validation: .empty,
        validationDetail: nil
    )
}

public struct JarvisNullMemoryProvider: JarvisAssistantMemoryProviding {
    public init() {}

    public func augmentation(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) async -> JarvisAssistantMemoryAugmentation {
        _ = request
        _ = classification
        return .none
    }
}

public struct JarvisNullCapabilityProvider: JarvisAssistantCapabilityProviding {
    public init() {}

    public func candidates(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) async -> [JarvisAssistantCapabilityCandidate] {
        _ = request
        _ = classification
        return []
    }
}

public struct JarvisDefaultResponseStrategy: JarvisAssistantResponseStrategyProviding {
    public init() {}

    public func deliveryMode(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        executionMode: JarvisAssistantExecutionMode
    ) -> JarvisAssistantDeliveryMode {
        if let preferred = request.executionPreferences.preferredDeliveryMode {
            return preferred
        }

        if classification.shouldPreferStructuredOutput && executionMode != .clarify {
            return .structuredCard
        }

        return .streamingText
    }
}
