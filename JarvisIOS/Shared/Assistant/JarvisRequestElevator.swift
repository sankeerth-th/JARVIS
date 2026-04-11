import Foundation

public enum JarvisElevatedRequestKind: String, Codable, Equatable {
    case greeting
    case questionAnswering
    case actionRequest
    case draftRequest
    case codingRequest
    case summarizationRequest
    case planningRequest
    case deviceActionRequest
    case appActionRequest
    case searchRequest
    case vaguePrompt
    case clarificationNeeded
}

public struct JarvisResponseContract: Equatable, Codable {
    public let maxSentences: Int?
    public let asksSingleQuestion: Bool
    public let prefersChecklist: Bool
    public let directAnswerFirst: Bool
    public let avoidRoboticFiller: Bool
    public let prefersCodeFirst: Bool
    public let prefersRunnableOutput: Bool
    public let prefersReadyToSend: Bool
    public let prefersMinimalExplanation: Bool
    public let forbidsHallucinatedCompletion: Bool

    public init(
        maxSentences: Int? = nil,
        asksSingleQuestion: Bool = false,
        prefersChecklist: Bool = false,
        directAnswerFirst: Bool = false,
        avoidRoboticFiller: Bool = true,
        prefersCodeFirst: Bool = false,
        prefersRunnableOutput: Bool = false,
        prefersReadyToSend: Bool = false,
        prefersMinimalExplanation: Bool = false,
        forbidsHallucinatedCompletion: Bool = false
    ) {
        self.maxSentences = maxSentences
        self.asksSingleQuestion = asksSingleQuestion
        self.prefersChecklist = prefersChecklist
        self.directAnswerFirst = directAnswerFirst
        self.avoidRoboticFiller = avoidRoboticFiller
        self.prefersCodeFirst = prefersCodeFirst
        self.prefersRunnableOutput = prefersRunnableOutput
        self.prefersReadyToSend = prefersReadyToSend
        self.prefersMinimalExplanation = prefersMinimalExplanation
        self.forbidsHallucinatedCompletion = forbidsHallucinatedCompletion
    }
}

public struct JarvisElevatedRequest: Equatable {
    public let kind: JarvisElevatedRequestKind
    public let elevatedIntent: String
    public let elevatedPrompt: String
    public let responseContract: JarvisResponseContract
    public let platformResponse: String?
    public let clarificationQuestion: String?
    public let prefersSafePrompt: Bool
    public let capabilityHint: JarvisAssistantCapabilityCandidate.Kind?

    public init(
        kind: JarvisElevatedRequestKind,
        elevatedIntent: String,
        elevatedPrompt: String,
        responseContract: JarvisResponseContract,
        platformResponse: String? = nil,
        clarificationQuestion: String? = nil,
        prefersSafePrompt: Bool = false,
        capabilityHint: JarvisAssistantCapabilityCandidate.Kind? = nil
    ) {
        self.kind = kind
        self.elevatedIntent = elevatedIntent
        self.elevatedPrompt = elevatedPrompt
        self.responseContract = responseContract
        self.platformResponse = platformResponse
        self.clarificationQuestion = clarificationQuestion
        self.prefersSafePrompt = prefersSafePrompt
        self.capabilityHint = capabilityHint
    }
}

@MainActor
public final class JarvisRequestElevator {
    public init() {}

    public func elevate(
        prompt: String,
        requestedTask: JarvisAssistantTask,
        classification: JarvisTaskClassification
    ) -> JarvisElevatedRequest {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        if let greeting = greetingResponse(for: normalized) {
            return JarvisElevatedRequest(
                kind: .greeting,
                elevatedIntent: "light_greeting",
                elevatedPrompt: trimmed,
                responseContract: JarvisResponseContract(maxSentences: 2),
                platformResponse: greeting,
                prefersSafePrompt: true
            )
        }

        if let draftStart = draftStartRequest(for: normalized, requestedTask: requestedTask) {
            return JarvisElevatedRequest(
                kind: .draftRequest,
                elevatedIntent: draftStart.intent,
                elevatedPrompt: draftStart.elevatedPrompt,
                responseContract: JarvisResponseContract(
                    directAnswerFirst: true,
                    prefersReadyToSend: true,
                    prefersMinimalExplanation: true
                ),
                prefersSafePrompt: true,
                capabilityHint: .draftEmail
            )
        }

        if let clarification = clarificationQuestion(for: normalized, requestedTask: requestedTask) {
            return JarvisElevatedRequest(
                kind: .clarificationNeeded,
                elevatedIntent: clarification.intent,
                elevatedPrompt: clarification.elevatedPrompt,
                responseContract: JarvisResponseContract(maxSentences: 1, asksSingleQuestion: true),
                platformResponse: clarification.question,
                clarificationQuestion: clarification.question,
                prefersSafePrompt: true
            )
        }

        let kind = classifyKind(normalized: normalized, requestedTask: requestedTask, classification: classification)
        let contract = responseContract(for: kind)
        let elevatedPrompt = elevatedPrompt(for: trimmed, kind: kind, classification: classification)
        return JarvisElevatedRequest(
            kind: kind,
            elevatedIntent: elevatedIntent(for: kind, classification: classification),
            elevatedPrompt: elevatedPrompt,
            responseContract: contract,
            prefersSafePrompt: kind != .greeting,
            capabilityHint: capabilityHint(for: normalized, kind: kind, requestedTask: requestedTask)
        )
    }

