import XCTest
@testable import Jarvis

final class JarvisMacCapabilityServicesTests: XCTestCase {
    @MainActor
    func testToolExecutionServiceApprovalPreviewMarksRequiresApproval() {
        let service = makeToolService()
        let preview = service.approvalPreview(for: ToolInvocation(name: .shellRunSafe, arguments: ["command": "pwd"]))

        XCTAssertEqual(preview.state, .requiresApproval)
        XCTAssertEqual(preview.metadata["tool"], ToolInvocation.ToolName.shellRunSafe.rawValue)
        XCTAssertEqual(preview.metadata["approvalRequired"], "true")
    }

    @MainActor
    func testToolExecutionServiceVoiceListenReturnsExecutingState() async throws {
        let speechInput = JarvisSpeechInputService(client: FakeSpeechInputClient())
        let service = makeToolService(speechInputService: speechInput)

        let result = try await service.execute(
            ToolInvocation(name: .voiceListen, arguments: [:]),
            context: ToolExecutionContext(settings: .default, requestedByUser: false)
        )

        XCTAssertEqual(result.state, .executing)
        XCTAssertEqual(result.voiceState, .listening)
    }

    func testSafeShellRejectsDisallowedCommands() async {
        let service = JarvisSafeShellService(runner: RecordingProcessRunner())
        let policy = makePolicy()

        let result = await service.runAllowedCommand(
            SafeShellCommandRequest(command: "rm", arguments: ["-rf", "/tmp/nope"]),
            policy: policy
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.exitCode, -1)
        XCTAssertEqual(result.stderr, "disallowed")
    }

    func testSafeShellRejectsReadsOutsideApprovedRoots() async throws {
        let service = JarvisSafeShellService(runner: RecordingProcessRunner())
        let allowedRoot = try temporaryDirectory(named: "allowed")
        let outsideRoot = try temporaryDirectory(named: "outside")
        let policy = makePolicy(indexedFolders: [allowedRoot.path])

        let result = await service.runAllowedCommand(
            SafeShellCommandRequest(command: "ls", arguments: [outsideRoot.path]),
            policy: policy
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.stderr, "disallowed")
    }

    func testOpenURLRejectsUnsupportedSchemes() {
        let service = JarvisMacActionService()

        let result = service.openURL("file:///Users/sanks04/Desktop/JARVIS")

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("Only http, https, and mailto URLs are allowed."))
    }

    func testProjectScaffoldCreatesSwiftPackageInsideApprovedRoot() throws {
        let parent = try temporaryDirectory(named: "workspace")
        let target = parent.appendingPathComponent("SampleProject", isDirectory: true)
        let policy = JarvisPathSafetyPolicy(readableRoots: [parent], writableRoots: [parent])
        let service = JarvisProjectActionService()

        let result = service.scaffoldProject(at: target.path, template: .swiftPackage, policy: policy)

        XCTAssertTrue(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("Package.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("Sources/SampleProject/main.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("Tests/SampleProjectTests/SampleProjectTests.swift").path))
    }

    @MainActor
    func testSpeechOutputServiceStopsPreviousUtteranceBeforeStartingNewOne() async {
        let synthesizer = FakeSpeechSynthesizer()
        let service = JarvisSpeechOutputService(synthesizer: synthesizer)

        let first = service.speak("Hello")
        let second = service.speak("Again")

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(synthesizer.startCalls, ["Hello", "Again"])
        XCTAssertEqual(synthesizer.stopCalls, 1)
        XCTAssertEqual(service.capabilityState, .speaking)
    }

    @MainActor
    func testSpeechInputServiceTracksCapabilityStates() async throws {
        let service = JarvisSpeechInputService(client: FakeSpeechInputClient())

        try await service.startListening()
        XCTAssertEqual(service.capabilityState, .listening)

        _ = await service.stopListening()
        XCTAssertEqual(service.capabilityState, .stopped)
    }

    private func makePolicy(indexedFolders: [String] = []) -> JarvisPathSafetyPolicy {
        var settings = AppSettings.default
        settings.indexedFolders = indexedFolders
        return JarvisPathSafetyPolicy(settings: settings)
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        return url
    }

    @MainActor
    private func makeToolService(
        speechInputService: JarvisSpeechInputService? = nil,
        speechOutputService: JarvisSpeechOutputService? = nil
    ) -> ToolExecutionService {
        let database = JarvisDatabase(filename: "JarvisTests-\(UUID().uuidString).sqlite")
        let importService = DocumentImportService()
        let ollama = OllamaClient()
        let localIndexService = LocalIndexService(database: database, importService: importService, ollama: ollama)
        return ToolExecutionService(
            calculator: Calculator(),
            screenshotService: ScreenshotService(),
            ocrService: OCRService(),
            notificationService: NotificationService(),
            localIndexService: localIndexService,
            macActionService: JarvisMacActionService(),
            projectActionService: JarvisProjectActionService(),
            safeShellService: JarvisSafeShellService(runner: RecordingProcessRunner()),
            speechInputService: speechInputService ?? JarvisSpeechInputService(client: FakeSpeechInputClient()),
            speechOutputService: speechOutputService ?? JarvisSpeechOutputService(synthesizer: FakeSpeechSynthesizer())
        )
    }
}

private struct RecordingProcessRunner: JarvisProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeout: TimeInterval
    ) async -> SafeShellCommandResult {
        SafeShellCommandResult(
            success: true,
            userMessage: "ran",
            stdout: executableURL.lastPathComponent,
            stderr: "",
            exitCode: 0,
            commandDescription: ([executableURL.path] + arguments).joined(separator: " ")
        )
    }
}

private final class FakeSpeechSynthesizer: JarvisSpeechSynthesizing {
    weak var delegate: NSSpeechSynthesizerDelegate?
    private(set) var isSpeaking = false
    private(set) var startCalls: [String] = []
    private(set) var stopCalls = 0

    func startSpeaking(_ text: String) -> Bool {
        startCalls.append(text)
        isSpeaking = true
        return true
    }

    func stopSpeaking() {
        stopCalls += 1
        isSpeaking = false
    }
}

private actor FakeSpeechInputClient: JarvisSpeechInputClient {
    func requestPermissions() async -> JarvisSpeechInputPermissions {
        JarvisSpeechInputPermissions(microphoneGranted: true, speechRecognitionGranted: true)
    }

    func startRecognition(
        localeIdentifier: String?,
        onUpdate: @escaping @Sendable (Result<JarvisSpeechRecognitionUpdate, Error>) -> Void
    ) async throws {
        _ = localeIdentifier
    }

    func stopRecognition() async {}

    func cancelRecognition() async {}
}
