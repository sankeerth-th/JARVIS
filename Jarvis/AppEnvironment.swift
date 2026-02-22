import Foundation

final class AppEnvironment: ObservableObject {
    let settingsStore = SettingsStore()
    let documentService = DocumentImportService()
    let tableExtractor = TableExtractor()
    let screenshotService = ScreenshotService()
    let ocrService = OCRService()
    let database = JarvisDatabase()
    let ollamaClient = OllamaClient()
    let notificationService = NotificationService()
    let permissionsManager = PermissionsManager()
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
                                            ollama: ollamaClient)
    lazy var diagnosticsService = DiagnosticsService(ollama: ollamaClient)

    lazy var notificationViewModel = NotificationViewModel(service: notificationService)
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
        notificationService.requestPermission()
        if settingsStore.clipboardWatcherEnabled() {
            clipboardWatcher.start()
        }
    }
}
