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
    case image
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

struct AppSettings: Codable, Equatable {
    var selectedModel: String
    var systemPrompt: String
    var tone: ToneStyle
    var disableLogging: Bool
    var clipboardWatcherEnabled: Bool
    var privacyStatus: PrivacyStatus
    var quickActions: [QuickAction]
    var indexedFolders: [String]
    var focusModeEnabled: Bool
    var focusPriorityApps: [String]
    var focusAllowUrgent: Bool
    var quietHoursStartHour: Int
    var quietHoursEndHour: Int
    var privacyGuardianEnabled: Bool
    var privacyClipboardMonitorEnabled: Bool
    var privacySensitiveDetectionEnabled: Bool
    var privacyNetworkMonitorEnabled: Bool

    static let `default` = AppSettings(
        selectedModel: "mistral",
        systemPrompt: "You are Jarvis, an offline-first macOS assistant. Keep answers concise, cite snippets, and never claim to have seen data you were not given.",
        tone: .professional,
        disableLogging: false,
        clipboardWatcherEnabled: false,
        privacyStatus: .offline,
        quickActions: QuickAction.defaults,
        indexedFolders: [],
        focusModeEnabled: false,
        focusPriorityApps: ["com.apple.mail", "com.apple.MobileSMS", "com.tinyspeck.slackmacgap"],
        focusAllowUrgent: true,
        quietHoursStartHour: 22,
        quietHoursEndHour: 7,
        privacyGuardianEnabled: false,
        privacyClipboardMonitorEnabled: false,
        privacySensitiveDetectionEnabled: true,
        privacyNetworkMonitorEnabled: true
    )

    enum CodingKeys: String, CodingKey {
        case selectedModel
        case systemPrompt
        case tone
        case disableLogging
        case clipboardWatcherEnabled
        case privacyStatus
        case quickActions
        case indexedFolders
        case focusModeEnabled
        case focusPriorityApps
        case focusAllowUrgent
        case quietHoursStartHour
        case quietHoursEndHour
        case privacyGuardianEnabled
        case privacyClipboardMonitorEnabled
        case privacySensitiveDetectionEnabled
        case privacyNetworkMonitorEnabled
    }

