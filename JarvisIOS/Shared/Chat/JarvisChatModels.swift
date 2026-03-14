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

    public init(id: UUID = UUID(), role: JarvisChatRole, text: String, createdAt: Date = Date(), isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isStreaming = isStreaming
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
