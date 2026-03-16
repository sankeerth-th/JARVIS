import Foundation

public enum JarvisTaskCategory: String, Codable, CaseIterable {
    case generalChat
    case questionAnswering
    case summarization
    case draftingMessage
    case draftingEmail
    case rewritingText
    case explainingSomething
    case planning
    case coding
    case contextAwareReply

    public var displayName: String {
        switch self {
        case .generalChat:
            return "General Chat"
        case .questionAnswering:
            return "Question Answering"
        case .summarization:
            return "Summarization"
        case .draftingMessage:
            return "Drafting Message"
        case .draftingEmail:
            return "Drafting Email"
        case .rewritingText:
            return "Rewriting Text"
        case .explainingSomething:
            return "Explaining Something"
        case .planning:
            return "Planning"
        case .coding:
            return "Coding"
        case .contextAwareReply:
            return "Context-Aware Reply"
        }
    }
}

public enum JarvisGenerationPreset: String, Codable, CaseIterable {
    case balanced
    case creative
    case precise
    case coding
    case drafting
}

public struct JarvisGenerationTuning: Equatable, Codable {
    public var preset: JarvisGenerationPreset
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var typicalP: Double
    public var repeatPenalty: Double
    public var penaltyLastN: Int
    public var maxContextTokens: Int
    public var maxOutputTokens: Int
    public var maxHistoryCharacters: Int
    public var maxKnowledgeCharacters: Int
    public var repetitionWindowCharacters: Int
    public var repetitionThreshold: Int
    public var requiresGroundedAnswers: Bool
    public var usesReasoningPlan: Bool
    public var responseStyle: JarvisAssistantResponseStyle

    public init(
        preset: JarvisGenerationPreset,
        temperature: Double,
        topP: Double,
        topK: Int,
        typicalP: Double,
        repeatPenalty: Double,
        penaltyLastN: Int,
        maxContextTokens: Int,
        maxOutputTokens: Int,
        maxHistoryCharacters: Int,
        maxKnowledgeCharacters: Int,
        repetitionWindowCharacters: Int,
        repetitionThreshold: Int,
        requiresGroundedAnswers: Bool,
        usesReasoningPlan: Bool,
        responseStyle: JarvisAssistantResponseStyle
    ) {
        self.preset = preset
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.typicalP = typicalP
        self.repeatPenalty = repeatPenalty
        self.penaltyLastN = penaltyLastN
        self.maxContextTokens = maxContextTokens
        self.maxOutputTokens = maxOutputTokens
        self.maxHistoryCharacters = maxHistoryCharacters
        self.maxKnowledgeCharacters = maxKnowledgeCharacters
        self.repetitionWindowCharacters = repetitionWindowCharacters
        self.repetitionThreshold = repetitionThreshold
        self.requiresGroundedAnswers = requiresGroundedAnswers
        self.usesReasoningPlan = usesReasoningPlan
        self.responseStyle = responseStyle
    }

    public static let balanced = JarvisGenerationTuning(
        preset: .balanced,
        temperature: 0.55,
        topP: 0.90,
        topK: 40,
        typicalP: 0.96,
        repeatPenalty: 1.08,
        penaltyLastN: 72,
        maxContextTokens: 768,
        maxOutputTokens: 320,
        maxHistoryCharacters: 2_400,
        maxKnowledgeCharacters: 520,
        repetitionWindowCharacters: 280,
        repetitionThreshold: 3,
        requiresGroundedAnswers: false,
        usesReasoningPlan: true,
        responseStyle: .balanced
    )
}

public struct JarvisTaskClassification: Equatable, Codable {
    public var category: JarvisTaskCategory
    public var task: JarvisAssistantTask
    public var preset: JarvisGenerationPreset
    public var confidence: Double
    public var reasoningHint: String
    public var responseHint: String
    public var shouldInjectKnowledge: Bool
    public var shouldPreferStructuredOutput: Bool

