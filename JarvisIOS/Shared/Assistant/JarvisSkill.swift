import Foundation

public struct JarvisSkill: Identifiable, Equatable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let requiredInputs: [String]
    public let responseFormat: String
    public let supportedTasks: [JarvisAssistantTask]
    public let supportedCategories: [JarvisTaskCategory]
    public let preferredContextSources: [JarvisSkillContextSource]
    public let preferredMemoryKinds: [JarvisMemoryKind]
    public let preferredOutputKind: JarvisSkillOutputKind
    public let formattingHints: [String]
    public let followUpActionHints: [String]
    public let triggerTerms: [String]

    public init(
        id: String,
        name: String,
        description: String,
        requiredInputs: [String],
        responseFormat: String,
        supportedTasks: [JarvisAssistantTask],
        supportedCategories: [JarvisTaskCategory],
        preferredContextSources: [JarvisSkillContextSource],
        preferredMemoryKinds: [JarvisMemoryKind],
        preferredOutputKind: JarvisSkillOutputKind,
        formattingHints: [String],
        followUpActionHints: [String],
        triggerTerms: [String]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.requiredInputs = requiredInputs
        self.responseFormat = responseFormat
        self.supportedTasks = supportedTasks
        self.supportedCategories = supportedCategories
        self.preferredContextSources = preferredContextSources
        self.preferredMemoryKinds = preferredMemoryKinds
        self.preferredOutputKind = preferredOutputKind
        self.formattingHints = formattingHints
        self.followUpActionHints = followUpActionHints
        self.triggerTerms = triggerTerms
    }
}

