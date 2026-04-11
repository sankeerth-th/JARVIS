import Foundation
import Combine

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Speech)
import Speech
#endif

struct JarvisSpeechInputPermissions: Equatable {
    var microphoneGranted: Bool
    var speechRecognitionGranted: Bool

    var isGranted: Bool {
        microphoneGranted && speechRecognitionGranted
    }
}

enum JarvisSpeechInputFailure: Error, Equatable {
    case permissionDenied
    case audioUnavailable
    case recognizerUnavailable
    case runtimeError(String)

    var message: String {
        switch self {
        case .permissionDenied:
            return "Microphone and speech recognition access are required."
        case .audioUnavailable:
            return "Audio input is unavailable."
        case .recognizerUnavailable:
            return "Speech recognition is unavailable."
        case .runtimeError(let message):
            return message
        }
    }
}

enum JarvisSpeechInputState: Equatable {
    case idle
    case requestingPermission
    case ready
    case listening
    case transcribing
    case stopping
    case failed(JarvisSpeechInputFailure)
}

struct JarvisSpeechTranscriptResult: Equatable {
    let transcript: String
    let confidence: Double?
}

struct JarvisSpeechRecognitionUpdate: Equatable {
    let transcript: String
    let isFinal: Bool
    let confidence: Double?
}

protocol JarvisSpeechInputClient {
    func requestPermissions() async -> JarvisSpeechInputPermissions
    func startRecognition(
        localeIdentifier: String?,
        onUpdate: @escaping @Sendable (Result<JarvisSpeechRecognitionUpdate, Error>) -> Void
    ) async throws
    func stopRecognition() async
    func cancelRecognition() async
}

@MainActor
final class JarvisSpeechInputService: ObservableObject {
    @Published private(set) var state: JarvisSpeechInputState = .idle
    @Published private(set) var capabilityState: VoiceInteractionState = .idle
    @Published private(set) var permissions = JarvisSpeechInputPermissions(microphoneGranted: false, speechRecognitionGranted: false)
    @Published private(set) var transcript: String = ""
    @Published private(set) var lastResult: JarvisSpeechTranscriptResult?

    private let client: JarvisSpeechInputClient

    init(client: JarvisSpeechInputClient = JarvisLiveSpeechInputClient()) {
        self.client = client
    }

    var isListening: Bool {
        switch state {
        case .listening, .transcribing, .stopping:
            return true
        default:
            return false
        }
    }

    func requestPermissions() async -> JarvisSpeechInputPermissions {
        state = .requestingPermission
        let granted = await client.requestPermissions()
        permissions = granted
        state = granted.isGranted ? .ready : .failed(.permissionDenied)
        capabilityState = .idle
        return granted
    }

    func startListening(localeIdentifier: String? = nil) async throws {
        if !permissions.isGranted {
            let granted = await requestPermissions()
            guard granted.isGranted else {
                throw JarvisSpeechInputFailure.permissionDenied
            }
        }

        transcript = ""
        lastResult = nil
        state = .listening
        capabilityState = .listening

        do {
            try await client.startRecognition(localeIdentifier: localeIdentifier) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handle(update: result)
                }
            }
        } catch let failure as JarvisSpeechInputFailure {
            state = .failed(failure)
            capabilityState = .interrupted
            throw failure
        } catch {
            let failure = JarvisSpeechInputFailure.runtimeError(error.localizedDescription)
            state = .failed(failure)
            capabilityState = .interrupted
            throw failure
        }
    }

    func stopListening() async -> JarvisSpeechTranscriptResult? {
        state = .stopping
        capabilityState = .processing
        await client.stopRecognition()
        let committed = commitTranscriptIfNeeded()
        if case .failed = state {
            return committed
        }
        state = .ready
        capabilityState = .stopped
        return committed
    }

    func cancelListening() async {
        await client.cancelRecognition()
        transcript = ""
        lastResult = nil
        state = .idle
        capabilityState = .interrupted
    }

    private func handle(update result: Result<JarvisSpeechRecognitionUpdate, Error>) {
        switch result {
        case .success(let update):
            transcript = update.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            state = transcript.isEmpty ? .listening : .transcribing
            capabilityState = transcript.isEmpty ? .listening : .processing
            if update.isFinal {
                lastResult = commitTranscriptIfNeeded(confidence: update.confidence)
                state = .ready
                capabilityState = .stopped
            }
        case .failure(let error):
            let failure = (error as? JarvisSpeechInputFailure) ?? .runtimeError(error.localizedDescription)
            state = .failed(failure)
            capabilityState = .interrupted
        }
    }

    private func commitTranscriptIfNeeded(confidence: Double? = nil) -> JarvisSpeechTranscriptResult? {
        let committed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !committed.isEmpty else { return nil }
        let result = JarvisSpeechTranscriptResult(transcript: committed, confidence: confidence)
        lastResult = result
        return result
    }
}

actor JarvisLiveSpeechInputClient: JarvisSpeechInputClient {
#if canImport(AVFoundation) && canImport(Speech)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
#endif

    func requestPermissions() async -> JarvisSpeechInputPermissions {
#if canImport(AVFoundation) && canImport(Speech)
        async let mic = requestMicrophonePermission()
        async let speech = requestSpeechPermission()
        return await JarvisSpeechInputPermissions(
            microphoneGranted: mic,
            speechRecognitionGranted: speech
        )
#else
        return JarvisSpeechInputPermissions(microphoneGranted: false, speechRecognitionGranted: false)
#endif
    }

    func startRecognition(
        localeIdentifier: String?,
        onUpdate: @escaping @Sendable (Result<JarvisSpeechRecognitionUpdate, Error>) -> Void
    ) async throws {
#if canImport(AVFoundation) && canImport(Speech)
        try await cancelAndReset()

        let locale = localeIdentifier.map(Locale.init(identifier:))
        guard let recognizer = locale.map({ SFSpeechRecognizer(locale: $0) }) ?? SFSpeechRecognizer() else {
            throw JarvisSpeechInputFailure.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw JarvisSpeechInputFailure.recognizerUnavailable
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let confidence = result.bestTranscription.segments.last.map { Double($0.confidence) }
                onUpdate(.success(.init(
                    transcript: result.bestTranscription.formattedString,
                    isFinal: result.isFinal,
                    confidence: confidence
                )))
            }
            if let error {
                onUpdate(.failure(error))
            }
        }

        audioEngine = engine
        recognitionRequest = request
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw JarvisSpeechInputFailure.audioUnavailable
        }
#else
        throw JarvisSpeechInputFailure.recognizerUnavailable
#endif
    }

    func stopRecognition() async {
#if canImport(AVFoundation) && canImport(Speech)
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
#endif
    }

    func cancelRecognition() async {
#if canImport(AVFoundation) && canImport(Speech)
        try? await cancelAndReset()
#endif
    }

#if canImport(AVFoundation) && canImport(Speech)
    private func cancelAndReset() async throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
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
