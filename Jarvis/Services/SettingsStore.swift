import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings
    private let userDefaultsKey = "com.jarvis.settings"
    private let defaults: UserDefaults
    private let securityEnvelope: JarvisSecurityEnvelope
    private let secureStore: JarvisSecureStore
    private let porcupineAccessKeyAccount = "jarvis.runtime.porcupine.access-key"
    private let porcupineKeywordPathKey = "com.jarvis.settings.porcupineKeywordPath"

    init(defaults: UserDefaults = .standard, securityEnvelope: JarvisSecurityEnvelope = .shared, secureStore: JarvisSecureStore = .shared) {
        self.defaults = defaults
        self.securityEnvelope = securityEnvelope
        self.secureStore = secureStore
        if let decoded = Self.loadSettings(
            from: defaults,
            key: userDefaultsKey,
            securityEnvelope: securityEnvelope
        ) {
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

    func setWakeWordEnabled(_ enabled: Bool) {
        update { $0.wakeWordEnabled = enabled }
    }

    func setVoiceAutoResponseEnabled(_ enabled: Bool) {
        update { $0.voiceAutoResponseEnabled = enabled }
    }

    func setStreamingSpeechEnabled(_ enabled: Bool) {
        update { $0.streamingSpeechEnabled = enabled }
    }

    func setBroadFileAccessEnabled(_ enabled: Bool) {
        update { $0.broadFileAccessEnabled = enabled }
    }

    func setTerminalExecutionEnabled(_ enabled: Bool) {
        update { $0.terminalExecutionEnabled = enabled }
    }

    func setApprovalStrictnessMode(_ mode: JarvisApprovalStrictnessMode) {
        update { $0.approvalStrictnessMode = mode }
    }

    func setTrustedWriteRoots(_ roots: [String]) {
        update { $0.trustedWriteRoots = roots }
    }

    func setExcludedReadRoots(_ roots: [String]) {
        update { $0.excludedReadRoots = roots }
    }

    func setRuntimeDiagnosticsEnabled(_ enabled: Bool) {
        update { $0.runtimeDiagnosticsEnabled = enabled }
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

    func porcupineAccessKey() -> String? {
        guard let data = secureStore.data(for: porcupineAccessKeyAccount) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setPorcupineAccessKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        secureStore.set(Data(trimmed.utf8), for: porcupineAccessKeyAccount)
    }

    func removePorcupineAccessKey() {
        secureStore.remove(account: porcupineAccessKeyAccount)
    }

    func importPorcupineAccessKeyFromEnvironmentIfNeeded(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard porcupineAccessKey() == nil else { return }
        guard let value = environment["PORCUPINE_ACCESS_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }
        secureStore.set(Data(value.utf8), for: porcupineAccessKeyAccount)
    }

    func porcupineKeywordPath() -> String? {
        defaults.string(forKey: porcupineKeywordPathKey)
    }

    func setPorcupineKeywordPath(_ path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: porcupineKeywordPathKey)
        } else {
            defaults.removeObject(forKey: porcupineKeywordPathKey)
        }
    }

    private func persist(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings),
              let sealed = try? securityEnvelope.seal(data, purpose: userDefaultsKey) else { return }
        defaults.set(sealed, forKey: userDefaultsKey)
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

    private static func loadSettings(
        from defaults: UserDefaults,
        key: String,
        securityEnvelope: JarvisSecurityEnvelope
    ) -> AppSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if let opened = try? securityEnvelope.open(data, purpose: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: opened) {
            return decoded
        }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
