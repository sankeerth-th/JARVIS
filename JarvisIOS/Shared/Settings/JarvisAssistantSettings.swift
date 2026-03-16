import Foundation

public enum JarvisStartupRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case home
    case assistant
    case voice
    case visual
    case knowledge

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .home:
            return "Home"
        case .assistant:
            return "Assistant"
        case .voice:
            return "Voice Assistant"
        case .visual:
            return "Visual Intelligence"
        case .knowledge:
            return "Knowledge"
        }
    }

    public var launchAction: JarvisLaunchAction {
        switch self {
        case .home:
            return .home
        case .assistant:
            return .assistant
        case .voice:
            return .voice
        case .visual:
            return .visualIntelligence
        case .knowledge:
            return .knowledge
        }
    }
}

public enum JarvisRuntimePerformanceProfile: String, Codable, CaseIterable, Identifiable, Sendable {
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

public enum JarvisContextWindowPreset: String, Codable, CaseIterable, Identifiable, Sendable {
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

public enum JarvisAssistantResponseStyle: String, Codable, CaseIterable, Identifiable, Sendable {
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

public enum JarvisAssistantQualityMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case balanced
    case highQuality

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact:
            return "Compact"
        case .balanced:
            return "Balanced"
        case .highQuality:
            return "High Quality"
        }
    }
}

public enum JarvisAssistantPromptMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case safe
    case advanced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safe:
            return "Safe"
        case .advanced:
            return "Advanced"
        }
    }
}

public struct JarvisRuntimeConfiguration: Equatable, Codable, Sendable {
    public var performanceProfile: JarvisRuntimePerformanceProfile
    public var contextWindow: JarvisContextWindowPreset
    public var responseStyle: JarvisAssistantResponseStyle
    public var temperature: Double
    public var batterySaverMode: Bool
    public var memorySafetyGuardsEnabled: Bool
    public var thermalProtectionEnabled: Bool
    public var adaptiveDeviceTieringEnabled: Bool
    public var experimentalSpeculativeDecodingEnabled: Bool

    public init(
        performanceProfile: JarvisRuntimePerformanceProfile = .balanced,
        contextWindow: JarvisContextWindowPreset = .automatic,
        responseStyle: JarvisAssistantResponseStyle = .balanced,
        temperature: Double = 0.55,
        batterySaverMode: Bool = false,
        memorySafetyGuardsEnabled: Bool = true,
        thermalProtectionEnabled: Bool = true,
        adaptiveDeviceTieringEnabled: Bool = true,
        experimentalSpeculativeDecodingEnabled: Bool = false
    ) {
        self.performanceProfile = performanceProfile
        self.contextWindow = contextWindow
        self.responseStyle = responseStyle
        self.temperature = temperature
        self.batterySaverMode = batterySaverMode
        self.memorySafetyGuardsEnabled = memorySafetyGuardsEnabled
        self.thermalProtectionEnabled = thermalProtectionEnabled
        self.adaptiveDeviceTieringEnabled = adaptiveDeviceTieringEnabled
        self.experimentalSpeculativeDecodingEnabled = experimentalSpeculativeDecodingEnabled
    }
}

public struct JarvisAssistantSettings: Codable, Equatable {
    public var startupRoute: JarvisStartupRoute
    public var preferredModelProfile: JarvisSupportedModelProfileID
    public var autoWarmOnLaunch: Bool
    public var autoWarmOnFirstSend: Bool
    public var assistantQualityMode: JarvisAssistantQualityMode
    public var promptMode: JarvisAssistantPromptMode
    public var memoryEnabled: Bool
    public var performanceProfile: JarvisRuntimePerformanceProfile
    public var contextWindow: JarvisContextWindowPreset
    public var responseStyle: JarvisAssistantResponseStyle
    public var creativity: Double
    public var unloadModelOnBackground: Bool
    public var batterySaverMode: Bool
    public var autoScrollConversation: Bool
    public var showRuntimeDiagnostics: Bool
    public var hapticsEnabled: Bool
    public var autoStartListeningForVoiceEntry: Bool
    public var autoSendVoiceAfterPause: Bool
    public var speechLocaleIdentifier: String?

