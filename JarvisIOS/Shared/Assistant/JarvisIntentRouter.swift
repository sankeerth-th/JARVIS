import Foundation

public enum JarvisIntentMode: String, Codable, Equatable, Sendable {
    case respond
    case action
    case clarify
    case workflow
}

public enum JarvisIntentValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case list([JarvisIntentValue])
    case object([String: JarvisIntentValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let list = try? container.decode([JarvisIntentValue].self) {
            self = .list(list)
        } else {
            self = .object(try container.decode([String: JarvisIntentValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .list(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct JarvisTypedIntent: Codable, Equatable, Sendable {
    public var mode: JarvisIntentMode
    public var intent: String
    public var confidence: Double
    public var arguments: [String: JarvisIntentValue]
    public var requiresConfirmation: Bool
    public var reasoningSummary: String

    public init(
        mode: JarvisIntentMode,
        intent: String,
        confidence: Double,
        arguments: [String: JarvisIntentValue] = [:],
        requiresConfirmation: Bool = false,
        reasoningSummary: String = ""
    ) {
        self.mode = mode
        self.intent = intent
        self.confidence = confidence
        self.arguments = arguments
        self.requiresConfirmation = requiresConfirmation
        self.reasoningSummary = reasoningSummary
    }
}

public enum JarvisModelLane: String, Codable, Equatable, Sendable {
    case localFast
    case remoteReasoning
}

public enum JarvisFallbackBehavior: String, Codable, Equatable, Sendable {
    case answerLocally
    case askForClarification
    case refuseUnsafeAction
    case retryWithRemote
}

public struct JarvisRouteDecision: Codable, Equatable, Sendable {
    public var typedIntent: JarvisTypedIntent
    public var selectedSkillID: String?
    public var lane: JarvisModelLane
    public var requiresConfirmation: Bool
    public var reason: String
    public var fallbackBehavior: JarvisFallbackBehavior

    public init(
        typedIntent: JarvisTypedIntent,
        selectedSkillID: String? = nil,
        lane: JarvisModelLane,
        requiresConfirmation: Bool = false,
        reason: String,
        fallbackBehavior: JarvisFallbackBehavior = .answerLocally
    ) {
        self.typedIntent = typedIntent
        self.selectedSkillID = selectedSkillID
        self.lane = lane
        self.requiresConfirmation = requiresConfirmation
        self.reason = reason
        self.fallbackBehavior = fallbackBehavior
    }
}

@MainActor
public final class JarvisIntentRouter {
    public init() {}

    public func route(
        request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest,
        skill: JarvisResolvedSkill
    ) -> JarvisRouteDecision {
        let typedIntent = makeTypedIntent(
            request: request,
            classification: classification,
            elevatedRequest: elevatedRequest
        )

        let lane: JarvisModelLane = {
            switch elevatedRequest.kind {
            case .planningRequest:
                return .remoteReasoning
            case .questionAnswering, .summarizationRequest:
                return request.prompt.count > 220 ? .remoteReasoning : .localFast
            case .codingRequest:
                return request.prompt.count > 320 ? .remoteReasoning : .localFast
            default:
                return .localFast
            }
        }()

        return JarvisRouteDecision(
            typedIntent: typedIntent,
            selectedSkillID: skill.skill.id,
            lane: lane,
            requiresConfirmation: typedIntent.requiresConfirmation,
            reason: elevatedRequest.elevatedIntent,
            fallbackBehavior: fallbackBehavior(for: elevatedRequest.kind)
        )
    }

    private func makeTypedIntent(
        request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        elevatedRequest: JarvisElevatedRequest
    ) -> JarvisTypedIntent {
        let mode: JarvisIntentMode
        switch elevatedRequest.kind {
        case .clarificationNeeded, .vaguePrompt:
            mode = .clarify
        case .planningRequest:
            mode = .workflow
        case .actionRequest, .deviceActionRequest, .appActionRequest, .searchRequest:
            mode = .action
        case .greeting, .questionAnswering, .draftRequest, .codingRequest, .summarizationRequest:
            mode = .respond
        }

        var arguments: [String: JarvisIntentValue] = [:]
        if request.requestedTask != .chat {
            arguments["requested_task"] = .string(request.requestedTask.rawValue)
        }
        arguments["classification"] = .string(classification.category.rawValue)
        if let replyTarget = request.replyTargetText, !replyTarget.isEmpty {
            arguments["reply_target"] = .string(replyTarget)
        }

        return JarvisTypedIntent(
            mode: mode,
            intent: elevatedRequest.elevatedIntent,
            confidence: classification.confidence,
            arguments: arguments,
            requiresConfirmation: requiresConfirmation(for: elevatedRequest.kind),
            reasoningSummary: elevatedRequest.responseContract.directAnswerFirst
                ? "Direct-answer contract"
                : "Contextual response contract"
        )
    }

    private func requiresConfirmation(for kind: JarvisElevatedRequestKind) -> Bool {
        switch kind {
        case .deviceActionRequest:
            return true
        default:
            return false
        }
    }

    private func fallbackBehavior(for kind: JarvisElevatedRequestKind) -> JarvisFallbackBehavior {
        switch kind {
        case .clarificationNeeded, .vaguePrompt:
            return .askForClarification
        case .deviceActionRequest, .appActionRequest:
            return .refuseUnsafeAction
        case .planningRequest:
            return .retryWithRemote
        default:
            return .answerLocally
        }
    }
}
