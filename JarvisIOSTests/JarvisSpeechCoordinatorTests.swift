import XCTest
@testable import JarvisIOS

@MainActor
final class JarvisSpeechCoordinatorTests: XCTestCase {
    func testStartFailsWhenPermissionsDenied() async {
        let client = MockSpeechRecognitionClient(
            permissions: JarvisSpeechPermissions(microphoneGranted: false, speechRecognitionGranted: true)
        )
        let coordinator = JarvisSpeechCoordinator(client: client)
        var autoSendValues: [String] = []

        await coordinator.start { autoSendValues.append($0) }

        XCTAssertEqual(coordinator.state, .failed(.permissionDenied))
        XCTAssertEqual(autoSendValues, [])
        XCTAssertEqual(client.startCallCount, 0)
    }

    func testPartialTranscriptAutoSendsAfterSilence() async throws {
        let client = MockSpeechRecognitionClient()
        let coordinator = JarvisSpeechCoordinator(client: client)
        var autoSendValues: [String] = []

        await coordinator.start(
            options: JarvisSpeechSessionOptions(autoSendAfterSilence: true, silenceTimeout: 0.05)
        ) { autoSendValues.append($0) }

        client.emit(.success(JarvisSpeechRecognitionUpdate(transcript: "draft answer", isFinal: false)))
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertEqual(coordinator.lastCommittedTranscript, "draft answer")
        XCTAssertEqual(autoSendValues, ["draft answer"])
        XCTAssertEqual(client.stopCallCount, 1)
    }

    func testManualStopCommitsTranscriptWhenRequested() async {
        let client = MockSpeechRecognitionClient()
        let coordinator = JarvisSpeechCoordinator(client: client)
        var autoSendValues: [String] = []

        await coordinator.start(
            options: JarvisSpeechSessionOptions(autoSendAfterSilence: false)
        ) { autoSendValues.append($0) }

        client.emit(.success(JarvisSpeechRecognitionUpdate(transcript: "send now", isFinal: false)))
        await coordinator.stop(commitIfAvailable: true)

        XCTAssertEqual(coordinator.lastCommittedTranscript, "send now")
        XCTAssertEqual(autoSendValues, ["send now"])
        XCTAssertEqual(client.stopCallCount, 1)
    }

    func testCancelSuppressesLateResults() async throws {
        let client = MockSpeechRecognitionClient()
        let coordinator = JarvisSpeechCoordinator(client: client)
        var autoSendValues: [String] = []

        await coordinator.start(
            options: JarvisSpeechSessionOptions(autoSendAfterSilence: true, silenceTimeout: 0.05)
        ) { autoSendValues.append($0) }

        await coordinator.cancel()
        client.emit(.success(JarvisSpeechRecognitionUpdate(transcript: "stale", isFinal: false)))
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(coordinator.lastCommittedTranscript, nil)
        XCTAssertEqual(autoSendValues, [])
        XCTAssertEqual(client.cancelCallCount, 2)
    }

    func testRuntimeErrorTransitionsToFailedState() async {
        let client = MockSpeechRecognitionClient(startError: JarvisSpeechFailure.audioUnavailable)
        let coordinator = JarvisSpeechCoordinator(client: client)

        await coordinator.start { _ in }

        XCTAssertEqual(coordinator.state, .failed(.audioUnavailable))
    }
}

private final class MockSpeechRecognitionClient: JarvisSpeechRecognitionClient, @unchecked Sendable {
    private let permissions: JarvisSpeechPermissions
    private let startError: Error?
    private var updateHandler: (@Sendable (Result<JarvisSpeechRecognitionUpdate, Error>) -> Void)?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var cancelCallCount = 0

    init(
        permissions: JarvisSpeechPermissions = JarvisSpeechPermissions(microphoneGranted: true, speechRecognitionGranted: true),
        startError: Error? = nil
    ) {
        self.permissions = permissions
        self.startError = startError
    }

    func emit(_ result: Result<JarvisSpeechRecognitionUpdate, Error>) {
        updateHandler?(result)
    }

    func requestPermissions() async -> JarvisSpeechPermissions {
        permissions
    }

    func startTranscription(
        localeIdentifier: String?,
        onUpdate: @escaping @Sendable (Result<JarvisSpeechRecognitionUpdate, Error>) -> Void
    ) async throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
        updateHandler = onUpdate
    }

    func stopTranscription() async {
        stopCallCount += 1
    }

    func cancelTranscription() async {
        cancelCallCount += 1
        updateHandler = nil
    }
}
