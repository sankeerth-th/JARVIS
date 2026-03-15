import Foundation

public enum JarvisAssistantEntryRoute: String, Codable, CaseIterable {
    case assistant
    case chat
    case voice
    case visual
    case knowledge
    case draftReply
    case continueConversation
    case systemAssistant
}

public enum JarvisAssistantEntrySource: String, Codable, CaseIterable {
    case normalLaunch
    case shortcut
    case deepLink
    case inApp
    case settings
    case legacy
}

public enum JarvisLaunchAction: String, Codable, CaseIterable {
    case home
    case assistant
    case chat
    case ask
    case voice
    case visualIntelligence
    case quickCapture
    case summarize
    case search
    case knowledge
    case draftReply
    case continueConversation
    case settings
    case modelLibrary = "models"
    case systemAssistant
}

public struct JarvisLaunchRoute: Codable, Equatable {
    public var action: JarvisLaunchAction
    public var payload: String?
    public var query: String?
    public var source: String
    public var createdAt: Date
    public var assistantTask: JarvisAssistantTask?
    public var shouldFocusComposer: Bool?
    public var shouldStartListening: Bool?
    public var shouldAutoSubmit: Bool?

    public init(
        action: JarvisLaunchAction,
        payload: String? = nil,
        query: String? = nil,
        source: String = JarvisAssistantEntrySource.inApp.rawValue,
        createdAt: Date = Date(),
        assistantTask: JarvisAssistantTask? = nil,
        shouldFocusComposer: Bool? = nil,
        shouldStartListening: Bool? = nil,
        shouldAutoSubmit: Bool? = nil
    ) {
        self.action = action
        self.payload = payload?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.createdAt = createdAt
        self.assistantTask = assistantTask
        self.shouldFocusComposer = shouldFocusComposer
        self.shouldStartListening = shouldStartListening
        self.shouldAutoSubmit = shouldAutoSubmit
    }

    public var entryRoute: JarvisAssistantEntryRoute? {
        switch action {
        case .assistant:
            return .assistant
        case .chat, .ask, .quickCapture, .summarize:
            return .chat
        case .voice:
            return .voice
        case .visualIntelligence:
            return .visual
        case .search, .knowledge:
            return .knowledge
        case .draftReply:
            return .draftReply
        case .continueConversation:
            return .continueConversation
        case .systemAssistant:
            return .systemAssistant
        case .home, .settings, .modelLibrary:
            return nil
        }
    }

    public var sourceKind: JarvisAssistantEntrySource {
        JarvisAssistantEntrySource(rawValue: source) ?? .inApp
    }

    public func url(scheme: String = "jarvis") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = action.rawValue

        var queryItems: [URLQueryItem] = [URLQueryItem(name: "source", value: source)]
        if let payload, !payload.isEmpty {
            queryItems.append(URLQueryItem(name: "text", value: payload))
        }
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        if let assistantTask {
            queryItems.append(URLQueryItem(name: "task", value: assistantTask.rawValue))
        }
        if let shouldFocusComposer {
            queryItems.append(URLQueryItem(name: "focus", value: shouldFocusComposer ? "1" : "0"))
        }
        if let shouldStartListening {
            queryItems.append(URLQueryItem(name: "listen", value: shouldStartListening ? "1" : "0"))
        }
        if let shouldAutoSubmit {
            queryItems.append(URLQueryItem(name: "submit", value: shouldAutoSubmit ? "1" : "0"))
        }
        components.queryItems = queryItems
        return components.url
    }

    public static func parse(url: URL) -> JarvisLaunchRoute? {
        guard let scheme = url.scheme?.lowercased(), scheme == "jarvis" else { return nil }

        let host = url.host?.lowercased() ?? ""
        let fallbackPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let rawAction = host.isEmpty ? fallbackPath : host
        guard let action = JarvisLaunchAction(rawValue: rawAction) else { return nil }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryMap = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name.lowercased(), $0.value ?? "") })
        let payload = queryMap["text"]
        let query = queryMap["query"]
        let source = queryMap["source"] ?? JarvisAssistantEntrySource.deepLink.rawValue
        let assistantTask = queryMap["task"].flatMap(JarvisAssistantTask.init(rawValue:))
        let shouldFocusComposer = queryMap["focus"].flatMap(Self.bool(from:))
        let shouldStartListening = queryMap["listen"].flatMap(Self.bool(from:))
        let shouldAutoSubmit = queryMap["submit"].flatMap(Self.bool(from:))

        return JarvisLaunchRoute(
            action: action,
            payload: payload,
            query: query,
            source: source,
            assistantTask: assistantTask,
            shouldFocusComposer: shouldFocusComposer,
            shouldStartListening: shouldStartListening,
            shouldAutoSubmit: shouldAutoSubmit
        )
    }

    public static func assistant(
        _ route: JarvisAssistantEntryRoute,
        payload: String? = nil,
        query: String? = nil,
        task: JarvisAssistantTask? = nil,
        source: JarvisAssistantEntrySource,
        shouldFocusComposer: Bool? = nil,
        shouldStartListening: Bool? = nil,
        shouldAutoSubmit: Bool? = nil
    ) -> JarvisLaunchRoute {
        let action: JarvisLaunchAction
        switch route {
        case .assistant:
            action = .assistant
        case .chat:
            action = .chat
        case .voice:
            action = .voice
        case .visual:
            action = .visualIntelligence
        case .knowledge:
            action = .knowledge
        case .draftReply:
            action = .draftReply
        case .continueConversation:
            action = .continueConversation
        case .systemAssistant:
            action = .systemAssistant
        }

        return JarvisLaunchRoute(
            action: action,
            payload: payload,
            query: query,
            source: source.rawValue,
            assistantTask: task,
            shouldFocusComposer: shouldFocusComposer,
            shouldStartListening: shouldStartListening,
            shouldAutoSubmit: shouldAutoSubmit
        )
    }

    private static func bool(from raw: String) -> Bool? {
        switch raw.lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
}

public final class JarvisLaunchRouteStore {
    public static let shared = JarvisLaunchRouteStore()

    private let defaults: UserDefaults
    private let key = "jarvis.phone.pendingLaunchRoute"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ route: JarvisLaunchRoute) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        defaults.set(data, forKey: key)
    }

    public func consumePendingRoute() -> JarvisLaunchRoute? {
        guard let data = defaults.data(forKey: key),
              let route = try? JSONDecoder().decode(JarvisLaunchRoute.self, from: data) else {
            return nil
        }
        defaults.removeObject(forKey: key)
        return route
    }
}
