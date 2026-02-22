import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings
    private let userDefaultsKey = "com.jarvis.settings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        persist(copy)
    }

    func override(settings newSettings: AppSettings) {
        settings = newSettings
        persist(newSettings)
    }

    func clearQuickActions() {
        update { $0.quickActions = [] }
    }

    func setPrivacyStatus(_ status: PrivacyStatus) {
        update { $0.privacyStatus = status }
    }

    func setModel(_ model: String) {
        update { $0.selectedModel = model }
    }

    func setTone(_ tone: ToneStyle) {
        update { $0.tone = tone }
    }

    func setClipboardWatcher(enabled: Bool) {
        update { $0.clipboardWatcherEnabled = enabled }
    }

    func setLogging(enabled: Bool) {
        update { $0.disableLogging = !enabled }
    }

    func setSystemPrompt(_ prompt: String) {
        update { $0.systemPrompt = prompt }
    }

    func systemPrompt() -> String { settings.systemPrompt }

    func tone() -> ToneStyle { settings.tone }

    func selectedModel() -> String { settings.selectedModel }

    func disableLogging() -> Bool { settings.disableLogging }

    func clipboardWatcherEnabled() -> Bool { settings.clipboardWatcherEnabled }

    func quickActions() -> [QuickAction] { settings.quickActions }

    var current: AppSettings { settings }

    private func persist(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: userDefaultsKey)
    }
}
