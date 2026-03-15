import AppIntents
import Foundation

private enum JarvisShortcutRouteBuilder {
    static func save(_ route: JarvisLaunchRoute) {
        JarvisLaunchRouteStore.shared.save(route)
    }
}

struct OpenJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Jarvis"
    static var description = IntentDescription("Open Jarvis using your configured startup destination.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let startupRoute = JarvisAssistantSettingsStore().load().startupRoute
        JarvisShortcutRouteBuilder.save(
            JarvisLaunchRoute(action: startupRoute.launchAction, source: JarvisAssistantEntrySource.shortcut.rawValue)
        )
        return .result()
    }
}

struct OpenAssistantIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Assistant"
    static var description = IntentDescription("Open Jarvis directly in the assistant.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisShortcutRouteBuilder.save(
            .assistant(.assistant, source: .shortcut, shouldFocusComposer: true)
        )
        return .result()
    }
}

struct AskJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Jarvis"
    static var description = IntentDescription("Open Jarvis directly in the assistant composer with optional input text.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Prompt", default: "")
    var prompt: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Jarvis with \(\.$prompt)")
    }

    func perform() async throws -> some IntentResult {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        JarvisShortcutRouteBuilder.save(
            JarvisLaunchRoute(
                action: .ask,
                payload: trimmedPrompt.isEmpty ? nil : trimmedPrompt,
                source: JarvisAssistantEntrySource.shortcut.rawValue,
                assistantTask: .chat,
                shouldFocusComposer: trimmedPrompt.isEmpty,
                shouldAutoSubmit: !trimmedPrompt.isEmpty
            )
        )
        return .result()
    }
}

struct QuickAskIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Ask"
    static var description = IntentDescription("Open Jarvis in a fast ask flow, optionally sending the provided text immediately.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question", default: "")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Quick ask Jarvis with \(\.$question)")
    }

    func perform() async throws -> some IntentResult {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        JarvisShortcutRouteBuilder.save(
            JarvisLaunchRoute(
                action: .ask,
                payload: trimmedQuestion.isEmpty ? nil : trimmedQuestion,
                source: JarvisAssistantEntrySource.shortcut.rawValue,
                assistantTask: .chat,
                shouldFocusComposer: trimmedQuestion.isEmpty,
                shouldAutoSubmit: !trimmedQuestion.isEmpty
            )
        )
        return .result()
    }
}

struct VoiceJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Voice Jarvis"
    static var description = IntentDescription("Open Jarvis directly in listening mode.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisShortcutRouteBuilder.save(
            .assistant(.voice, task: .chat, source: .shortcut, shouldStartListening: true)
        )
        return .result()
    }
}

struct VisualJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Visual Jarvis"
    static var description = IntentDescription("Open Jarvis visual assistant preview.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisShortcutRouteBuilder.save(
            .assistant(.visual, task: .visualDescribe, source: .shortcut)
        )
        return .result()
    }
}

struct DraftReplyIntent: AppIntent {
    static var title: LocalizedStringResource = "Draft Reply"
    static var description = IntentDescription("Open Jarvis and prepare a reply draft.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Reply Target", default: "")
    var seedText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Draft a reply for \(\.$seedText)")
    }

    func perform() async throws -> some IntentResult {
        let trimmedSeedText = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
        JarvisShortcutRouteBuilder.save(
            .assistant(
                .draftReply,
                payload: trimmedSeedText.isEmpty ? nil : trimmedSeedText,
                task: .reply,
                source: .shortcut,
                shouldFocusComposer: trimmedSeedText.isEmpty,
                shouldAutoSubmit: !trimmedSeedText.isEmpty
            )
        )
        return .result()
    }
}

struct QuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Capture"
    static var description = IntentDescription("Open Jarvis ready to capture text immediately.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisShortcutRouteBuilder.save(
            JarvisLaunchRoute(
                action: .quickCapture,
                source: JarvisAssistantEntrySource.shortcut.rawValue,
                assistantTask: .quickCapture,
                shouldFocusComposer: true
            )
        )
        return .result()
    }
}