    private func classifyKind(
        normalized: String,
        requestedTask: JarvisAssistantTask,
        classification: JarvisTaskClassification
    ) -> JarvisElevatedRequestKind {
        switch requestedTask {
        case .summarize:
            return .summarizationRequest
        case .reply, .draftEmail:
            return .draftRequest
        case .analyzeText:
            if classification.category == .coding {
                return .codingRequest
            }
            if classification.category == .planning {
                return .planningRequest
            }
        default:
            break
        }

        if classification.category == .coding {
            return .codingRequest
        }
        if isScreenshotRequest(normalized) {
            return .deviceActionRequest
        }
        if isOpenRouteRequest(normalized) || isRouteDisplayRequest(normalized) || isAppActionRequest(normalized) {
            return .appActionRequest
        }
        if isSearchRequest(normalized) {
            return .searchRequest
        }
        if classification.category == .planning {
            return .planningRequest
        }
        if classification.category == .summarization {
            return .summarizationRequest
        }
        if classification.category == .draftingEmail || classification.category == .draftingMessage || classification.category == .contextAwareReply {
            return .draftRequest
        }
        if normalized.contains("?") || normalized.hasPrefix("what ") || normalized.hasPrefix("why ") || normalized.hasPrefix("how ") {
            return .questionAnswering
        }
        if normalized.split(whereSeparator: \.isWhitespace).count <= 3 {
            return .vaguePrompt
        }
        return .actionRequest
    }

    private func responseContract(for kind: JarvisElevatedRequestKind) -> JarvisResponseContract {
        switch kind {
        case .greeting:
            return JarvisResponseContract(maxSentences: 2)
        case .questionAnswering:
            return JarvisResponseContract(directAnswerFirst: true)
        case .actionRequest:
            return JarvisResponseContract(directAnswerFirst: true)
        case .draftRequest:
            return JarvisResponseContract(
                directAnswerFirst: true,
                prefersReadyToSend: true,
                prefersMinimalExplanation: true
            )
        case .codingRequest:
            return JarvisResponseContract(
                directAnswerFirst: true,
                prefersCodeFirst: true,
                prefersRunnableOutput: true,
                prefersMinimalExplanation: true
            )
        case .summarizationRequest:
            return JarvisResponseContract(prefersChecklist: true)
        case .planningRequest:
            return JarvisResponseContract(prefersChecklist: true)
        case .deviceActionRequest, .appActionRequest, .searchRequest:
            return JarvisResponseContract(
                maxSentences: 2,
                directAnswerFirst: true,
                forbidsHallucinatedCompletion: true
            )
        case .vaguePrompt, .clarificationNeeded:
            return JarvisResponseContract(maxSentences: 1, asksSingleQuestion: true)
        }
    }

    private func elevatedPrompt(
        for prompt: String,
        kind: JarvisElevatedRequestKind,
        classification: JarvisTaskClassification
    ) -> String {
        switch kind {
        case .planningRequest:
            return "Turn this into a clear action plan with priorities and next steps:\n\(prompt)"
        case .codingRequest:
            return "Solve this as a coding task. Return runnable code first, then a minimal explanation and any important risks or test notes:\n\(prompt)"
        case .summarizationRequest:
            return "Summarize this into a compact overview and key points:\n\(prompt)"
        case .draftRequest:
            return "Draft the requested content so it is ready to send or use with minimal editing. Ask one follow-up only if essential:\n\(prompt)"
        case .questionAnswering:
            return "Answer this directly and clearly:\n\(prompt)"
        case .actionRequest:
            return "Help the user complete this task directly and concretely:\n\(prompt)"
        case .deviceActionRequest:
            return "This request targets a device action. Do not claim completion unless the action is actually available. State the action route clearly:\n\(prompt)"
        case .appActionRequest:
            return "This request targets an in-app or app-routing action. Do not hallucinate completion. Either route it or state the exact next action:\n\(prompt)"
        case .searchRequest:
            return "This request is a search or retrieval action. Prefer routing to search/knowledge rather than free-form guessing:\n\(prompt)"
        case .vaguePrompt:
            return "The user gave a short or weak prompt. Infer the likely task conservatively and ask for the single missing detail only if required:\n\(prompt)"
        case .clarificationNeeded, .greeting:
            return prompt
        }
    }

