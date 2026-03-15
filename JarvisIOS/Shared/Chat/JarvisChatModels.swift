import Foundation

public enum JarvisChatRole: String, Codable {
    case user
    case assistant
    case system
}

public struct JarvisChatMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public var role: JarvisChatRole
    public var text: String
    public var createdAt: Date
    public var isStreaming: Bool
    public var structuredOutput: JarvisAssistantStructuredOutput?
    public var memoryAttribution: JarvisMessageMemoryAttribution?

    public init(
        id: UUID = UUID(),
        role: JarvisChatRole,
        text: String,
        createdAt: Date = Date(),
        isStreaming: Bool = false,
        structuredOutput: JarvisAssistantStructuredOutput? = nil,
        memoryAttribution: JarvisMessageMemoryAttribution? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.structuredOutput = structuredOutput
        self.memoryAttribution = memoryAttribution
    }
}

public struct JarvisConversationRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var updatedAt: Date
    public var messages: [JarvisChatMessage]

    public init(id: UUID = UUID(), title: String = "New Conversation", updatedAt: Date = Date(), messages: [JarvisChatMessage] = []) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

public struct JarvisKnowledgeItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var text: String
    public var source: String
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, text: String, source: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.text = text
        self.source = source
        self.createdAt = createdAt
    }
}

public struct JarvisKnowledgeResult: Identifiable, Equatable {
    public let id = UUID()
    public var item: JarvisKnowledgeItem
    public var score: Double
    public var snippet: String

    public init(item: JarvisKnowledgeItem, score: Double, snippet: String) {
        self.item = item
        self.score = score
        self.snippet = snippet
    }
}

public enum JarvisAssistantTask: String, Codable, CaseIterable, Equatable {
    case chat
    case summarize
    case reply
    case draftEmail
    case analyzeText
    case visualDescribe
    case prioritizeNotifications
    case quickCapture
    case knowledgeAnswer

    public var displayName: String {
        switch self {
        case .chat:
            return "Chat"
        case .summarize:
            return "Summarize"
        case .reply:
            return "Reply"
        case .draftEmail:
            return "Draft Email"
        case .analyzeText:
            return "Analyze Text"
        case .visualDescribe:
            return "Visual Describe"
        case .prioritizeNotifications:
            return "Prioritize Notifications"
        case .quickCapture:
            return "Quick Capture"
        case .knowledgeAnswer:
            return "Knowledge Answer"
        }
    }

    public var historyLimit: Int {
        switch self {
        case .chat:
            return 12
        case .summarize:
            return 4
        case .reply, .draftEmail:
            return 6
        case .analyzeText:
            return 6
        case .visualDescribe:
            return 3
        case .prioritizeNotifications:
            return 5
        case .quickCapture:
            return 3
        case .knowledgeAnswer:
            return 8
        }
    }

    public var groundingLimit: Int {
        switch self {
        case .knowledgeAnswer:
            return 4
        case .chat, .summarize, .reply, .draftEmail, .analyzeText, .visualDescribe, .prioritizeNotifications, .quickCapture:
            return 2
        }
    }
}

public struct JarvisAssistantTaskContext: Equatable {
    public var task: JarvisAssistantTask
    public var source: String
    public var seedText: String?
    public var replyTargetText: String?
    public var groundedResults: [JarvisKnowledgeResult]

    public init(
        task: JarvisAssistantTask,
        source: String,
        seedText: String? = nil,
        replyTargetText: String? = nil,
        groundedResults: [JarvisKnowledgeResult] = []
    ) {
        self.task = task
        self.source = source
        self.seedText = seedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.replyTargetText = replyTargetText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.groundedResults = groundedResults
    }
}

public struct JarvisAssistantRequest: Equatable {
    public var task: JarvisAssistantTask
    public var prompt: String
    public var source: String
    public var history: [JarvisChatMessage]
    public var groundedResults: [JarvisKnowledgeResult]
    public var replyTargetText: String?
    public var classification: JarvisTaskClassification
    public var promptBlueprint: JarvisPromptBlueprint
    public var tuning: JarvisGenerationTuning
    public var debugSummary: String

    public init(
        task: JarvisAssistantTask,
        prompt: String,
        source: String,
        history: [JarvisChatMessage],
        groundedResults: [JarvisKnowledgeResult] = [],
        replyTargetText: String? = nil,
        classification: JarvisTaskClassification = .default,
        promptBlueprint: JarvisPromptBlueprint = .default,
        tuning: JarvisGenerationTuning = .balanced,
        debugSummary: String = ""
    ) {
        self.task = task
        self.prompt = prompt
        self.source = source
        self.history = history
        self.groundedResults = groundedResults
        self.replyTargetText = replyTargetText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.classification = classification
        self.promptBlueprint = promptBlueprint
        self.tuning = tuning
        self.debugSummary = debugSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
