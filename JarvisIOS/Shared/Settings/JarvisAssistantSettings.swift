import Foundation

public enum JarvisStartupRoute: String, Codable, CaseIterable, Identifiable {
    case home
    case assistant
    case knowledge

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .home:
            return "Home"
        case .assistant:
            return "Assistant"
        case .knowledge:
            return "Knowledge"
        }
    }

    public var launchAction: JarvisLaunchAction {
        switch self {
        case .home:
            return .home
        case .assistant:
            return .ask
        case .knowledge:
            return .search
        }
    }
}

public enum JarvisRuntimePerformanceProfile: String, Codable, CaseIterable, Identifiable {
    case efficient
    case balanced
    case quality

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .efficient:
            return "Efficient"
        case .balanced:
            return "Balanced"
        case .quality:
            return "Quality"
        }
    }
}

public enum JarvisContextWindowPreset: String, Codable, CaseIterable, Identifiable {
    case automatic
    case compact
    case standard
    case extended

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .compact:
            return "Compact"
        case .standard:
            return "Standard"
        case .extended:
            return "Extended"
        }
    }

    public var tokenEstimateLabel: String {
        switch self {
        case .automatic:
            return "Adaptive"
        case .compact:
            return "~1K"
        case .standard:
            return "~2K"
        case .extended:
            return "~4K"
        }
    }

    public var explicitContextSize: Int? {
        switch self {
        case .automatic:
            return nil
        case .compact:
            return 1024
        case .standard:
            return 2048
        case .extended:
            return 4096
        }
    }
}

public enum JarvisAssistantResponseStyle: String, Codable, CaseIterable, Identifiable {
    case concise
    case balanced
    case detailed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .concise:
            return "Concise"
        case .balanced:
            return "Balanced"
        case .detailed:
            return "Detailed"
        }
    }

    public var systemInstructionSuffix: String {
        switch self {
        case .concise:
            return "Keep replies compact unless the user asks for detail."
        case .balanced:
            return "Balance speed and completeness."
        case .detailed:
            return "Provide fuller explanations when they improve usefulness."
        }
    }
}

public struct JarvisRuntimeConfiguration: Equatable, Codable {
    public var performanceProfile: JarvisRuntimePerformanceProfile
    public var contextWindow: JarvisContextWindowPreset
    public var responseStyle: JarvisAssistantResponseStyle
    public var temperature: Double
    public var batterySaverMode: Bool

    public init(
        performanceProfile: JarvisRuntimePerformanceProfile = .balanced,
        contextWindow: JarvisContextWindowPreset = .automatic,
        responseStyle: JarvisAssistantResponseStyle = .balanced,
        temperature: Double = 0.7,
        batterySaverMode: Bool = false
    ) {
        self.performanceProfile = performanceProfile
        self.contextWindow = contextWindow
        self.responseStyle = responseStyle
        self.temperature = temperature
        self.batterySaverMode = batterySaverMode
    }
}

public struct JarvisAssistantSettings: Codable, Equatable {
    public var startupRoute: JarvisStartupRoute
    public var autoWarmOnLaunch: Bool
    public var performanceProfile: JarvisRuntimePerformanceProfile
    public var contextWindow: JarvisContextWindowPreset
    public var responseStyle: JarvisAssistantResponseStyle
    public var creativity: Double
    public var unloadModelOnBackground: Bool
    public var batterySaverMode: Bool
    public var autoScrollConversation: Bool
    public var showRuntimeDiagnostics: Bool
    public var hapticsEnabled: Bool

    public init(
        startupRoute: JarvisStartupRoute = .home,
        autoWarmOnLaunch: Bool = false,
        performanceProfile: JarvisRuntimePerformanceProfile = .balanced,
        contextWindow: JarvisContextWindowPreset = .automatic,
        responseStyle: JarvisAssistantResponseStyle = .balanced,
        creativity: Double = 0.7,
        unloadModelOnBackground: Bool = false,
        batterySaverMode: Bool = false,
        autoScrollConversation: Bool = true,
        showRuntimeDiagnostics: Bool = false,
        hapticsEnabled: Bool = true
    ) {
        self.startupRoute = startupRoute
        self.autoWarmOnLaunch = autoWarmOnLaunch
        self.performanceProfile = performanceProfile
        self.contextWindow = contextWindow
        self.responseStyle = responseStyle
        self.creativity = creativity
        self.unloadModelOnBackground = unloadModelOnBackground
        self.batterySaverMode = batterySaverMode
        self.autoScrollConversation = autoScrollConversation
        self.showRuntimeDiagnostics = showRuntimeDiagnostics
        self.hapticsEnabled = hapticsEnabled
    }

    public static let `default` = JarvisAssistantSettings()

    public var runtimeConfiguration: JarvisRuntimeConfiguration {
        JarvisRuntimeConfiguration(
            performanceProfile: performanceProfile,
            contextWindow: contextWindow,
            responseStyle: responseStyle,
            temperature: min(max(creativity, 0.0), 1.2),
            batterySaverMode: batterySaverMode
        )
    }
}

public final class JarvisAssistantSettingsStore {
    private let defaults: UserDefaults
    private let key = "jarvis.ios.assistant.settings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> JarvisAssistantSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(JarvisAssistantSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    public func save(_ settings: JarvisAssistantSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
