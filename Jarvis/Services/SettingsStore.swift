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
            settings = Self.normalizedSettings(decoded)
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

    func setIndexedFolders(_ folders: [String]) {
        update { $0.indexedFolders = folders }
    }

    func addIndexedFolder(_ path: String) {
        update { settings in
            guard !settings.indexedFolders.contains(path) else { return }
            settings.indexedFolders.append(path)
        }
    }

    func removeIndexedFolder(_ path: String) {
        update { settings in
            settings.indexedFolders.removeAll { $0 == path }
        }
    }

    func setFocusModeEnabled(_ enabled: Bool) {
        update { $0.focusModeEnabled = enabled }
    }

    func setFocusPriorityApps(_ apps: [String]) {
        update { $0.focusPriorityApps = apps }
    }

    func setFocusAllowUrgent(_ allow: Bool) {
        update { $0.focusAllowUrgent = allow }
    }

    func setQuietHours(startHour: Int, endHour: Int) {
        update {
            $0.quietHoursStartHour = max(0, min(startHour, 23))
            $0.quietHoursEndHour = max(0, min(endHour, 23))
        }
    }

    func setPrivacyGuardianEnabled(_ enabled: Bool) {
        update { $0.privacyGuardianEnabled = enabled }
    }

    func setPrivacyClipboardMonitorEnabled(_ enabled: Bool) {
        update { $0.privacyClipboardMonitorEnabled = enabled }
    }

    func setPrivacySensitiveDetectionEnabled(_ enabled: Bool) {
        update { $0.privacySensitiveDetectionEnabled = enabled }
    }

    func setPrivacyNetworkMonitorEnabled(_ enabled: Bool) {
        update { $0.privacyNetworkMonitorEnabled = enabled }
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

    func indexedFolders() -> [String] { settings.indexedFolders }

    var current: AppSettings { settings }

    private func persist(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: userDefaultsKey)
    }

    private static func normalizedSettings(_ settings: AppSettings) -> AppSettings {
        var copy = settings
        let existingKinds = Set(copy.quickActions.map { $0.kind })
        let missing = QuickAction.defaults.filter { !existingKinds.contains($0.kind) }
        if !missing.isEmpty {
            copy.quickActions.append(contentsOf: missing)
        }
        return copy
    }
}
