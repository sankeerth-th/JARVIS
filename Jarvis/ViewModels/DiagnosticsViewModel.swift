import Foundation

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published var statuses: [DiagnosticStatus] = []
    @Published var moduleHealth: [ModuleHealthStatus] = []
    @Published var latency: TimeInterval = 0
    @Published var lastUpdated: Date? = nil

    private let diagnosticsService: DiagnosticsService
    private let ollama: OllamaClient
    private let settingsStore: SettingsStore

    init(diagnosticsService: DiagnosticsService, ollama: OllamaClient, settingsStore: SettingsStore) {
        self.diagnosticsService = diagnosticsService
        self.ollama = ollama
        self.settingsStore = settingsStore
    }

    func refresh() {
        Task {
            let statuses = await diagnosticsService.fetchStatuses(selectedModel: settingsStore.selectedModel())
            let moduleHealth = await diagnosticsService.moduleHealth(settings: settingsStore.current)
            await MainActor.run {
                self.statuses = statuses
                self.moduleHealth = moduleHealth
                self.lastUpdated = Date()
            }
        }
        Task {
            let value = await measureLatency()
            await MainActor.run {
                self.latency = value
            }
        }
    }

    private func measureLatency() async -> TimeInterval {
        let prompt = GenerateRequest(model: settingsStore.selectedModel(), prompt: "Say ok", system: settingsStore.systemPrompt(), stream: true)
        let stream = ollama.streamGenerate(request: prompt)
        let start = Date()
        do {
            for try await chunk in stream {
                if !chunk.isEmpty { return Date().timeIntervalSince(start) }
            }
        } catch {}
        return 0
    }
}
