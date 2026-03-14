import Combine
import Foundation

#if canImport(AVFAudio)
import AVFAudio
#endif

#if canImport(Speech)
import Speech
#endif

public struct JarvisSpeechPermissions: Equatable, Sendable {
    public var microphoneGranted: Bool
    public var speechRecognitionGranted: Bool

    public init(microphoneGranted: Bool, speechRecognitionGranted: Bool) {
        self.microphoneGranted = microphoneGranted
        self.speechRecognitionGranted = speechRecognitionGranted
    }

    public var isGranted: Bool {
        microphoneGranted && speechRecognitionGranted
    }
}

public enum JarvisSpeechFailure: Error, Equatable, Sendable {
    case permissionDenied
    case audioUnavailable
    case recognizerUnavailable
    case runtimeError(String)

    public var message: String {
        switch self {
        case .permissionDenied:
            return "Microphone and speech recognition access are required."
        case .audioUnavailable:
            return "Audio input is unavailable on this device."
        case .recognizerUnavailable:
            return "Speech recognition is not available for the selected language."
        case .runtimeError(let message):
            return message
        }
    }
}

public enum JarvisSpeechState: Equatable, Sendable {
    case idle
    case requestingPermission
    case ready
    case listening
    case transcribing
    case stopping
    case failed(JarvisSpeechFailure)
}

public struct JarvisSpeechSessionOptions: Equatable, Sendable {
    public var localeIdentifier: String?
    public var autoSendAfterSilence: Bool
    public var silenceTimeout: TimeInterval

    public init(
        localeIdentifier: String? = nil,
        autoSendAfterSilence: Bool = true,
        silenceTimeout: TimeInterval = 1.2
    ) {
        self.localeIdentifier = localeIdentifier
        self.autoSendAfterSilence = autoSendAfterSilence
        self.silenceTimeout = silenceTimeout
    }
}

public struct JarvisSpeechRecognitionUpdate: Equatable, Sendable {
    public var transcript: String
    public var isFinal: Bool

    public init(transcript: String, isFinal: Bool) {
        self.transcript = transcript
        self.isFinal = isFinal
    }
}

public protocol JarvisSpeechRecognitionClient: Sendable {
    func requestPermissions() async -> JarvisSpeechPermissions
    func startTranscription(
        localeIdentifier: String?,
        onUpdate: @escaping @Sendable (Result<JarvisSpeechRecognitionUpdate, Error>) -> Void
    ) async throws
    func stopTranscription() async
    func cancelTranscription() async
}

@MainActor
public final class JarvisSpeechCoordinator: ObservableObject {
    @Published public private(set) var state: JarvisSpeechState = .idle
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var permissions = JarvisSpeechPermissions(
        microphoneGranted: false,
        speechRecognitionGranted: false
    )
    @Published public private(set) var lastCommittedTranscript: String?

    private let client: JarvisSpeechRecognitionClient
    private var silenceTask: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var activeOptions = JarvisSpeechSessionOptions()
    private var autoSendHandler: (@Sendable (String) -> Void)?

    public init(client: JarvisSpeechRecognitionClient = JarvisLiveSpeechRecognitionClient()) {
        self.client = client
    }

    public var isListening: Bool {
        switch state {
        case .listening, .transcribing:
            return true
        default:
            return false
        }
    }

    public func start(
        options: JarvisSpeechSessionOptions = JarvisSpeechSessionOptions(),
        onAutoSend: (@escaping @Sendable (String) -> Void)
    ) async {
        await stopInternal(cancelOnly: true)

        activeOptions = options
        autoSendHandler = onAutoSend
        lastCommittedTranscript = nil
        transcript = ""
        state = .requestingPermission

        let permissions = await client.requestPermissions()
        self.permissions = permissions

        guard permissions.isGranted else {
            state = .failed(.permissionDenied)
            return
        }

        let sessionID = UUID()
        activeSessionID = sessionID

        do {
            try await client.startTranscription(localeIdentifier: options.localeIdentifier) { [weak self] result in
                Task { @MainActor in
                    self?.handleRecognitionResult(result, for: sessionID)
                }
            }
            state = .listening
        } catch let failure as JarvisSpeechFailure {
            activeSessionID = nil
            state = .failed(failure)
        } catch {
            activeSessionID = nil
            state = .failed(.runtimeError(error.localizedDescription))
        }
    }