public enum JarvisSkillCatalog {
    public static let all: [JarvisSkill] = [
        JarvisSkill(
            id: "code_generation",
            name: "Code Generation",
            description: "Produce or modify code with concise implementation context.",
            requiredInputs: ["code goal", "constraints"],
            responseFormat: "code answer card",
            supportedTasks: [.analyzeText, .chat],
            supportedCategories: [.coding],
            preferredContextSources: [.projectMemory, .taskMemory, .recentMessages, .constraints],
            preferredMemoryKinds: [.project, .task, .recentContext, .conversationSummary],
            preferredOutputKind: .codeAnswer,
            formattingHints: ["Lead with the fix or implementation.", "Use short explanatory notes after code."],
            followUpActionHints: ["test", "refactor", "explain"],
            triggerTerms: ["implement", "write code", "generate code", "function", "swift", "fix"]
        ),
        JarvisSkill(
            id: "code_explanation",
            name: "Code Explanation",
            description: "Explain code behavior, tradeoffs, and debugging paths.",
            requiredInputs: ["code context", "question"],
            responseFormat: "code answer card",
            supportedTasks: [.analyzeText, .chat],
            supportedCategories: [.coding, .explainingSomething],
            preferredContextSources: [.projectMemory, .recentMessages, .conversationSummary],
            preferredMemoryKinds: [.project, .task, .conversationSummary],
            preferredOutputKind: .codeAnswer,
            formattingHints: ["Explain the cause first, then the remedy.", "Use bullets for risks or tradeoffs."],
            followUpActionHints: ["debug", "refine", "test"],
            triggerTerms: ["explain code", "why does", "compile error", "debug", "stack trace"]
        ),
        JarvisSkill(
            id: "draft_email",
            name: "Draft Email",
            description: "Compose or refine a send-ready email.",
            requiredInputs: ["recipient or context", "intent"],
            responseFormat: "draft card",
            supportedTasks: [.draftEmail, .reply],
            supportedCategories: [.draftingEmail],
            preferredContextSources: [.preferenceMemory, .replyTarget, .recentMessages, .conversationSummary],
            preferredMemoryKinds: [.preference, .recentContext, .conversationSummary],
            preferredOutputKind: .draft,
            formattingHints: ["Write in a send-ready format.", "Reflect saved tone preferences if available."],
            followUpActionHints: ["rephrase", "shorten", "change tone"],
            triggerTerms: ["email", "subject", "send", "reply"]
        ),
        JarvisSkill(
            id: "draft_message",
            name: "Draft Message",
            description: "Draft texts and short replies in the user's voice.",
            requiredInputs: ["recipient or tone", "intent"],
            responseFormat: "draft card",
            supportedTasks: [.reply, .chat],
            supportedCategories: [.draftingMessage, .contextAwareReply],
            preferredContextSources: [.preferenceMemory, .replyTarget, .recentMessages],
            preferredMemoryKinds: [.preference, .recentContext],
            preferredOutputKind: .draft,
            formattingHints: ["Keep it ready to send.", "Mirror the user's preferred tone when known."],
            followUpActionHints: ["make warmer", "make shorter", "make more direct"],
            triggerTerms: ["message", "text back", "reply", "what should i say"]
        ),
        JarvisSkill(
            id: "planning",
            name: "Planning",
            description: "Turn a goal into steps, constraints, and next actions.",
            requiredInputs: ["goal", "constraints"],
            responseFormat: "checklist / plan card",
            supportedTasks: [.analyzeText, .quickCapture, .chat],
            supportedCategories: [.planning],
            preferredContextSources: [.taskMemory, .projectMemory, .conversationSummary, .constraints],
            preferredMemoryKinds: [.task, .project, .conversationSummary, .recentContext],
            preferredOutputKind: .checklist,
            formattingHints: ["Produce actionable ordered steps.", "Highlight blockers and open decisions."],
            followUpActionHints: ["prioritize", "expand", "assign"],
            triggerTerms: ["plan", "roadmap", "checklist", "next step"]
        ),
        JarvisSkill(
            id: "summarization",
            name: "Summarization",
            description: "Compress content into key points, decisions, and next steps.",
            requiredInputs: ["source text"],
            responseFormat: "summary card",
            supportedTasks: [.summarize, .knowledgeAnswer],
            supportedCategories: [.summarization],
            preferredContextSources: [.conversationSummary, .knowledge],
            preferredMemoryKinds: [.conversationSummary, .knowledge, .recentContext],
            preferredOutputKind: .summary,
            formattingHints: ["Emphasize decisions, goals, and open tasks.", "Stay concise."],
            followUpActionHints: ["expand", "turn into checklist"],
            triggerTerms: ["summarize", "summary", "tl;dr", "key points"]
        ),
        JarvisSkill(
            id: "answer_question",
            name: "Answer Question",
            description: "Answer a direct question with concise supporting context.",
            requiredInputs: ["question"],
            responseFormat: "knowledge answer card",
            supportedTasks: [.chat, .knowledgeAnswer],
            supportedCategories: [.questionAnswering, .explainingSomething],
            preferredContextSources: [.knowledge, .conversationSummary, .recentMessages],
            preferredMemoryKinds: [.knowledge, .conversationSummary, .project, .preference],
            preferredOutputKind: .knowledgeAnswer,
            formattingHints: ["Answer first.", "Add supporting context only if it changes the answer."],
            followUpActionHints: ["search more", "show source", "explain"],
            triggerTerms: ["what", "how", "why", "question"]
        ),
        JarvisSkill(
            id: "knowledge_lookup",
            name: "Knowledge Lookup",
            description: "Retrieve relevant saved knowledge and answer from it.",
            requiredInputs: ["topic or fact"],
            responseFormat: "knowledge answer card",
            supportedTasks: [.knowledgeAnswer, .chat],
            supportedCategories: [.questionAnswering, .explainingSomething],
            preferredContextSources: [.knowledge, .conversationSummary, .projectMemory],
            preferredMemoryKinds: [.knowledge, .conversationSummary, .project],
            preferredOutputKind: .knowledgeAnswer,
            formattingHints: ["Ground the answer in saved knowledge before general reasoning.", "Stay precise."],
            followUpActionHints: ["open knowledge", "summarize source"],
            triggerTerms: ["knowledge", "docs", "note", "saved", "remember"]
        ),
        JarvisSkill(
            id: "rewrite_text",
            name: "Rewrite Text",
            description: "Rewrite or tighten text while keeping intent intact.",
            requiredInputs: ["source text", "desired tone or constraints"],
            responseFormat: "draft card",
            supportedTasks: [.reply, .chat],
            supportedCategories: [.rewritingText],
            preferredContextSources: [.preferenceMemory, .recentMessages, .replyTarget],
            preferredMemoryKinds: [.preference, .recentContext],
            preferredOutputKind: .draft,
            formattingHints: ["Preserve intent and improve clarity.", "Use the requested tone."],
            followUpActionHints: ["shorter", "friendlier", "more formal"],
            triggerTerms: ["rewrite", "rephrase", "polish", "tighten"]
        ),
        JarvisSkill(
            id: "brainstorm",
            name: "Brainstorm",
            description: "Generate options, directions, and variations.",
            requiredInputs: ["topic", "goal"],
            responseFormat: "brainstorm list",
            supportedTasks: [.chat, .quickCapture],
            supportedCategories: [.generalChat],
            preferredContextSources: [.projectMemory, .preferenceMemory, .conversationSummary],
            preferredMemoryKinds: [.project, .preference, .conversationSummary],
            preferredOutputKind: .brainstorm,
            formattingHints: ["Offer distinct options, not minor variants.", "Keep the list scannable."],
            followUpActionHints: ["pick one", "compare", "expand"],
            triggerTerms: ["brainstorm", "ideas", "options", "names"]
        )
    ]

