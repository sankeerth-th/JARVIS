import Foundation

public enum ContextBlockType: String, Codable, CaseIterable {
    case task
    case conversation
    case knowledge
    case replyTarget
    case system
    case assistantState
    case memory

    public var priority: Int {
        switch self {
        case .system:
            return 0
        case .assistantState:
            return 1
        case .task:
            return 2
        case .replyTarget:
            return 3
        case .knowledge:
            return 4
        case .conversation:
            return 5
        case .memory:
            return 6
        }
    }
}

public struct ContextBlock: Equatable, Identifiable {
    public let id = UUID()
    public let type: ContextBlockType
    public let title: String
    public let content: String
    public let priority: Int
    public let isOptional: Bool

    public init(
        type: ContextBlockType,
        title: String,
        content: String,
        priority: Int? = nil,
        isOptional: Bool = false
    ) {
        self.type = type
        self.title = title
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.priority = priority ?? type.priority
        self.isOptional = isOptional
    }
}

public struct ContextMetadata: Equatable {
    public let totalBlocks: Int
    public let totalCharacters: Int
    public let estimatedTokens: Int
    public let blockTypes: [ContextBlockType]

    public init(
        totalBlocks: Int = 0,
        totalCharacters: Int = 0,
        estimatedTokens: Int = 0,
        blockTypes: [ContextBlockType] = []
    ) {
        self.totalBlocks = totalBlocks
        self.totalCharacters = totalCharacters
        self.estimatedTokens = estimatedTokens
        self.blockTypes = blockTypes
    }
}

public struct ContextAssembly: Equatable {
    public let systemInstruction: String
    public let assistantRole: String
    public let taskInstruction: String
    public let responseInstruction: String
    public let contextBlocks: [JarvisPromptContextBlock]
    public let recentMessages: [JarvisChatMessage]
    public let knowledgeResults: [JarvisKnowledgeResult]
    public let metadata: ContextMetadata

    public init(
        systemInstruction: String,
        assistantRole: String,
        taskInstruction: String,
        responseInstruction: String,
        contextBlocks: [JarvisPromptContextBlock] = [],
        recentMessages: [JarvisChatMessage] = [],
        knowledgeResults: [JarvisKnowledgeResult] = [],
        metadata: ContextMetadata = ContextMetadata()
    ) {
        self.systemInstruction = systemInstruction
        self.assistantRole = assistantRole
        self.taskInstruction = taskInstruction
        self.responseInstruction = responseInstruction
        self.contextBlocks = contextBlocks
        self.recentMessages = recentMessages
        self.knowledgeResults = knowledgeResults
        self.metadata = metadata
    }
}

@MainActor
public final class ContextBuilder {
    private var blocks: [ContextBlock] = []
    private let maxTotalCharacters: Int

    public init(maxTotalCharacters: Int = 4_200) {
        self.maxTotalCharacters = maxTotalCharacters
    }

    public func build(
        request: JarvisOrchestrationRequest,
        classification: JarvisTaskClassification,
        memoryContext: MemoryContext,
        resolvedSkill: JarvisResolvedSkill
    ) -> ContextAssembly {
        blocks.removeAll()

        addSystemBlock()
        addAssistantRoleBlock()
        addTaskBlock(classification: classification, mode: request.mode, resolvedSkill: resolvedSkill)
        addConversationBlock(memoryContext: memoryContext, resolvedSkill: resolvedSkill)
        addKnowledgeBlock(knowledgeResults: request.knowledgeResults, classification: classification, resolvedSkill: resolvedSkill)
        if resolvedSkill.policy.includeReplyTarget {
            addReplyTargetBlock(replyTargetText: request.replyTargetText)
        }

        blocks.sort { $0.priority < $1.priority }
        pruneBlocksIfNeeded()

        let promptBlocks = blocks.map { JarvisPromptContextBlock(title: $0.title, content: $0.content) }
        let metadata = ContextMetadata(
            totalBlocks: blocks.count,
            totalCharacters: blocks.reduce(0) { $0 + $1.content.count },
            estimatedTokens: blocks.reduce(0) { $0 + $1.content.count } / 4,
            blockTypes: blocks.map(\.type)
        )

        return ContextAssembly(
            systemInstruction: JarvisPromptBlueprint.default.systemInstruction,
            assistantRole: "You are Jarvis, a proactive iPhone assistant. Reason cleanly, act on the user's intent, and optimize for usefulness on a phone-sized screen.",
            taskInstruction: "Task type: \(classification.category.displayName). Skill: \(resolvedSkill.skill.name). \(classification.reasoningHint)",
            responseInstruction: ([classification.responseHint, request.mode.responseHint] + resolvedSkill.skill.formattingHints).joined(separator: " "),
            contextBlocks: promptBlocks,
            recentMessages: memoryContext.recentMessages,
            knowledgeResults: request.knowledgeResults,
            metadata: metadata
        )
    }