struct SummarizeTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize Text"
    static var description = IntentDescription("Open Jarvis and prefill a summarize request.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$text)")
    }

    func perform() async throws -> some IntentResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        JarvisShortcutRouteBuilder.save(
            JarvisLaunchRoute(
                action: .summarize,
                payload: trimmedText.isEmpty ? nil : trimmedText,
                source: JarvisAssistantEntrySource.shortcut.rawValue,
                assistantTask: .summarize,
                shouldFocusComposer: trimmedText.isEmpty,
                shouldAutoSubmit: !trimmedText.isEmpty
            )
        )
        return .result()
    }
}

struct OpenKnowledgeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Knowledge"
    static var description = IntentDescription("Open Jarvis local knowledge search.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisShortcutRouteBuilder.save(
            .assistant(.knowledge, source: .shortcut)
        )
        return .result()
    }
}

struct SearchLocalKnowledgeIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Local Knowledge"
    static var description = IntentDescription("Open Jarvis local knowledge search with a query.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Query")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Jarvis knowledge for \(\.$query)")
    }

    func perform() async throws -> some IntentResult {
        JarvisShortcutRouteBuilder.save(
            JarvisLaunchRoute(
                action: .knowledge,
                query: query,
                source: JarvisAssistantEntrySource.shortcut.rawValue,
                assistantTask: .knowledgeAnswer
            )
        )
        return .result()
    }
}

struct OpenModelLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Model Library"
    static var description = IntentDescription("Open Jarvis model library directly.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisShortcutRouteBuilder.save(
            JarvisLaunchRoute(action: .modelLibrary, source: JarvisAssistantEntrySource.shortcut.rawValue)
        )
        return .result()
    }
}

struct ContinueConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Last Conversation"
    static var description = IntentDescription("Open Jarvis and continue your latest conversation.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisShortcutRouteBuilder.save(
            .assistant(.continueConversation, task: .chat, source: .shortcut, shouldFocusComposer: true)
        )
        return .result()
    }
}

struct JarvisPhoneShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAssistantIntent(),
            phrases: [
                "Open assistant in \(.applicationName)",
                "Open ask in \(.applicationName)"
            ],
            shortTitle: "Open Assistant",
            systemImageName: "bubble.left.and.text.bubble.right.fill"
        )
        AppShortcut(
            intent: AskJarvisIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask Jarvis in \(.applicationName)"
            ],
            shortTitle: "Ask Jarvis",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: QuickAskIntent(),
            phrases: [
                "Quick ask in \(.applicationName)",
                "Quick question in \(.applicationName)"
            ],
            shortTitle: "Quick Ask",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: VoiceJarvisIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Voice mode in \(.applicationName)"
            ],
            shortTitle: "Voice Jarvis",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: VisualJarvisIntent(),
            phrases: [
                "Visual assistant in \(.applicationName)",
                "Open visual mode in \(.applicationName)"
            ],
            shortTitle: "Visual Preview",
            systemImageName: "viewfinder"
        )
        AppShortcut(
            intent: DraftReplyIntent(),
            phrases: [
                "Draft reply in \(.applicationName)",
                "Reply with \(.applicationName)"
            ],
            shortTitle: "Draft Reply",
            systemImageName: "arrowshape.turn.up.left.fill"
        )
        AppShortcut(
            intent: QuickCaptureIntent(),
            phrases: [
                "Quick capture in \(.applicationName)",
                "Capture with \(.applicationName)"
            ],
            shortTitle: "Quick Capture",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SummarizeTextIntent(),
            phrases: [
                "Summarize with \(.applicationName)",
                "Summarize text in \(.applicationName)"
            ],
            shortTitle: "Summarize",
            systemImageName: "text.quote"
        )
        AppShortcut(
            intent: OpenKnowledgeIntent(),
            phrases: [
                "Open knowledge in \(.applicationName)",
                "Open search in \(.applicationName)"
            ],
            shortTitle: "Open Knowledge",
            systemImageName: "books.vertical"
        )
        AppShortcut(
            intent: ContinueConversationIntent(),
            phrases: [
                "Continue in \(.applicationName)",
                "Resume Jarvis in \(.applicationName)"
            ],
            shortTitle: "Continue",
            systemImageName: "arrow.uturn.forward.circle"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .teal
}
