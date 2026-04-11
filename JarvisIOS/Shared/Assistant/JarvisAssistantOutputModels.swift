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
    public var capabilitySurfaces: [JarvisAssistantCapabilitySurface]

    public init(
        cards: [JarvisAssistantCard] = [],
        capabilitySurfaces: [JarvisAssistantCapabilitySurface] = []
    ) {
        self.cards = cards
        self.capabilitySurfaces = capabilitySurfaces
    }

    public var isEmpty: Bool {
        cards.isEmpty && capabilitySurfaces.isEmpty
    }
}

public enum JarvisAssistantCapabilityStatus: String, Codable, Equatable {
    case pending
    case executing
    case success
    case failed
    case denied
    case unsupported
    case cancelled
}

public enum JarvisAssistantCapabilitySurfaceKind: String, Codable, Equatable {
    case fileSearchResults
    case filePreview
    case patchApproval
    case allowedRoots
    case macAction
    case shellResult
    case projectAction
}

public struct JarvisAssistantCapabilityFact: Identifiable, Codable, Equatable {
    public let id: UUID
    public var label: String
    public var value: String

    public init(id: UUID = UUID(), label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct JarvisAssistantCapabilityEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var subtitle: String?
    public var facts: [JarvisAssistantCapabilityFact]

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        facts: [JarvisAssistantCapabilityFact] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.facts = facts
    }
}

public enum JarvisAssistantApprovalDecision: String, Codable, Equatable {
    case pending
    case approved
    case denied
}

public struct JarvisAssistantApprovalSurface: Codable, Equatable {
    public var scenarioID: String
    public var title: String
    public var message: String
    public var approveTitle: String
    public var denyTitle: String
    public var decision: JarvisAssistantApprovalDecision
    public var runtimeHookAvailable: Bool

    public init(
        scenarioID: String,
        title: String,
        message: String,
        approveTitle: String = "Approve",
        denyTitle: String = "Deny",
        decision: JarvisAssistantApprovalDecision = .pending,
        runtimeHookAvailable: Bool = false
    ) {
        self.scenarioID = scenarioID
        self.title = title
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.approveTitle = approveTitle
        self.denyTitle = denyTitle
        self.decision = decision
        self.runtimeHookAvailable = runtimeHookAvailable
    }
}

public struct JarvisAssistantCapabilitySurface: Identifiable, Codable, Equatable {
    public let id: UUID
    public var kind: JarvisAssistantCapabilitySurfaceKind
    public var title: String
    public var status: JarvisAssistantCapabilityStatus
    public var summary: String
    public var entries: [JarvisAssistantCapabilityEntry]
    public var previewText: String?
    public var footnote: String?
    public var approval: JarvisAssistantApprovalSurface?

    public init(
        id: UUID = UUID(),
        kind: JarvisAssistantCapabilitySurfaceKind,
        title: String,
        status: JarvisAssistantCapabilityStatus,
        summary: String = "",
        entries: [JarvisAssistantCapabilityEntry] = [],
        previewText: String? = nil,
        footnote: String? = nil,
        approval: JarvisAssistantApprovalSurface? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.status = status
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.entries = entries
        self.previewText = previewText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.footnote = footnote?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.approval = approval
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
