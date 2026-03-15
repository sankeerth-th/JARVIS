import Foundation

public enum JarvisMemoryKind: String, Codable, CaseIterable, Equatable {
    case preference
    case personalFact
    case project
    case task
    case conversationSummary
    case recentContext

    public var promptTitle: String {
        switch self {
        case .preference:
            return "User Preference"
        case .personalFact:
            return "Personal Fact"
        case .project:
            return "Project Context"
        case .task:
            return "Task Context"
        case .conversationSummary:
            return "Conversation Summary"
        case .recentContext:
            return "Recent Context"
        }
    }

    public var retrievalWeight: Double {
        switch self {
        case .preference:
            return 2.8
        case .project:
            return 2.4
        case .task:
            return 2.1
        case .personalFact:
            return 2.0
        case .conversationSummary:
            return 1.7
        case .recentContext:
            return 1.2
        }
    }
}

public struct JarvisMemoryRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public var kind: JarvisMemoryKind
    public var title: String
    public var content: String
    public var normalizedContent: String
    public var conversationID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastAccessedAt: Date?
    public var confidence: Double
    public var importance: Double
    public var isPinned: Bool
    public var tags: [String]
    public var entityHints: [String]
    public var embeddingPlaceholder: String?

    public init(
        id: UUID = UUID(),
        kind: JarvisMemoryKind,
        title: String,
        content: String,
        normalizedContent: String? = nil,
        conversationID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        confidence: Double = 0.5,
        importance: Double = 0.5,
        isPinned: Bool = false,
        tags: [String] = [],
        entityHints: [String] = [],
        embeddingPlaceholder: String? = nil
    ) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.kind = kind
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.content = trimmedContent
        self.normalizedContent = normalizedContent ?? JarvisMemoryText.normalize(trimmedContent)
        self.conversationID = conversationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAccessedAt = lastAccessedAt
        self.confidence = confidence
        self.importance = importance
        self.isPinned = isPinned
        self.tags = tags
        self.entityHints = entityHints
        self.embeddingPlaceholder = embeddingPlaceholder
    }
}

public struct JarvisMemoryMatch: Equatable, Identifiable {
    public let id: UUID
    public let record: JarvisMemoryRecord
    public let score: Double
    public let reasons: [String]

    public init(record: JarvisMemoryRecord, score: Double, reasons: [String]) {
        self.id = record.id
        self.record = record
        self.score = score
        self.reasons = reasons
    }
}

public struct ConversationSummary: Identifiable, Codable, Equatable {
    public let id: UUID
    public let conversationID: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public let messageCount: Int
    public let summaryText: String
    public let keyTopics: [String]
    public let userIntent: String
    public let assistantActions: [String]

    public init(
        id: UUID = UUID(),
        conversationID: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messageCount: Int,
        summaryText: String,
        keyTopics: [String] = [],
        userIntent: String = "",
        assistantActions: [String] = []
    ) {
        self.id = id
        self.conversationID = conversationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.summaryText = summaryText
        self.keyTopics = keyTopics
        self.userIntent = userIntent
        self.assistantActions = assistantActions
    }
}

public struct MemoryContext: Equatable {
    public let recentMessages: [JarvisChatMessage]
    public let summary: ConversationSummary?
    public let retrievedMemories: [JarvisMemoryMatch]
    public let totalMessages: Int
    public let compressedMessageCount: Int

    public init(
        recentMessages: [JarvisChatMessage] = [],
        summary: ConversationSummary? = nil,
        retrievedMemories: [JarvisMemoryMatch] = [],
        totalMessages: Int = 0,
        compressedMessageCount: Int = 0
    ) {
        self.recentMessages = recentMessages
        self.summary = summary
        self.retrievedMemories = retrievedMemories
        self.totalMessages = totalMessages
        self.compressedMessageCount = compressedMessageCount
    }

    public var memoryLabels: [String] {
        let kinds = Set(retrievedMemories.map(\.record.kind))
        return kinds.map(\.promptTitle).sorted()
    }

    public var isMemoryInformed: Bool {
        summary != nil || !retrievedMemories.isEmpty
    }
}

public struct MemoryRetentionPolicy: Equatable {
    public var maxRecentMessages: Int
    public var maxSummaryMessages: Int
    public var maxCharactersPerMessage: Int
    public var minMessageAgeForCompression: TimeInterval
    public var enableSemanticCompression: Bool
    public var maxRetrievedMemories: Int
    public var maxStoredMemories: Int

    public init(
        maxRecentMessages: Int = 8,
        maxSummaryMessages: Int = 18,
        maxCharactersPerMessage: Int = 800,
        minMessageAgeForCompression: TimeInterval = 300,
        enableSemanticCompression: Bool = true,
        maxRetrievedMemories: Int = 4,
        maxStoredMemories: Int = 120
    ) {
        self.maxRecentMessages = maxRecentMessages
        self.maxSummaryMessages = maxSummaryMessages
        self.maxCharactersPerMessage = maxCharactersPerMessage
        self.minMessageAgeForCompression = minMessageAgeForCompression
        self.enableSemanticCompression = enableSemanticCompression
        self.maxRetrievedMemories = maxRetrievedMemories
        self.maxStoredMemories = maxStoredMemories
    }

    public static let `default` = MemoryRetentionPolicy()
}

enum JarvisMemoryText {
    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func terms(for text: String) -> [String] {
        Array(
            Set(
                normalize(text)
                    .split(separator: " ")
                    .map(String.init)
                    .filter { $0.count > 1 }
            )
        )
    }
}