    init(selectedModel: String,
         systemPrompt: String,
         tone: ToneStyle,
         disableLogging: Bool,
         clipboardWatcherEnabled: Bool,
         privacyStatus: PrivacyStatus,
         quickActions: [QuickAction],
         indexedFolders: [String],
         focusModeEnabled: Bool,
         focusPriorityApps: [String],
         focusAllowUrgent: Bool,
         quietHoursStartHour: Int,
         quietHoursEndHour: Int,
         privacyGuardianEnabled: Bool,
         privacyClipboardMonitorEnabled: Bool,
         privacySensitiveDetectionEnabled: Bool,
         privacyNetworkMonitorEnabled: Bool) {
        self.selectedModel = selectedModel
        self.systemPrompt = systemPrompt
        self.tone = tone
        self.disableLogging = disableLogging
        self.clipboardWatcherEnabled = clipboardWatcherEnabled
        self.privacyStatus = privacyStatus
        self.quickActions = quickActions
        self.indexedFolders = indexedFolders
        self.focusModeEnabled = focusModeEnabled
        self.focusPriorityApps = focusPriorityApps
        self.focusAllowUrgent = focusAllowUrgent
        self.quietHoursStartHour = quietHoursStartHour
        self.quietHoursEndHour = quietHoursEndHour
        self.privacyGuardianEnabled = privacyGuardianEnabled
        self.privacyClipboardMonitorEnabled = privacyClipboardMonitorEnabled
        self.privacySensitiveDetectionEnabled = privacySensitiveDetectionEnabled
        self.privacyNetworkMonitorEnabled = privacyNetworkMonitorEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? defaults.selectedModel
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? defaults.systemPrompt
        tone = try container.decodeIfPresent(ToneStyle.self, forKey: .tone) ?? defaults.tone
        disableLogging = try container.decodeIfPresent(Bool.self, forKey: .disableLogging) ?? defaults.disableLogging
        clipboardWatcherEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardWatcherEnabled) ?? defaults.clipboardWatcherEnabled
        privacyStatus = try container.decodeIfPresent(PrivacyStatus.self, forKey: .privacyStatus) ?? defaults.privacyStatus
        quickActions = try container.decodeIfPresent([QuickAction].self, forKey: .quickActions) ?? defaults.quickActions
        indexedFolders = try container.decodeIfPresent([String].self, forKey: .indexedFolders) ?? defaults.indexedFolders
        focusModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .focusModeEnabled) ?? defaults.focusModeEnabled
        focusPriorityApps = try container.decodeIfPresent([String].self, forKey: .focusPriorityApps) ?? defaults.focusPriorityApps
        focusAllowUrgent = try container.decodeIfPresent(Bool.self, forKey: .focusAllowUrgent) ?? defaults.focusAllowUrgent
        quietHoursStartHour = try container.decodeIfPresent(Int.self, forKey: .quietHoursStartHour) ?? defaults.quietHoursStartHour
        quietHoursEndHour = try container.decodeIfPresent(Int.self, forKey: .quietHoursEndHour) ?? defaults.quietHoursEndHour
        privacyGuardianEnabled = try container.decodeIfPresent(Bool.self, forKey: .privacyGuardianEnabled) ?? defaults.privacyGuardianEnabled
        privacyClipboardMonitorEnabled = try container.decodeIfPresent(Bool.self, forKey: .privacyClipboardMonitorEnabled) ?? defaults.privacyClipboardMonitorEnabled
        privacySensitiveDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .privacySensitiveDetectionEnabled) ?? defaults.privacySensitiveDetectionEnabled
        privacyNetworkMonitorEnabled = try container.decodeIfPresent(Bool.self, forKey: .privacyNetworkMonitorEnabled) ?? defaults.privacyNetworkMonitorEnabled
    }
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
        case whyDidThisHappen
        case searchMyFiles
        case toggleFocusMode
        case showNotificationDigest
        case addCurrentAppToPriority
        case privacyReport
        case thinkWithMe
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
        QuickAction(title: "Run macro", kind: .workflowMacro, icon: "gear"),
        QuickAction(title: "Why did this happen?", kind: .whyDidThisHappen, icon: "questionmark.circle"),
        QuickAction(title: "Search my files", kind: .searchMyFiles, icon: "folder"),
        QuickAction(title: "Toggle focus mode", kind: .toggleFocusMode, icon: "moon.zzz"),
        QuickAction(title: "Show digest", kind: .showNotificationDigest, icon: "text.bubble"),
        QuickAction(title: "Add current app", kind: .addCurrentAppToPriority, icon: "plus.app"),
        QuickAction(title: "Privacy report", kind: .privacyReport, icon: "lock.shield"),
        QuickAction(title: "Think with me", kind: .thinkWithMe, icon: "brain")
    ]
}

struct ToolInvocation: Codable, Equatable {
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

struct ToolResult: Codable, Equatable {
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
    var extractedText: String
    var lastModified: Date?
    var lastIndexed: Date

    init(id: UUID = UUID(), title: String, path: String, embedding: [Double], extractedText: String = "", lastModified: Date? = nil, lastIndexed: Date = .init()) {
        self.id = id
        self.title = title
        self.path = path
        self.embedding = embedding
        self.extractedText = extractedText
        self.lastModified = lastModified
        self.lastIndexed = lastIndexed
    }
}

struct FileSearchResult: Identifiable {
    let id: UUID
    let document: IndexedDocument
    let snippet: String
    let score: Double

    init(id: UUID = UUID(), document: IndexedDocument, snippet: String, score: Double) {
        self.id = id
        self.document = document
        self.snippet = snippet
        self.score = score
    }
}

struct FeatureEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let feature: String
    let type: String
    let summary: String
    let metadata: [String: String]
    let createdAt: Date

    init(id: UUID = UUID(), feature: String, type: String, summary: String, metadata: [String: String] = [:], createdAt: Date = .init()) {
        self.id = id
        self.feature = feature
        self.type = type
        self.summary = summary
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

struct ModuleHealthStatus: Identifiable, Equatable {
    let id = UUID()
    let module: String
    let enabled: Bool
    let permissionsOK: Bool
    let lastRun: Date?
}

enum WhySymptom: String, CaseIterable, Identifiable {
    case notificationOverload = "Notification overload"
    case appLag = "App lag"
    case highCPU = "High CPU"
    case draftFailed = "Draft failed"
    case other = "Other"

    var id: String { rawValue }
}

struct ThinkingEntry: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case assistant
        case user
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = .init()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct ThinkingSessionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var problem: String
    var constraints: String
    var options: [String]
    var entries: [ThinkingEntry]
    var summary: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, problem: String, constraints: String, options: [String], entries: [ThinkingEntry], summary: String, createdAt: Date = .init(), updatedAt: Date = .init()) {
        self.id = id
        self.title = title
        self.problem = problem
        self.constraints = constraints
        self.options = options
        self.entries = entries
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
