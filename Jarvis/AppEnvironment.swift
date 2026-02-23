import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let settingsStore = SettingsStore()
    let documentService = DocumentImportService()
    let tableExtractor = TableExtractor()
    let screenshotService = ScreenshotService()
    let ocrService = OCRService()
    let database = JarvisDatabase()
    let ollamaClient = OllamaClient()
    let notificationService = NotificationService()
    let permissionsManager = PermissionsManager.shared
    let clipboardWatcher = ClipboardWatcher()
    let hotKeyCenter = HotKeyCenter()

    lazy var localIndexService = LocalIndexService(database: database, importService: documentService, ollama: ollamaClient)
    lazy var calculator = Calculator()
    lazy var toolExecutionService = ToolExecutionService(calculator: calculator,
                                                         screenshotService: screenshotService,
                                                         ocrService: ocrService,
                                                         notificationService: notificationService,
                                                         localIndexService: localIndexService)
    lazy var conversationService = ConversationService(database: database, ollama: ollamaClient)
    lazy var macroService = MacroService(database: database)
    lazy var workflowEngine = WorkflowEngine(notificationService: notificationService,
                                            localIndexService: localIndexService,
                                            documentService: documentService,
                                            screenshotService: screenshotService,
                                            ocrService: ocrService,
                                            ollama: ollamaClient)
    lazy var diagnosticsService = DiagnosticsService(ollama: ollamaClient, database: database)

    lazy var notificationViewModel = NotificationViewModel(service: notificationService, settingsStore: settingsStore, ollama: ollamaClient)
    lazy var settingsViewModel = SettingsViewModel(settingsStore: settingsStore,
                                                   permissions: permissionsManager,
                                                   localIndexService: localIndexService,
                                                   macroService: macroService,
                                                   conversationService: conversationService,
                                                   ollama: ollamaClient)
    lazy var emailDraftViewModel = EmailDraftViewModel(screenshotService: screenshotService,
                                                       ocrService: ocrService,
                                                       ollama: ollamaClient,
                                                       settingsStore: settingsStore)
    lazy var diagnosticsViewModel = DiagnosticsViewModel(diagnosticsService: diagnosticsService,
                                                         ollama: ollamaClient,
                                                         settingsStore: settingsStore)
    lazy var commandPaletteViewModel = CommandPaletteViewModel(settingsStore: settingsStore,
                                                               conversationService: conversationService,
                                                               documentService: documentService,
                                                               tableExtractor: tableExtractor,
                                                               localIndexService: localIndexService,
                                                               macroService: macroService,
                                                               workflowEngine: workflowEngine,
                                                               toolService: toolExecutionService,
                                                               notificationViewModel: notificationViewModel,
                                                               clipboardWatcher: clipboardWatcher,
                                                               diagnosticsService: diagnosticsService,
                                                               ollama: ollamaClient)

    func startServices() {
        ollamaClient.onNetworkRequest = { [weak self] url in
            guard let self else { return }
            let settings = self.settingsStore.current
            guard settings.privacyGuardianEnabled, settings.privacyNetworkMonitorEnabled else { return }
            let host = url.host?.lowercased() ?? "unknown"
            let isLocal = host == "127.0.0.1" || host == "localhost" || host == "::1"
            let type = isLocal ? "network.local" : "network.external"
            let summary = isLocal ? "Jarvis network call -> \(host)" : "Unexpected outbound call -> \(host)"
            self.diagnosticsService.logEvent(feature: "Privacy guardian", type: type, summary: summary, metadata: ["url": url.absoluteString])
        }
        let settings = settingsStore.current
        if settings.clipboardWatcherEnabled || (settings.privacyGuardianEnabled && settings.privacyClipboardMonitorEnabled) {
            clipboardWatcher.start()
        }
    }
}