    public func stop(commitIfAvailable: Bool) async {
        state = .stopping
        silenceTask?.cancel()
        silenceTask = nil
        await client.stopTranscription()

        if commitIfAvailable {
            commitTranscriptIfNeeded()
        }

        activeSessionID = nil
        if case .failed = state {
            return
        }
        if !commitIfAvailable || lastCommittedTranscript == nil {
            state = .ready
        }
    }

    public func cancel() async {
        await stopInternal(cancelOnly: true)
        state = .idle
    }

    public func clearTranscript() {
        transcript = ""
        lastCommittedTranscript = nil
    }

    private func stopInternal(cancelOnly: Bool) async {
        silenceTask?.cancel()
        silenceTask = nil
        activeSessionID = nil
        if cancelOnly {
            await client.cancelTranscription()
        } else {
            await client.stopTranscription()
        }
    }

    private func handleRecognitionResult(
        _ result: Result<JarvisSpeechRecognitionUpdate, Error>,
        for sessionID: UUID
    ) {
        guard activeSessionID == sessionID else { return }

        switch result {
        case .success(let update):
            transcript = update.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            state = transcript.isEmpty ? .listening : .transcribing

            if update.isFinal {
                silenceTask?.cancel()
                commitTranscriptIfNeeded()
                activeSessionID = nil
                state = .ready
                return
            }

            scheduleSilenceTimer(for: sessionID)
        case .failure(let error):
            activeSessionID = nil
            silenceTask?.cancel()
            silenceTask = nil
            if let failure = error as? JarvisSpeechFailure {
                state = .failed(failure)
            } else {
                state = .failed(.runtimeError(error.localizedDescription))
            }
        }
    }

    private func scheduleSilenceTimer(for sessionID: UUID) {
        guard activeOptions.autoSendAfterSilence else { return }
        guard !transcript.isEmpty else { return }

        silenceTask?.cancel()
        let timeout = activeOptions.silenceTimeout
        silenceTask = Task { [weak self] in
            let duration = UInt64(max(timeout, 0.2) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)
            await MainActor.run {
                guard let self, self.activeSessionID == sessionID else { return }
                self.commitTranscriptIfNeeded()
                self.activeSessionID = nil
                self.state = .ready
            }
            await self?.client.stopTranscription()
        }
    }

    private func commitTranscriptIfNeeded() {
        let committed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !committed.isEmpty else { return }
        lastCommittedTranscript = committed
        autoSendHandler?(committed)
        transcript = ""
    }
}

public actor JarvisLiveSpeechRecognitionClient: JarvisSpeechRecognitionClient {
#if canImport(AVFAudio) && canImport(Speech)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
#endif

    public init() {}

    public func requestPermissions() async -> JarvisSpeechPermissions {
#if canImport(AVFAudio) && canImport(Speech)
        async let microphoneGranted = requestMicrophonePermission()
        async let speechGranted = requestSpeechPermission()
        return await JarvisSpeechPermissions(
            microphoneGranted: microphoneGranted,
            speechRecognitionGranted: speechGranted
        )
#else
        return JarvisSpeechPermissions(microphoneGranted: false, speechRecognitionGranted: false)
#endif
    }

    public func startTranscription(
        localeIdentifier: String?,
        onUpdate: @escaping @Sendable (Result<JarvisSpeechRecognitionUpdate, Error>) -> Void
    ) async throws {
#if canImport(AVFAudio) && canImport(Speech)
        try await cancelAndReset()

        let locale = localeIdentifier.map(Locale.init(identifier:))
        guard let recognizer = locale.map({ SFSpeechRecognizer(locale: $0) }) ?? SFSpeechRecognizer() else {
            throw JarvisSpeechFailure.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw JarvisSpeechFailure.recognizerUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw JarvisSpeechFailure.audioUnavailable
        }

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        self.audioEngine = audioEngine
        self.recognitionRequest = request
        self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                onUpdate(.success(JarvisSpeechRecognitionUpdate(
                    transcript: result.bestTranscription.formattedString,
                    isFinal: result.isFinal
                )))
            }

            if let error {
                onUpdate(.failure(error))
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw JarvisSpeechFailure.audioUnavailable
        }
#else
        throw JarvisSpeechFailure.recognizerUnavailable
#endif
    }

    public func stopTranscription() async {
#if canImport(AVFAudio) && canImport(Speech)
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }

    public func cancelTranscription() async {
#if canImport(AVFAudio) && canImport(Speech)
        try? await cancelAndReset()
#endif
    }

#if canImport(AVFAudio) && canImport(Speech)
    private func cancelAndReset() async throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
#endif
}