    public static func resolve(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) -> JarvisSkill {
        let prompt = request.prompt.lowercased()

        let ranked = all.map { skill -> (JarvisSkill, Int) in
            var score = 0
            if skill.supportedTasks.contains(classification.task) || skill.supportedTasks.contains(request.requestedTask) {
                score += 5
            }
            if skill.supportedCategories.contains(classification.category) {
                score += 6
            }
            score += skill.triggerTerms.filter { prompt.contains($0) }.count * 2
            if request.assistantMode == .code, skill.id.hasPrefix("code_") {
                score += 3
            }
            if request.assistantMode == .write, skill.id.hasPrefix("draft_") {
                score += 3
            }
            if request.assistantMode == .plan, skill.id == "planning" {
                score += 3
            }
            if request.assistantMode == .summarize, skill.id == "summarization" {
                score += 3
            }
            return (skill, score)
        }

        let best = ranked.sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.id < rhs.0.id
            }
            return lhs.1 > rhs.1
        }.first

        if let best, best.1 > 0 {
            return best.0
        }

        return fallbackSkill(for: classification)
    }

    private static func fallbackSkill(for classification: JarvisTaskClassification) -> JarvisSkill {
        switch classification.category {
        case .coding:
            return all.first { $0.id == "code_generation" }!
        case .draftingEmail:
            return all.first { $0.id == "draft_email" }!
        case .draftingMessage, .contextAwareReply:
            return all.first { $0.id == "draft_message" }!
        case .planning:
            return all.first { $0.id == "planning" }!
        case .summarization:
            return all.first { $0.id == "summarization" }!
        case .questionAnswering, .explainingSomething:
            return all.first { $0.id == "answer_question" }!
        case .rewritingText:
            return all.first { $0.id == "rewrite_text" }!
        case .generalChat:
            return all.first { $0.id == "brainstorm" }!
        }
    }
}

public struct JarvisSkillCapabilityProvider: JarvisAssistantCapabilityProviding {
    public init() {}

    public func candidates(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) async -> [JarvisAssistantCapabilityCandidate] {
        let prompt = request.prompt.lowercased()
        var candidates: [JarvisAssistantCapabilityCandidate] = []

        if prompt.contains("take a screenshot") || prompt.contains("take screenshot") || prompt.contains("capture the screen") {
            candidates.append(
                JarvisAssistantCapabilityCandidate(
                    name: "device.screenshot",
                    summary: "Capture the current screen as an image using a device capability.",
                    kind: .screenshot,
                    availability: .placeholder
                )
            )
        }

        if prompt.contains("open settings") || prompt.contains("show settings") || prompt.contains("open camera") || prompt.contains("show knowledge") || prompt.contains("open knowledge") {
            candidates.append(
                JarvisAssistantCapabilityCandidate(
                    name: "app.open_route",
                    summary: "Open a specific Jarvis or system-adjacent route instead of answering in free text.",
                    kind: .openRoute,
                    availability: .placeholder
                )
            )
        }

        if prompt.contains("search my notes") || prompt.contains("search local knowledge") || prompt.contains("find in my notes") || prompt.contains("search knowledge") {
            candidates.append(
                JarvisAssistantCapabilityCandidate(
                    name: "knowledge.search",
                    summary: "Search the local knowledge surface directly.",
                    kind: .searchKnowledge,
                    availability: .placeholder
                )
            )
        }

        if prompt.contains("save this") || prompt.contains("save reply") || prompt.contains("bookmark this") {
            candidates.append(
                JarvisAssistantCapabilityCandidate(
                    name: "content.save",
                    summary: "Save the current content using a platform or app action.",
                    kind: .saveContent,
                    availability: .placeholder
                )
            )
        }

        if prompt.contains("copy this") || prompt.contains("copy reply") {
            candidates.append(
                JarvisAssistantCapabilityCandidate(
                    name: "content.copy",
                    summary: "Copy the latest content using a platform or app action.",
                    kind: .copyContent,
                    availability: .placeholder
                )
            )
        }

        if prompt.contains("new chat") || prompt.contains("start new chat") {
            candidates.append(
                JarvisAssistantCapabilityCandidate(
                    name: "chat.new",
                    summary: "Start a new assistant conversation.",
                    kind: .newChat,
                    availability: .placeholder
                )
            )
        }

        candidates.append(contentsOf: JarvisSkillCatalog.all.compactMap { skill in
            let taskMatch = skill.supportedTasks.contains(classification.task) || skill.supportedTasks.contains(request.requestedTask)
            let categoryMatch = skill.supportedCategories.contains(classification.category)
            let triggerMatch = skill.triggerTerms.contains { prompt.contains($0) }
            guard taskMatch || categoryMatch || triggerMatch else { return nil }
            return JarvisAssistantCapabilityCandidate(
                name: skill.id,
                summary: "\(skill.description) Response format: \(skill.responseFormat).",
                kind: skill.id == "draft_email" ? .draftEmail : .generic,
                availability: .placeholder
            )
        })

        return candidates
    }
}