    public init(
        startupRoute: JarvisStartupRoute = .home,
        preferredModelProfile: JarvisSupportedModelProfileID = .gemma3_4b_it_q4_0,
        autoWarmOnLaunch: Bool = false,
        autoWarmOnFirstSend: Bool = true,
        assistantQualityMode: JarvisAssistantQualityMode = .balanced,
        promptMode: JarvisAssistantPromptMode = .safe,
        memoryEnabled: Bool = true,
        performanceProfile: JarvisRuntimePerformanceProfile = .balanced,
        contextWindow: JarvisContextWindowPreset = .automatic,
        responseStyle: JarvisAssistantResponseStyle = .balanced,
        creativity: Double = 0.55,
        unloadModelOnBackground: Bool = false,
        batterySaverMode: Bool = false,
        autoScrollConversation: Bool = true,
        showRuntimeDiagnostics: Bool = false,
        hapticsEnabled: Bool = true,
        autoStartListeningForVoiceEntry: Bool = true,
        autoSendVoiceAfterPause: Bool = true,
        speechLocaleIdentifier: String? = nil
    ) {
        self.startupRoute = startupRoute
        self.preferredModelProfile = preferredModelProfile
        self.autoWarmOnLaunch = autoWarmOnLaunch
        self.autoWarmOnFirstSend = autoWarmOnFirstSend
        self.assistantQualityMode = assistantQualityMode
        self.promptMode = promptMode
        self.memoryEnabled = memoryEnabled
        self.performanceProfile = performanceProfile
        self.contextWindow = contextWindow
        self.responseStyle = responseStyle
        self.creativity = creativity
        self.unloadModelOnBackground = unloadModelOnBackground
        self.batterySaverMode = batterySaverMode
        self.autoScrollConversation = autoScrollConversation
        self.showRuntimeDiagnostics = showRuntimeDiagnostics
        self.hapticsEnabled = hapticsEnabled
        self.autoStartListeningForVoiceEntry = autoStartListeningForVoiceEntry
        self.autoSendVoiceAfterPause = autoSendVoiceAfterPause
        self.speechLocaleIdentifier = speechLocaleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case startupRoute
        case preferredModelProfile
        case autoWarmOnLaunch
        case autoWarmOnFirstSend
        case assistantQualityMode
        case promptMode
        case memoryEnabled
        case performanceProfile
        case contextWindow
        case responseStyle
        case creativity
        case unloadModelOnBackground
        case batterySaverMode
        case autoScrollConversation
        case showRuntimeDiagnostics
        case hapticsEnabled
        case autoStartListeningForVoiceEntry
        case autoSendVoiceAfterPause
        case speechLocaleIdentifier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startupRoute = try container.decodeIfPresent(JarvisStartupRoute.self, forKey: .startupRoute) ?? .home
        preferredModelProfile = try container.decodeIfPresent(JarvisSupportedModelProfileID.self, forKey: .preferredModelProfile) ?? .gemma3_4b_it_q4_0
        autoWarmOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoWarmOnLaunch) ?? false
        autoWarmOnFirstSend = try container.decodeIfPresent(Bool.self, forKey: .autoWarmOnFirstSend) ?? true
        assistantQualityMode = try container.decodeIfPresent(JarvisAssistantQualityMode.self, forKey: .assistantQualityMode) ?? .balanced
        promptMode = try container.decodeIfPresent(JarvisAssistantPromptMode.self, forKey: .promptMode) ?? .safe
        memoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? true
        performanceProfile = try container.decodeIfPresent(JarvisRuntimePerformanceProfile.self, forKey: .performanceProfile) ?? .balanced
        contextWindow = try container.decodeIfPresent(JarvisContextWindowPreset.self, forKey: .contextWindow) ?? .automatic
        responseStyle = try container.decodeIfPresent(JarvisAssistantResponseStyle.self, forKey: .responseStyle) ?? .balanced
        creativity = try container.decodeIfPresent(Double.self, forKey: .creativity) ?? 0.55
        unloadModelOnBackground = try container.decodeIfPresent(Bool.self, forKey: .unloadModelOnBackground) ?? false
        batterySaverMode = try container.decodeIfPresent(Bool.self, forKey: .batterySaverMode) ?? false
        autoScrollConversation = try container.decodeIfPresent(Bool.self, forKey: .autoScrollConversation) ?? true
        showRuntimeDiagnostics = try container.decodeIfPresent(Bool.self, forKey: .showRuntimeDiagnostics) ?? false
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        autoStartListeningForVoiceEntry = try container.decodeIfPresent(Bool.self, forKey: .autoStartListeningForVoiceEntry) ?? true
        autoSendVoiceAfterPause = try container.decodeIfPresent(Bool.self, forKey: .autoSendVoiceAfterPause) ?? true
        speechLocaleIdentifier = try container.decodeIfPresent(String.self, forKey: .speechLocaleIdentifier)?.trimmingCharacters(in: .whitespacesAndNewlines)
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
