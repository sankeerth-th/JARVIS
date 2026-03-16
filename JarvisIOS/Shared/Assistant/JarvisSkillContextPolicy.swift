import Foundation

public enum JarvisSkillContextSource: String, Codable, CaseIterable, Equatable {
    case recentMessages
    case conversationSummary
    case projectMemory
    case taskMemory
    case preferenceMemory
    case knowledge
    case replyTarget
    case constraints
}

public enum JarvisSkillOutputKind: String, Codable, Equatable {
    case text
    case codeAnswer
    case draft
    case checklist
    case knowledgeAnswer
    case clarification
    case brainstorm
    case summary
}

public struct JarvisSkillContextPolicy: Equatable, Codable {
    public let recentMessageLimit: Int
    public let includeSummary: Bool
    public let knowledgeLimit: Int
    public let maxMemoryItems: Int
    public let maxMemoryCharacters: Int
    public let includeReplyTarget: Bool

    public init(
        recentMessageLimit: Int,
        includeSummary: Bool,
        knowledgeLimit: Int,
        maxMemoryItems: Int,
        maxMemoryCharacters: Int,
        includeReplyTarget: Bool
    ) {
        self.recentMessageLimit = recentMessageLimit
        self.includeSummary = includeSummary
        self.knowledgeLimit = knowledgeLimit
        self.maxMemoryItems = maxMemoryItems
        self.maxMemoryCharacters = maxMemoryCharacters
        self.includeReplyTarget = includeReplyTarget
    }
}

public struct JarvisResolvedSkill: Equatable, Codable {
    public let skill: JarvisSkill
    public let policy: JarvisSkillContextPolicy

    public init(skill: JarvisSkill, policy: JarvisSkillContextPolicy) {
        self.skill = skill
        self.policy = policy
    }
}

public enum JarvisSkillPolicyResolver {
    public static func resolve(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) -> JarvisResolvedSkill {
        let skill = JarvisSkillCatalog.resolve(for: request, classification: classification)
        return JarvisResolvedSkill(
            skill: skill,
            policy: policy(for: skill, classification: classification)
        )
    }

    public static func policy(
        for skill: JarvisSkill,
        classification: JarvisTaskClassification
    ) -> JarvisSkillContextPolicy {
        switch skill.id {
        case "code_generation", "code_explanation":
            return JarvisSkillContextPolicy(
                recentMessageLimit: 4,
                includeSummary: true,
                knowledgeLimit: 1,
                maxMemoryItems: 4,
                maxMemoryCharacters: 440,
                includeReplyTarget: false
            )
        case "draft_email", "draft_message", "rewrite_text":
            return JarvisSkillContextPolicy(
                recentMessageLimit: 5,
                includeSummary: true,
                knowledgeLimit: 0,
                maxMemoryItems: 3,
                maxMemoryCharacters: 320,
                includeReplyTarget: true
            )
        case "planning":
            return JarvisSkillContextPolicy(
                recentMessageLimit: 5,
                includeSummary: true,
                knowledgeLimit: 1,
                maxMemoryItems: 4,
                maxMemoryCharacters: 420,
                includeReplyTarget: false
            )
        case "knowledge_lookup", "answer_question":
            return JarvisSkillContextPolicy(
                recentMessageLimit: 4,
                includeSummary: true,
                knowledgeLimit: classification.shouldInjectKnowledge ? 4 : 2,
                maxMemoryItems: 4,
                maxMemoryCharacters: 360,
                includeReplyTarget: false
            )
        case "summarization":
            return JarvisSkillContextPolicy(
                recentMessageLimit: 3,
                includeSummary: false,
                knowledgeLimit: 1,
                maxMemoryItems: 2,
                maxMemoryCharacters: 220,
                includeReplyTarget: false
            )
        case "brainstorm":
            return JarvisSkillContextPolicy(
                recentMessageLimit: 4,
                includeSummary: true,
                knowledgeLimit: 1,
                maxMemoryItems: 3,
                maxMemoryCharacters: 280,
                includeReplyTarget: false
            )
        default:
            return JarvisSkillContextPolicy(
                recentMessageLimit: max(3, classification.task.historyLimit - 1),
                includeSummary: true,
                knowledgeLimit: classification.task.groundingLimit,
                maxMemoryItems: 3,
                maxMemoryCharacters: 300,
                includeReplyTarget: true
            )
        }
    }
}
