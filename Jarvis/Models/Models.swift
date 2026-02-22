import Foundation
import SwiftUI

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var role: ChatRole
    var text: String
    var createdAt: Date
    var metadata: [String: String]
    var citations: [String]
    var isStreaming: Bool
    var toolCall: ToolInvocation?
    var toolResult: ToolResult?

    init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = .init(), metadata: [String: String] = [:], citations: [String] = [], isStreaming: Bool = false, toolCall: ToolInvocation? = nil, toolResult: ToolResult? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.metadata = metadata
        self.citations = citations
        self.isStreaming = isStreaming
        self.toolCall = toolCall
        self.toolResult = toolResult
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var model: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var isPinned: Bool

    init(id: UUID = UUID(), title: String, model: String, createdAt: Date = .init(), updatedAt: Date = .init(), messages: [ChatMessage] = [], isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.isPinned = isPinned
    }
}

enum DocumentType: String, Codable {
    case text
    case markdown
    case pdf
    case docx
    case unknown
}

struct Document: Identifiable, Codable {
    let id: UUID
    let url: URL?
    let type: DocumentType
    let title: String
    let content: String
    let lastModified: Date?
    let metadata: [String: String]

    init(id: UUID = UUID(), url: URL? = nil, type: DocumentType, title: String, content: String, lastModified: Date? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.url = url
        self.type = type
        self.title = title
        self.content = content
        self.lastModified = lastModified
        self.metadata = metadata
    }
}

enum DocumentAction: String, CaseIterable, Identifiable {
    case summarize = "Summarize"
    case bulletKeyPoints = "Bullet key points"
    case actionItems = "Action items"
    case rewriteCleaner = "Rewrite cleaner"
    case fixGrammar = "Fix grammar"
    case convertToTable = "Convert to table"

    var id: String { rawValue }
}

struct NotificationItem: Identifiable, Codable, Equatable {
    enum Priority: String, Codable, CaseIterable {
        case urgent
        case needsReply
        case fyi
        case low
    }

    let id: UUID
    let appIdentifier: String
    let title: String
    let body: String
    let date: Date
    var priority: Priority
    var suggestedResponse: String?
    var metadata: [String: String]

    init(id: UUID = UUID(), appIdentifier: String, title: String, body: String, date: Date = .init(), priority: Priority = .fyi, suggestedResponse: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.appIdentifier = appIdentifier
        self.title = title
        self.body = body
        self.date = date
        self.priority = priority
        self.suggestedResponse = suggestedResponse
        self.metadata = metadata
    }
}

struct NotificationRule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var keywords: [String]
    var apps: [String]
    var quietHours: QuietHours?
    var focusMode: Bool
    var priority: NotificationItem.Priority

    init(id: UUID = UUID(), name: String, keywords: [String] = [], apps: [String] = [], quietHours: QuietHours? = nil, focusMode: Bool = false, priority: NotificationItem.Priority = .fyi) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.apps = apps
        self.quietHours = quietHours
        self.focusMode = focusMode
        self.priority = priority
    }
}

struct QuietHours: Codable, Equatable {
    var start: DateComponents
    var end: DateComponents
}

struct MacroStep: Codable, Identifiable, Equatable {
    enum StepKind: String, Codable {
        case summarizeNotifications
        case summarizeDocuments
        case summarizeCalendar
        case runPrompt
        case runTool
    }

    let id: UUID
    var kind: StepKind
    var payload: [String: String]

    init(id: UUID = UUID(), kind: StepKind, payload: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.payload = payload
    }
}

struct Macro: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var steps: [MacroStep]
    var scheduleDescription: String?

    init(id: UUID = UUID(), name: String, steps: [MacroStep], scheduleDescription: String? = nil) {
        self.id = id
        self.name = name
        self.steps = steps
        self.scheduleDescription = scheduleDescription
    }
}

enum ToneStyle: String, Codable, CaseIterable {
    case professional
    case friendly
    case direct

    var promptValue: String {
        switch self {
        case .professional: return "professional but warm"
        case .friendly: return "friendly and casual"
        case .direct: return "direct and concise"
        }
    }
}

struct AppSettings: Codable {
    var selectedModel: String
    var systemPrompt: String
    var tone: ToneStyle
    var disableLogging: Bool
    var clipboardWatcherEnabled: Bool
    var privacyStatus: PrivacyStatus
    var quickActions: [QuickAction]

    static let `default` = AppSettings(
        selectedModel: "mistral",
        systemPrompt: "You are Jarvis, an offline-first macOS assistant. Keep answers concise, cite snippets, and never claim to have seen data you were not given.",
        tone: .professional,
        disableLogging: false,
        clipboardWatcherEnabled: false,
        privacyStatus: .offline,
        quickActions: QuickAction.defaults
    )
}

enum PrivacyStatus: String, Codable {
    case offline
    case online

    var description: String {
        switch self {
        case .offline: return "Offline (Ollama local)"
        case .online: return "Online (optional)"
        }
    }
}

struct QuickAction: Identifiable, Codable, Equatable {
    enum ActionKind: String, Codable {
        case summarizeClipboard
        case fixClipboardGrammar
        case makeChecklist
        case draftEmail
        case extractTable
        case meetingSummary
        case codeHelper
        case searchKnowledgeBase
        case workflowMacro
    }

    let id: UUID
    var title: String
    var kind: ActionKind
    var icon: String

    init(id: UUID = UUID(), title: String, kind: ActionKind, icon: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.icon = icon
    }

    static let defaults: [QuickAction] = [
        QuickAction(title: "Summarize clipboard", kind: .summarizeClipboard, icon: "text.book.closed"),
        QuickAction(title: "Fix grammar", kind: .fixClipboardGrammar, icon: "wand.and.sparkles"),
        QuickAction(title: "Checklist", kind: .makeChecklist, icon: "checklist"),
        QuickAction(title: "Draft email", kind: .draftEmail, icon: "envelope"),
        QuickAction(title: "Extract table", kind: .extractTable, icon: "table"),
        QuickAction(title: "Meeting recap", kind: .meetingSummary, icon: "person.3.sequence"),
        QuickAction(title: "Code helper", kind: .codeHelper, icon: "curlybraces"),
        QuickAction(title: "Search docs", kind: .searchKnowledgeBase, icon: "magnifyingglass"),
        QuickAction(title: "Run macro", kind: .workflowMacro, icon: "gear" )
    ]
}

struct ToolInvocation: Codable {
    enum ToolName: String, Codable {
        case calculate
        case ocrCurrentWindow
        case listNotifications
        case searchLocalDocs
        case summarize
    }

    var name: ToolName
    var arguments: [String: String]
}

struct ToolResult: Codable {
    var content: String
    var metadata: [String: String]
}

struct CalculationResult: Equatable {
    let expression: String
    let result: Decimal
    let steps: [String]
}

struct TableExtractionResult: Equatable {
    enum OutputFormat: String {
        case markdown
        case csv
        case json
    }

    let headers: [String]
    let rows: [[String]]
}

struct IndexedDocument: Identifiable, Codable {
    let id: UUID
    var title: String
    var path: String
    var embedding: [Double]
    var lastIndexed: Date

    init(id: UUID = UUID(), title: String, path: String, embedding: [Double], lastIndexed: Date = .init()) {
        self.id = id
        self.title = title
        self.path = path
        self.embedding = embedding
        self.lastIndexed = lastIndexed
    }
}
