import Foundation

public enum JarvisAssistantCardKind: String, Codable, Equatable {
    case draft
    case action
    case checklist
    case clarification
    case summary
}

public struct JarvisAssistantCard: Identifiable, Codable, Equatable {
    public let id: UUID
    public var kind: JarvisAssistantCardKind
    public var title: String
    public var body: String
    public var items: [String]
    public var callout: String?

    public init(
        id: UUID = UUID(),
        kind: JarvisAssistantCardKind,
        title: String,
        body: String = "",
        items: [String] = [],
        callout: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.items = items
        self.callout = callout?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct JarvisAssistantStructuredOutput: Codable, Equatable {
    public var cards: [JarvisAssistantCard]

    public init(cards: [JarvisAssistantCard] = []) {
        self.cards = cards
    }

    public var isEmpty: Bool {
        cards.isEmpty
    }
}

public struct JarvisMessageMemoryAttribution: Codable, Equatable {
    public var labels: [String]
    public var usedSummary: Bool

    public init(labels: [String] = [], usedSummary: Bool = false) {
        self.labels = labels
        self.usedSummary = usedSummary
    }

    public var displayText: String? {
        if !labels.isEmpty {
            return "Used memory: \(labels.joined(separator: ", "))"
        }
        if usedSummary {
            return "Used conversation summary"
        }
        return nil
    }
}