    public init(
        category: JarvisTaskCategory,
        task: JarvisAssistantTask,
        preset: JarvisGenerationPreset,
        confidence: Double,
        reasoningHint: String,
        responseHint: String,
        shouldInjectKnowledge: Bool,
        shouldPreferStructuredOutput: Bool
    ) {
        self.category = category
        self.task = task
        self.preset = preset
        self.confidence = confidence
        self.reasoningHint = reasoningHint
        self.responseHint = responseHint
        self.shouldInjectKnowledge = shouldInjectKnowledge
        self.shouldPreferStructuredOutput = shouldPreferStructuredOutput
    }

    public static let `default` = JarvisTaskClassification(
        category: .generalChat,
        task: .chat,
        preset: .balanced,
        confidence: 0.5,
        reasoningHint: "Answer directly and keep the flow conversational.",
        responseHint: "Lead with the answer and add only the most useful detail.",
        shouldInjectKnowledge: false,
        shouldPreferStructuredOutput: false
    )
}

public struct JarvisPromptContextBlock: Equatable, Codable {
    public var title: String
    public var content: String

    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}

public struct JarvisPromptBlueprint: Equatable, Codable {
    public var systemInstruction: String
    public var assistantRole: String
    public var taskTypeInstruction: String
    public var responseInstruction: String
    public var contextBlocks: [JarvisPromptContextBlock]
    public var userInputPrefix: String

    public init(
        systemInstruction: String,
        assistantRole: String,
        taskTypeInstruction: String,
        responseInstruction: String,
        contextBlocks: [JarvisPromptContextBlock],
        userInputPrefix: String
    ) {
        self.systemInstruction = systemInstruction
        self.assistantRole = assistantRole
        self.taskTypeInstruction = taskTypeInstruction
        self.responseInstruction = responseInstruction
        self.contextBlocks = contextBlocks
        self.userInputPrefix = userInputPrefix
    }

    public static let `default` = JarvisPromptBlueprint(
        systemInstruction: "You are Jarvis, a private on-device AI assistant designed for fast reasoning, clear answers, and intelligent help with everyday tasks.",
        assistantRole: "Act like a proactive iPhone assistant: concise, context-aware, and action-oriented.",
        taskTypeInstruction: "Treat the request as a general assistant conversation.",
        responseInstruction: "Lead with the answer, then add the most useful supporting detail.",
        contextBlocks: [],
        userInputPrefix: "User request:"
    )
}

public struct JarvisPromptEnvelope: Equatable {
    public var classification: JarvisTaskClassification
    public var tuning: JarvisGenerationTuning
    public var blueprint: JarvisPromptBlueprint
    public var prompt: String
    public var history: [JarvisChatMessage]
    public var groundedResults: [JarvisKnowledgeResult]
    public var replyTargetText: String?
    public var debugSummary: String

    public init(
        classification: JarvisTaskClassification,
        tuning: JarvisGenerationTuning,
        blueprint: JarvisPromptBlueprint,
        prompt: String,
        history: [JarvisChatMessage],
        groundedResults: [JarvisKnowledgeResult],
        replyTargetText: String?,
        debugSummary: String
    ) {
        self.classification = classification
        self.tuning = tuning
        self.blueprint = blueprint
        self.prompt = prompt
        self.history = history
        self.groundedResults = groundedResults
        self.replyTargetText = replyTargetText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.debugSummary = debugSummary
    }
}

public enum JarvisAssistantSuggestionDescriptorAction: Equatable {
    case prompt(String)
    case task(JarvisAssistantTask, String)
    case saveToKnowledge
    case voiceFollowUp
    case searchKnowledge(String)
}

public struct JarvisAssistantSuggestionDescriptor: Equatable {
    public var title: String
    public var icon: String
    public var action: JarvisAssistantSuggestionDescriptorAction

    public init(title: String, icon: String, action: JarvisAssistantSuggestionDescriptorAction) {
        self.title = title
        self.icon = icon
        self.action = action
    }
}

public struct JarvisStreamingTextProcessor {
    private var pending = ""

    public init() {}

    public mutating func ingest(_ chunk: String) -> String? {
        pending.append(chunk)
        return flushIfNeeded(force: false)
    }

    public mutating func finish() -> String? {
        flushIfNeeded(force: true)
    }