    private func elevatedIntent(
        for kind: JarvisElevatedRequestKind,
        classification: JarvisTaskClassification
    ) -> String {
        switch kind {
        case .greeting:
            return "greeting"
        case .questionAnswering:
            return "question_answering"
        case .actionRequest:
            return "task_execution"
        case .draftRequest:
            return classification.category == .draftingEmail ? "email_assistance" : "drafting"
        case .codingRequest:
            return "coding_support"
        case .summarizationRequest:
            return "summarization"
        case .planningRequest:
            return "planning"
        case .deviceActionRequest:
            return "device_action"
        case .appActionRequest:
            return "app_action"
        case .searchRequest:
            return "search"
        case .vaguePrompt:
            return "ambiguous_request"
        case .clarificationNeeded:
            return "clarification"
        }
    }

    private func greetingResponse(for normalized: String) -> String? {
        let greetings: Set<String> = ["hi", "hello", "hey", "yo", "good morning", "good afternoon", "good evening"]
        guard greetings.contains(normalized) else { return nil }

        switch normalized {
        case "good morning":
            return "Good morning. Ready when you are."
        case "good evening":
            return "Good evening. Send me the task when you're ready."
        default:
            return "Hey. Send me what you need."
        }
    }

    private func clarificationQuestion(
        for normalized: String,
        requestedTask: JarvisAssistantTask
    ) -> (intent: String, question: String, elevatedPrompt: String)? {
        if requestedTask == .draftEmail {
            return (
                "email_assistance",
                "Do you want help drafting a new email or replying to one?",
                "The user needs email help but has not specified whether this is a new draft or a reply."
            )
        }

        if normalized == "fix this" || normalized == "fix" {
            return (
                "problem_solving",
                "What exactly needs fixing: code, writing, or a specific error?",
                "The user asked for a fix without enough context. Ask one precise question to identify the target."
            )
        }

        if normalized == "plan tomorrow" || normalized == "plan" {
            return (
                "planning",
                "What do you want tomorrow's plan optimized for: work, errands, or a full-day schedule?",
                "The user wants planning help but has not given the planning scope."
            )
        }

        let wordCount = normalized.split(whereSeparator: \.isWhitespace).count
        if wordCount <= 2, ["this", "that", "it"].contains(where: normalized.contains) {
            return (
                "clarification",
                "What are you referring to exactly?",
                "The user is referencing missing context. Ask for the missing referent in one short question."
            )
        }

        return nil
    }

    private func draftStartRequest(
        for normalized: String,
        requestedTask: JarvisAssistantTask
    ) -> (intent: String, elevatedPrompt: String)? {
        if requestedTask == .draftEmail || normalized == "mail" || normalized == "email" {
            return (
                "email_assistance",
                """
                Start an email draft immediately. Use a neutral professional tone, keep it concise, and leave short placeholders only where the user omitted critical details like recipient or purpose.
                """
            )
        }

        return nil
    }

    private func capabilityHint(
        for normalized: String,
        kind: JarvisElevatedRequestKind,
        requestedTask: JarvisAssistantTask
    ) -> JarvisAssistantCapabilityCandidate.Kind? {
        switch kind {
        case .deviceActionRequest:
            if isScreenshotRequest(normalized) {
                return .screenshot
            }
            return .generic
        case .appActionRequest:
            if containsAny(normalized, in: ["open settings", "show settings"]) {
                return .openRoute
            }
            if containsAny(normalized, in: ["open camera", "camera"]) {
                return .openRoute
            }
            if containsAny(normalized, in: ["start new chat", "new chat", "clear conversation"]) {
                return .newChat
            }
            if containsAny(normalized, in: ["save this", "save reply", "bookmark this"]) {
                return .saveContent
            }
            if containsAny(normalized, in: ["copy this", "copy reply"]) {
                return .copyContent
            }
            return .openRoute
        case .searchRequest:
            return .searchKnowledge
        case .draftRequest where requestedTask == .draftEmail || containsAny(normalized, in: ["draft email", "write an email", "email draft"]):
            return .draftEmail
        default:
            return nil
        }
    }

    private func isScreenshotRequest(_ normalized: String) -> Bool {
        containsAny(normalized, in: [
            "take a screenshot",
            "take screenshot",
            "capture the screen",
            "screenshot of the screen",
            "screen shot"
        ])
    }

    private func isOpenRouteRequest(_ normalized: String) -> Bool {
        containsAny(normalized, in: [
            "open settings",
            "show settings",
            "open camera",
            "show camera",
            "show knowledge",
            "open knowledge",
            "open visual",
            "show visual"
        ])
    }

    private func isRouteDisplayRequest(_ normalized: String) -> Bool {
        containsAny(normalized, in: ["show knowledge", "show settings", "show camera", "show chat"])
    }

    private func isAppActionRequest(_ normalized: String) -> Bool {
        containsAny(normalized, in: [
            "start new chat",
            "new chat",
            "save this",
            "save reply",
            "bookmark this",
            "copy this",
            "copy reply"
        ])
    }

    private func isSearchRequest(_ normalized: String) -> Bool {
        containsAny(normalized, in: [
            "search files",
            "search my files",
            "search knowledge",
            "search my notes",
            "find in my notes",
            "find in knowledge",
            "search local knowledge"
        ])
    }

    private func containsAny(_ value: String, in terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }
}
