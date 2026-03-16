import Foundation

public enum JarvisAssistantCardKind: String, Codable, Equatable {
    case draft
    case action
    case checklist
    case clarification
    case summary
    case codeAnswer
    case codeBlock
    case knowledgeAnswer
    case decisionTree
    case prosCons
    case brainstorm
    case multiStepPlan
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
    public var usedMemory: Bool
    public var memorySourceIDs: [UUID]
    public var sourceKinds: [JarvisMemoryKind]
    public var labels: [String]
    public var usedSummary: Bool
    public var chosenSkillID: String?

    public init(
        usedMemory: Bool = false,
        memorySourceIDs: [UUID] = [],
        sourceKinds: [JarvisMemoryKind] = [],
        labels: [String] = [],
        usedSummary: Bool = false,
        chosenSkillID: String? = nil
    ) {
        self.usedMemory = usedMemory
        self.memorySourceIDs = memorySourceIDs
        self.sourceKinds = sourceKinds
        self.labels = labels
        self.usedSummary = usedSummary
        self.chosenSkillID = chosenSkillID
    }

    private enum CodingKeys: String, CodingKey {
        case usedMemory
        case memorySourceIDs
        case sourceKinds
        case labels
        case usedSummary
        case chosenSkillID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedMemory = try container.decodeIfPresent(Bool.self, forKey: .usedMemory) ?? false
        self.memorySourceIDs = try container.decodeIfPresent([UUID].self, forKey: .memorySourceIDs) ?? []
        self.sourceKinds = try container.decodeIfPresent([JarvisMemoryKind].self, forKey: .sourceKinds) ?? []
        self.labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        self.usedSummary = try container.decodeIfPresent(Bool.self, forKey: .usedSummary) ?? false
        self.chosenSkillID = try container.decodeIfPresent(String.self, forKey: .chosenSkillID)
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
