import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var indexingStatus: String? = nil
    @Published var availableModels: [String] = []
    @Published var macros: [Macro] = []

    private let settingsStore: SettingsStore
    private let permissions: PermissionsManager
    private let localIndexService: LocalIndexService
    private let macroService: MacroService
    private let conversationService: ConversationService
    private let ollama: OllamaClient
    private var cancellables: Set<AnyCancellable> = []
    private var didBind = false

    init(settingsStore: SettingsStore,
         permissions: PermissionsManager,
         localIndexService: LocalIndexService,
         macroService: MacroService,
         conversationService: ConversationService,
         ollama: OllamaClient) {
        self.settingsStore = settingsStore
        self.permissions = permissions
        self.localIndexService = localIndexService
        self.macroService = macroService
        self.conversationService = conversationService
        self.ollama = ollama
        self.settings = settingsStore.current
        macroService.$macros
            .receive(on: DispatchQueue.main)
            .sink { [weak self] macros in self?.macros = macros }
            .store(in: &cancellables)
        observeSettings()
    }

    func observeSettings() {
        guard !didBind else { return }
        didBind = true
        settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                guard let self else { return }
                guard self.settings != newSettings else { return }
                self.settings = newSettings
            }
            .store(in: &cancellables)
    }

    func setLoggingDisabled(_ disabled: Bool) {
        settingsStore.setLogging(enabled: !disabled)
    }

    func toggleClipboardWatcher(isOn: Bool) {
        settingsStore.setClipboardWatcher(enabled: isOn)
    }

    func clearHistory() {
        conversationService.clearHistory()
    }

    func setTone(_ tone: ToneStyle) {
        settingsStore.setTone(tone)
    }

    func setModel(_ model: String) {
        settingsStore.setModel(model)
    }

    func refreshModels() {
        Task {
            do {
                let models = try await ollama.listModels()
                let names = models.map { $0.name }
                await MainActor.run {
                    availableModels = names
                    if !names.contains(settingsStore.selectedModel()), let first = names.first {
                        settingsStore.setModel(first)
                    }
                }
            } catch {
                indexingStatus = "Model refresh failed: \(error.localizedDescription)"
            }
        }
    }

    func requestAccessibility() { permissions.requestAccessibility() }
    func requestScreenRecording() { permissions.requestScreenRecording() }
    func requestNotifications() { permissions.requestNotifications() }
    func openAccessibilitySettings() { permissions.openAccessibilitySettings() }
    func openScreenRecordingSettings() { permissions.openScreenRecordingSettings() }
    func openNotificationSettings() { permissions.openNotificationSettings() }

    func indexFolder(url: URL) {
        Task {
            indexingStatus = "Indexing..."
            do {
                let count = try await localIndexService.indexFolder(url)
                indexingStatus = "Indexed \(count) files from \(url.lastPathComponent)"
            } catch {
                indexingStatus = "Index failed: \(error.localizedDescription)"
            }
        }
    }

    func createMacro(name: String, steps: [MacroStep]) {
        macroService.save(Macro(name: name, steps: steps))
    }

    func deleteMacro(_ macro: Macro) {
        macroService.delete(macro)
    }
}