    private mutating func flushIfNeeded(force: Bool) -> String? {
        guard !pending.isEmpty else { return nil }
        guard let flushIndex = flushIndex(force: force) else { return nil }

        let segment = String(pending[..<flushIndex])
        pending.removeSubrange(..<flushIndex)
        return segment
    }

    private func flushIndex(force: Bool) -> String.Index? {
        if force {
            return pending.endIndex
        }

        if pending.contains("\n\n") {
            return pending.endIndex
        }

        if pending.hasSuffix("```") || pending.hasSuffix("\n") {
            return pending.endIndex
        }

        let endings = CharacterSet(charactersIn: ".!?:;")
        if let last = pending.unicodeScalars.last,
           endings.contains(last),
           pending.count >= 18 {
            return pending.endIndex
        }

        guard pending.count >= 36 else { return nil }

        var cursor = pending.endIndex
        var scanned = 0
        while cursor > pending.startIndex, scanned < 20 {
            cursor = pending.index(before: cursor)
            scanned += 1
            let scalar = pending[cursor].unicodeScalars.first
            if scalar.map(CharacterSet.whitespacesAndNewlines.contains) == true {
                return pending.index(after: cursor)
            }
        }

        return pending.count >= 72 ? pending.endIndex : nil
    }
}

enum JarvisAssistantIntelligence {
    static func classify(
        prompt: String,
        requestedTask: JarvisAssistantTask,
        context: JarvisAssistantTaskContext,
        conversation: JarvisConversationRecord
    ) -> JarvisTaskClassification {
        let normalized = prompt.lowercased()
        let replyRequested = requestedTask == .reply || context.replyTargetText?.isEmpty == false

        if replyRequested || containsAny(normalized, in: ["reply to", "respond to", "text back", "what should i say", "draft a reply"]) {
            return JarvisTaskClassification(
                category: .contextAwareReply,
                task: .reply,
                preset: .drafting,
                confidence: 0.95,
                reasoningHint: "Use the surrounding context and draft a response the user can send with minimal editing.",
                responseHint: "Write naturally, preserve important details, and keep the wording ready to send.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: false
            )
        }

        if requestedTask == .draftEmail || containsAny(normalized, in: ["draft email", "write an email", "email reply", "professional email", "subject line"]) {
            return JarvisTaskClassification(
                category: .draftingEmail,
                task: .draftEmail,
                preset: .drafting,
                confidence: 0.95,
                reasoningHint: "Produce a polished email with clear structure and appropriate tone.",
                responseHint: "Use a strong opening, concise body, and a clear close. Make it feel send-ready.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: false
            )
        }

        if requestedTask == .summarize || containsAny(normalized, in: ["summarize", "summary", "tl;dr", "key points", "short overview"]) {
            return JarvisTaskClassification(
                category: .summarization,
                task: .summarize,
                preset: .precise,
                confidence: 0.94,
                reasoningHint: "Compress the content faithfully and surface the highest-signal points first.",
                responseHint: "Prefer an overview plus compact bullets or short sections instead of long prose.",
                shouldInjectKnowledge: requestedTask == .knowledgeAnswer,
                shouldPreferStructuredOutput: true
            )
        }

        if containsAny(normalized, in: ["rewrite", "rephrase", "make this shorter", "tighten", "improve grammar", "fix grammar", "simplify this", "make this sound"]) {
            return JarvisTaskClassification(
                category: .rewritingText,
                task: .analyzeText,
                preset: .drafting,
                confidence: 0.9,
                reasoningHint: "Transform the text while preserving the underlying intent and important facts.",
                responseHint: "Return only the rewritten output unless a short note materially helps.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: false
            )
        }

        if requestedTask == .analyzeText || containsAny(normalized, in: ["plan", "roadmap", "next steps", "organize", "strategy", "schedule", "checklist", "todo"]) {
            return JarvisTaskClassification(
                category: .planning,
                task: .analyzeText,
                preset: .balanced,
                confidence: 0.82,
                reasoningHint: "Organize the work into concrete actions, priorities, and next steps.",
                responseHint: "Use a structure that helps the user act quickly, such as ordered steps or grouped bullets.",
                shouldInjectKnowledge: containsAny(normalized, in: ["based on my notes", "using my notes", "from my notes", "knowledge"]),
                shouldPreferStructuredOutput: true
            )
        }

        if containsAny(normalized, in: ["swift", "xcode", "stack trace", "compile", "compiler", "function", "refactor", "debug", "bug", "code", "test case", "unit test", "regex", "python", "javascript", "typescript", "script", "class ", "def ", "func ", "write a script", "write code"]) {
            return JarvisTaskClassification(
                category: .coding,
                task: .analyzeText,
                preset: .coding,
                confidence: 0.92,
                reasoningHint: "Reason step-by-step about the code path, likely failure modes, and concrete fixes.",
                responseHint: "Be specific, use precise terminology, and prefer directly actionable code guidance.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            )
        }

        if containsAny(normalized, in: ["explain", "how does", "walk me through", "why does", "what happens"]) {
            return JarvisTaskClassification(
                category: .explainingSomething,
                task: .analyzeText,
                preset: .precise,
                confidence: 0.84,
                reasoningHint: "Teach clearly, front-load the concept, and add just enough detail for understanding.",
                responseHint: "Use plain language first, then add the key mechanism or example.",
                shouldInjectKnowledge: containsAny(normalized, in: ["from my notes", "knowledge", "saved context"]),
                shouldPreferStructuredOutput: false
            )
        }

        if requestedTask == .knowledgeAnswer || containsAny(normalized, in: ["based on my notes", "from my notes", "saved context", "knowledge base", "what do my notes say"]) {
            return JarvisTaskClassification(
                category: .questionAnswering,
                task: .knowledgeAnswer,
                preset: .precise,
                confidence: 0.88,
                reasoningHint: "Ground the answer in available local context and say when that context is thin.",
                responseHint: "Answer directly, cite the local source title when helpful, and avoid pretending the context says more than it does.",
                shouldInjectKnowledge: true,
                shouldPreferStructuredOutput: false
            )
        }

        if normalized.contains("?") || containsAny(normalized, in: ["what", "when", "where", "who", "which"]) {
            return JarvisTaskClassification(
                category: .questionAnswering,
                task: requestedTask == .chat ? .chat : requestedTask,
                preset: .precise,
                confidence: 0.72,
                reasoningHint: "Answer the question directly and keep the explanation grounded.",
                responseHint: "Start with the answer, then add the minimum context needed to trust it.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: false
            )
        }

        let hasConversationHistory = !conversation.messages.isEmpty
        return JarvisTaskClassification(
            category: hasConversationHistory ? .generalChat : .draftingMessage,
            task: requestedTask == .chat ? .chat : requestedTask,
            preset: hasConversationHistory ? .balanced : .creative,
            confidence: 0.62,
            reasoningHint: "Stay conversational, adapt to the user's tone, and be useful quickly.",
            responseHint: "Keep the answer natural, but add structure if the reply gets longer than a short paragraph.",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: false
        )
    }

    static func tuning(
        for classification: JarvisTaskClassification,
        settings: JarvisAssistantSettings
    ) -> JarvisGenerationTuning {
        let settingsStyle = settings.responseStyle
        let effectiveCreativity = clamp(settings.creativity, min: 0.0, max: 1.0)

        func resolvedStyle(_ presetStyle: JarvisAssistantResponseStyle) -> JarvisAssistantResponseStyle {
            switch settingsStyle {
            case .concise:
                return .concise
            case .detailed:
                return classification.category == .summarization ? .balanced : .detailed
            case .balanced:
                return presetStyle
            }
        }

        switch classification.preset {
        case .balanced:
            let isPlanning = classification.category == .planning
            let isGreetingLike = classification.category == .generalChat && classification.confidence <= 0.65
            return JarvisGenerationTuning(
                preset: .balanced,
                temperature: isPlanning ? 0.45 : clamp(effectiveCreativity, min: 0.60, max: 0.70),
                topP: 0.90,
                topK: 40,
                typicalP: isPlanning ? 0.94 : 0.95,
                repeatPenalty: isPlanning ? 1.12 : 1.10,
                penaltyLastN: isPlanning ? 96 : 72,
                maxContextTokens: 768,
                maxOutputTokens: isGreetingLike ? 40 : (isPlanning ? 250 : 220),
                maxHistoryCharacters: 2_400,
                maxKnowledgeCharacters: 520,
                repetitionWindowCharacters: isPlanning ? 320 : 280,
                repetitionThreshold: 3,
                requiresGroundedAnswers: false,
                usesReasoningPlan: true,
                responseStyle: resolvedStyle(.balanced)
            )
        case .creative:
            return JarvisGenerationTuning(
                preset: .creative,
                temperature: clamp(max(effectiveCreativity, 0.68), min: 0.68, max: 0.82),
                topP: 0.90,
                topK: 48,
                typicalP: 0.95,
                repeatPenalty: 1.10,
                penaltyLastN: 72,
                maxContextTokens: 640,
                maxOutputTokens: 220,
                maxHistoryCharacters: 2_100,
                maxKnowledgeCharacters: 320,
                repetitionWindowCharacters: 240,
                repetitionThreshold: 3,
                requiresGroundedAnswers: false,
                usesReasoningPlan: true,
                responseStyle: resolvedStyle(.balanced)
            )
        case .precise:
            let isSummary = classification.category == .summarization
            let isQuestion = classification.category == .questionAnswering
            return JarvisGenerationTuning(
                preset: .precise,
                temperature: isSummary ? 0.35 : 0.45,
                topP: isSummary ? 0.82 : 0.88,
                topK: 28,
                typicalP: isSummary ? 0.90 : 0.92,
                repeatPenalty: isSummary ? 1.16 : 1.15,
                penaltyLastN: isSummary ? 112 : 96,
                maxContextTokens: 896,
                maxOutputTokens: isSummary ? 300 : 200,
                maxHistoryCharacters: 1_800,
                maxKnowledgeCharacters: 720,
                repetitionWindowCharacters: isSummary ? 360 : 320,
                repetitionThreshold: 3,
                requiresGroundedAnswers: isSummary || isQuestion || classification.shouldInjectKnowledge,
                usesReasoningPlan: true,
                responseStyle: resolvedStyle(.balanced)
            )
        case .coding:
            return JarvisGenerationTuning(
                preset: .coding,
                temperature: 0.20,
                topP: 0.85,
                topK: 24,
                typicalP: 0.90,
                repeatPenalty: 1.12,
                penaltyLastN: 128,
                maxContextTokens: 1_024,
                maxOutputTokens: 400,
                maxHistoryCharacters: 2_600,
                maxKnowledgeCharacters: 420,
                repetitionWindowCharacters: 360,
                repetitionThreshold: 3,
                requiresGroundedAnswers: true,
                usesReasoningPlan: true,
                responseStyle: resolvedStyle(.balanced)
            )
        case .drafting:
            return JarvisGenerationTuning(
                preset: .drafting,
                temperature: clamp(effectiveCreativity, min: 0.60, max: 0.70),
                topP: 0.90,
                topK: 36,
                typicalP: 0.95,
                repeatPenalty: 1.10,
                penaltyLastN: 72,
                maxContextTokens: 768,
                maxOutputTokens: 220,
                maxHistoryCharacters: 2_100,
                maxKnowledgeCharacters: 360,
                repetitionWindowCharacters: 260,
                repetitionThreshold: 3,
                requiresGroundedAnswers: classification.category == .contextAwareReply,
                usesReasoningPlan: true,
                responseStyle: resolvedStyle(.balanced)
            )
        }
    }

    static func recentHistory(
        from messages: [JarvisChatMessage],
        budget: Int
    ) -> [JarvisChatMessage] {
        let candidates = messages.enumerated().filter { !$0.element.isStreaming }
        guard !candidates.isEmpty else { return [] }

        let latestUserID = candidates.last(where: { $0.element.role == .user })?.element.id
        let latestAssistantID = candidates.last(where: { $0.element.role == .assistant })?.element.id
        let latestSystemID = candidates.last(where: { $0.element.role == .system })?.element.id
        let latestInstructionLikeUserID = candidates.last(where: { candidate in
            candidate.element.role == .user && isInstructionLike(candidate.element.text)
        })?.element.id

        let maxPerMessageCharacters = max(180, min(420, budget / 3))
        var consumed = 0
        var selectedOffsets = Set<Int>()

        func appendCandidate(_ candidate: (offset: Int, element: JarvisChatMessage)) {
            guard !selectedOffsets.contains(candidate.offset) else { return }

            let trimmedMessage = trimmedHistoryMessage(candidate.element, maxCharacters: maxPerMessageCharacters)
            let text = trimmedMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            let cost = min(text.count + 24, maxPerMessageCharacters + 40)
            if !selectedOffsets.isEmpty, consumed + cost > budget {
                return
            }

            consumed += cost
            selectedOffsets.insert(candidate.offset)
        }

        for candidate in candidates.reversed() {
            let identifier = candidate.element.id
            if identifier == latestUserID ||
                identifier == latestAssistantID ||
                identifier == latestSystemID ||
                identifier == latestInstructionLikeUserID {
                appendCandidate(candidate)
            }
        }

        for candidate in candidates.reversed() {
            appendCandidate(candidate)
            if consumed >= budget {
                break
            }
        }

        return candidates
            .filter { selectedOffsets.contains($0.offset) }
            .map { trimmedHistoryMessage($0.element, maxCharacters: maxPerMessageCharacters) }
    }

    static func condensedMemorySummary(
        from messages: [JarvisChatMessage],
        excluding history: [JarvisChatMessage]
    ) -> String? {
        let excludedIDs = Set(history.map(\.id))
        let older = messages
            .filter { !excludedIDs.contains($0.id) && !$0.isStreaming }
            .suffix(6)
            .compactMap { message -> String? in
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let prefix = message.role == .assistant ? "Jarvis" : "User"
                let compact = compactWhitespace(text)
                return "\(prefix): \(compact.prefix(120))"
            }

        guard !older.isEmpty else { return nil }
        return older.joined(separator: "\n")
    }

    static func limitedKnowledge(
        from results: [JarvisKnowledgeResult],
        maxCharacters: Int
    ) -> [JarvisKnowledgeResult] {
        var used = 0
        var trimmed: [JarvisKnowledgeResult] = []

        let prioritized = results.sorted { lhs, rhs in
            let scoreDelta = Swift.abs(lhs.score - rhs.score)
            if scoreDelta > 0.05 {
                return lhs.score > rhs.score
            }
            return lhs.snippet.count < rhs.snippet.count
        }

        for result in prioritized {
            let snippet = compactWhitespace(result.snippet)
            let limitedSnippet = String(snippet.prefix(220))
            let cost = result.item.title.count + limitedSnippet.count
            if !trimmed.isEmpty, used + cost > maxCharacters {
                break
            }
            used += cost
            trimmed.append(
                JarvisKnowledgeResult(
                    item: result.item,
                    score: result.score,
                    snippet: limitedSnippet
                )
            )
        }

        return trimmed
    }

    static func buildPromptEnvelope(
        prompt: String,
        source: String,
        classification: JarvisTaskClassification,
        tuning: JarvisGenerationTuning,
        history: [JarvisChatMessage],
        olderMemorySummary: String?,
        groundedResults: [JarvisKnowledgeResult],
        replyTargetText: String?,
        mode: String
    ) -> JarvisPromptEnvelope {
        let normalizedPrompt = compactWhitespace(prompt)
        let filteredHistory = history.filter { message in
            guard message.role == .user else { return true }
            return compactWhitespace(message.text) != normalizedPrompt
        }

        var contextBlocks: [JarvisPromptContextBlock] = [
            JarvisPromptContextBlock(
                title: "Mode",
                content: "Source: \(source)\nInput mode: \(mode)\nDetected task: \(classification.category.displayName)"
            )
        ]

        if let olderMemorySummary, !olderMemorySummary.isEmpty {
            contextBlocks.append(
                JarvisPromptContextBlock(
                    title: "Prior Context",
                    content: olderMemorySummary
                )
            )
        }

        if let replyTargetText, !replyTargetText.isEmpty {
            contextBlocks.append(
                JarvisPromptContextBlock(
                    title: "Reply",
                    content: replyTargetText
                )
            )
        }

        if !groundedResults.isEmpty {
            let knowledgeContent = groundedResults.map { result in
                "\(result.item.title): \(result.snippet)"
            }.joined(separator: "\n")

            contextBlocks.append(
                JarvisPromptContextBlock(
                    title: "Knowledge",
                    content: knowledgeContent
                )
            )
        }

        let blueprint = JarvisPromptBlueprint(
            systemInstruction: """
            You are Jarvis, a private on-device iPhone assistant designed for fast reasoning, reliable answers, and strong task execution.
            Treat system instructions as highest priority. Use the supplied context first. If the answer is uncertain or under-specified, say what is missing instead of guessing.
            Avoid filler, avoid repeating the user's wording, and do not claim actions or facts you cannot support.
            """,
            assistantRole: "Act like a calm, highly capable iPhone assistant. Be concise, concrete, and easy to scan on a small screen.",
            taskTypeInstruction: taskInstruction(for: classification, tuning: tuning),
            responseInstruction: responseInstruction(for: classification, tuning: tuning),
            contextBlocks: contextBlocks,
            userInputPrefix: classification.shouldPreferStructuredOutput ? "User request. Use structure when it improves speed or clarity:" : "User request:"
        )

        let finalPrompt = """
        \(blueprint.userInputPrefix)
        \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        \(structuredOutputHint(for: classification))
        """
        let debugSummary = "task=\(classification.category.rawValue) preset=\(tuning.preset.rawValue) history=\(history.count) knowledge=\(groundedResults.count)"

        return JarvisPromptEnvelope(
            classification: classification,
            tuning: tuning,
            blueprint: blueprint,
            prompt: finalPrompt,
            history: filteredHistory,
            groundedResults: groundedResults,
            replyTargetText: replyTargetText,
            debugSummary: debugSummary
        )
    }

    static func suggestions(
        for classification: JarvisTaskClassification,
        latestAssistantText: String
    ) -> [JarvisAssistantSuggestionDescriptor] {
        let trimmed = latestAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        switch classification.category {
        case .summarization:
            return [
                .init(title: "Rewrite Shorter", icon: "text.badge.minus", action: .task(.summarize, trimmed)),
                .init(title: "Explain More", icon: "plus.bubble", action: .prompt("Expand the summary with one more layer of detail.")),
                .init(title: "Draft Reply", icon: "arrowshape.turn.up.left", action: .task(.reply, trimmed)),
                .init(title: "Save", icon: "bookmark", action: .saveToKnowledge),
                .init(title: "Voice Follow-up", icon: "waveform", action: .voiceFollowUp)
            ]
        case .draftingEmail, .draftingMessage, .contextAwareReply, .rewritingText:
            return [
                .init(title: "More Direct", icon: "arrow.right.to.line", action: .prompt("Rewrite that to sound more direct and concise.")),
                .init(title: "Warmer Tone", icon: "heart.text.square", action: .prompt("Rewrite that with a warmer, more human tone.")),
                .init(title: "Shorter", icon: "text.badge.minus", action: .prompt("Rewrite that in about half the length.")),
                .init(title: "Save", icon: "bookmark", action: .saveToKnowledge),
                .init(title: "Voice Follow-up", icon: "waveform", action: .voiceFollowUp)
            ]
        case .coding:
            return [
                .init(title: "Add Tests", icon: "checklist", action: .prompt("Add the most important test cases for that solution.")),
                .init(title: "Explain Fix", icon: "doc.text.magnifyingglass", action: .prompt("Explain the fix in simpler terms and mention any risks.")),
                .init(title: "Tighten Plan", icon: "hammer", action: .prompt("Turn that into a minimal implementation plan.")),
                .init(title: "Summarize", icon: "text.quote", action: .task(.summarize, trimmed)),
                .init(title: "Save", icon: "bookmark", action: .saveToKnowledge)
            ]
        case .planning:
            return [
                .init(title: "Checklist", icon: "checklist", action: .prompt("Turn that plan into a checklist with priorities.")),
                .init(title: "Shorter Plan", icon: "list.bullet.indent", action: .prompt("Compress that into the shortest actionable version.")),
                .init(title: "Draft Reply", icon: "arrowshape.turn.up.left", action: .task(.reply, trimmed)),
                .init(title: "Search Notes", icon: "magnifyingglass", action: .searchKnowledge(String(trimmed.prefix(100)))),
                .init(title: "Voice Follow-up", icon: "waveform", action: .voiceFollowUp)
            ]
        case .questionAnswering, .explainingSomething:
            return [
                .init(title: "Simpler", icon: "textformat.alt", action: .prompt("Explain that in simpler language.")),
                .init(title: "Example", icon: "lightbulb", action: .prompt("Add one practical example.")),
                .init(title: "Summarize", icon: "text.quote", action: .task(.summarize, trimmed)),
                .init(title: "Search Notes", icon: "magnifyingglass", action: .searchKnowledge(String(trimmed.prefix(100)))),
                .init(title: "Voice Follow-up", icon: "waveform", action: .voiceFollowUp)
            ]
        case .generalChat:
            return [
                .init(title: "Follow-up", icon: "arrow.turn.down.right", action: .prompt("Can you expand with one practical next step?")),
                .init(title: "Summarize", icon: "text.quote", action: .task(.summarize, trimmed)),
                .init(title: "Draft Reply", icon: "arrowshape.turn.up.left", action: .task(.reply, trimmed)),
                .init(title: "Save", icon: "bookmark", action: .saveToKnowledge),
                .init(title: "Voice Follow-up", icon: "waveform", action: .voiceFollowUp)
            ]
        }
    }

    private static func containsAny(_ value: String, in terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }

    private static func taskInstruction(
        for classification: JarvisTaskClassification,
        tuning: JarvisGenerationTuning
    ) -> String {
        var components = [
            "Task type: \(classification.category.displayName).",
            classification.reasoningHint
        ]

        if tuning.usesReasoningPlan {
            components.append("Think step-by-step internally before answering. Do not expose reasoning. Return only the final answer.")
        }

        if tuning.requiresGroundedAnswers || classification.shouldInjectKnowledge {
            components.append("Prefer grounded claims, distinguish facts from inference, and say when the available context is insufficient.")
        }

        return components.joined(separator: " ")
    }

    private static func responseInstruction(
        for classification: JarvisTaskClassification,
        tuning: JarvisGenerationTuning
    ) -> String {
        var components = [
            classification.responseHint,
            tuning.responseStyle.systemInstructionSuffix,
            "Use only as much structure as needed for fast comprehension."
        ]

        if classification.shouldPreferStructuredOutput {
            components.append("When useful, format the answer as: direct answer, key points or steps, then a brief caveat only if needed.")
        }

        if tuning.requiresGroundedAnswers {
            components.append("Do not fabricate specifics. If confidence is limited, say so briefly and continue with the highest-confidence help.")
        }

        return components.joined(separator: " ")
    }

    private static func structuredOutputHint(for classification: JarvisTaskClassification) -> String {
        guard classification.shouldPreferStructuredOutput else { return "" }
        switch classification.category {
        case .coding:
            return "\nPreferred shape: answer first, likely cause, smallest fix, risks or test cases if relevant."
        case .planning:
            return "\nPreferred shape: goal, ordered steps, priorities, next action."
        case .summarization:
            return "\nPreferred shape: one-sentence overview, key points, next actions if implied."
        default:
            return "\nPreferred shape: direct answer, supporting points, brief next step if useful."
        }
    }

    private static func compactWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedHistoryMessage(_ message: JarvisChatMessage, maxCharacters: Int) -> JarvisChatMessage {
        let compact = compactWhitespace(message.text)
        guard compact.count > maxCharacters else {
            var trimmed = message
            trimmed.text = compact
            return trimmed
        }

        var trimmed = message
        trimmed.text = String(compact.prefix(maxCharacters - 1)) + "…"
        return trimmed
    }

    private static func isInstructionLike(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return containsAny(normalized, in: [
            "please",
            "use this",
            "make sure",
            "don't",
            "do not",
            "format",
            "answer in",
            "keep it",
            "focus on"
        ])
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
