import AppIntents
import Foundation

struct OpenJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Jarvis"
    static var description = IntentDescription("Open Jarvis Home immediately.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisLaunchRouteStore.shared.save(JarvisLaunchRoute(action: .home, source: "intent.open"))
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
        JarvisLaunchRouteStore.shared.save(
            JarvisLaunchRoute(action: .ask, payload: prompt.isEmpty ? nil : prompt, source: "intent.ask")
        )
        return .result()
    }
}

struct QuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Capture"
    static var description = IntentDescription("Open Jarvis ready to capture text immediately.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisLaunchRouteStore.shared.save(JarvisLaunchRoute(action: .quickCapture, source: "intent.capture"))
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
        JarvisLaunchRouteStore.shared.save(JarvisLaunchRoute(action: .summarize, payload: text, source: "intent.summarize"))
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
        JarvisLaunchRouteStore.shared.save(JarvisLaunchRoute(action: .search, payload: query, source: "intent.search"))
        return .result()
    }
}

struct ContinueConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Last Conversation"
    static var description = IntentDescription("Open Jarvis and continue your latest conversation.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        JarvisLaunchRouteStore.shared.save(JarvisLaunchRoute(action: .continueConversation, source: "intent.continue"))
        return .result()
    }
}

struct JarvisPhoneShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenJarvisIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Launch \(.applicationName)"
            ],
            shortTitle: "Open Jarvis",
            systemImageName: "bolt.fill"
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
            intent: SearchLocalKnowledgeIntent(),
            phrases: [
                "Search knowledge in \(.applicationName)",
                "Find in \(.applicationName)"
            ],
            shortTitle: "Search Knowledge",
            systemImageName: "magnifyingglass"
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
