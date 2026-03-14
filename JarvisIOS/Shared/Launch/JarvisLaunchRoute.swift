import Foundation

public enum JarvisLaunchAction: String, Codable, CaseIterable {
    case home
    case ask
    case quickCapture
    case summarize
    case search
    case continueConversation
}

public struct JarvisLaunchRoute: Codable, Equatable {
    public var action: JarvisLaunchAction
    public var payload: String?
    public var source: String
    public var createdAt: Date

    public init(action: JarvisLaunchAction, payload: String? = nil, source: String = "app", createdAt: Date = Date()) {
        self.action = action
        self.payload = payload?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.createdAt = createdAt
    }

    public func url(scheme: String = "jarvis") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = action.rawValue
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "source", value: source)]
        if let payload, !payload.isEmpty {
            let payloadKey = action == .search ? "query" : "text"
            queryItems.append(URLQueryItem(name: payloadKey, value: payload))
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
        let payload = queryMap["text"] ?? queryMap["query"]
        let source = queryMap["source"] ?? "url"

        return JarvisLaunchRoute(action: action, payload: payload, source: source)
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