    private func addSystemBlock() {
        blocks.append(
            ContextBlock(
                type: .system,
                title: "",
                content: """
                You are Jarvis, a private on-device AI assistant designed for fast reasoning, clear answers, and intelligent help with everyday tasks.
                Lead with the answer, stay concrete, and be useful immediately.
                Do not mention the model, runtime, or device constraints unless the user asks.
                """
            )
        )
    }

    private func addAssistantRoleBlock() {
        blocks.append(
            ContextBlock(
                type: .assistantState,
                title: "Assistant Role",
                content: "Behave like a proactive assistant. Use structure when it makes the response easier to scan on a phone."
            )
        )
    }

    private func addTaskBlock(classification: JarvisTaskClassification, mode: JarvisAssistantMode, resolvedSkill: JarvisResolvedSkill) {
        blocks.append(
            ContextBlock(
                type: .task,
                title: "Task",
                content: "Detected task: \(classification.category.displayName)\nMode: \(mode.displayName)\nSkill: \(resolvedSkill.skill.name)\n\(classification.reasoningHint)"
            )
        )
    }

    private func addConversationBlock(memoryContext: MemoryContext, resolvedSkill: JarvisResolvedSkill) {
        var parts: [String] = []
        if resolvedSkill.policy.includeSummary, let summary = memoryContext.summary {
            parts.append("Prior summary: \(summary.summaryText)")
            if let openTasks = summary.openTasks, !openTasks.isEmpty {
                parts.append("Open tasks: \(openTasks.joined(separator: "; "))")
            }
            if let followUps = summary.unresolvedFollowUps, !followUps.isEmpty {
                parts.append("Unresolved follow-ups: \(followUps.joined(separator: "; "))")
            }
        }

        if !memoryContext.recentMessages.isEmpty {
            parts.append("Recent conversation:")
            for message in memoryContext.recentMessages.suffix(resolvedSkill.policy.recentMessageLimit) {
                let role = message.role == .assistant ? "Jarvis" : "User"
                parts.append("\(role): \(String(message.text.prefix(220)))")
            }
        }

        guard !parts.isEmpty else { return }

        blocks.append(
            ContextBlock(
                type: .conversation,
                title: "Conversation Context",
                content: parts.joined(separator: "\n"),
                isOptional: true
            )
        )
    }

    private func addKnowledgeBlock(
        knowledgeResults: [JarvisKnowledgeResult],
        classification: JarvisTaskClassification,
        resolvedSkill: JarvisResolvedSkill
    ) {
        guard classification.shouldInjectKnowledge else { return }
        guard !knowledgeResults.isEmpty else { return }

        let content = knowledgeResults.prefix(max(1, resolvedSkill.policy.knowledgeLimit)).map { result in
            "- \(result.item.title): \(result.snippet)"
        }
        .joined(separator: "\n")

        blocks.append(
            ContextBlock(
                type: .knowledge,
                title: "Knowledge Context",
                content: content,
                isOptional: true
            )
        )
    }

    private func addReplyTargetBlock(replyTargetText: String?) {
        guard let replyTargetText, !replyTargetText.isEmpty else { return }

        blocks.append(
            ContextBlock(
                type: .replyTarget,
                title: "Reply Target",
                content: replyTargetText
            )
        )
    }

    private func pruneBlocksIfNeeded() {
        var current = blocks.reduce(0) { $0 + $1.content.count }
        guard current > maxTotalCharacters else { return }

        for block in blocks.sorted(by: { $0.priority > $1.priority }) where block.isOptional {
            guard current > maxTotalCharacters else { break }
            blocks.removeAll { $0.id == block.id }
            current -= block.content.count
        }
    }
}
