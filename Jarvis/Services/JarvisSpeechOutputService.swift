import Foundation
import AppKit
import Combine

enum JarvisSpeechOutputState: Equatable {
    case idle
    case speaking
}

protocol JarvisSpeechSynthesizing: AnyObject {
    var delegate: NSSpeechSynthesizerDelegate? { get set }
    var isSpeaking: Bool { get }
    func startSpeaking(_ text: String) -> Bool
    func stopSpeaking()
}

extension NSSpeechSynthesizer: JarvisSpeechSynthesizing {}

@MainActor
final class JarvisSpeechOutputService: NSObject, ObservableObject, NSSpeechSynthesizerDelegate {
    @Published private(set) var state: JarvisSpeechOutputState = .idle
    @Published private(set) var capabilityState: VoiceInteractionState = .idle

    private let synthesizer: JarvisSpeechSynthesizing
    private var finishContinuations: [CheckedContinuation<Void, Never>] = []

    init(synthesizer: JarvisSpeechSynthesizing = NSSpeechSynthesizer()) {
        self.synthesizer = synthesizer
        super.init()
        self.synthesizer.delegate = self
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    func speak(_ text: String) -> Bool {
        let utterance = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else { return false }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking()
            capabilityState = .interrupted
        }
        let started = synthesizer.startSpeaking(utterance)
        state = started ? .speaking : .idle
        capabilityState = started ? .speaking : .idle
        return started
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking()
        state = .idle
        capabilityState = .stopped
        let continuations = finishContinuations
        finishContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func speakAndWait(_ text: String) async -> Bool {
        let started = speak(text)
        guard started else { return false }
        await withCheckedContinuation { continuation in
            finishContinuations.append(continuation)
        }
        return true
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        state = .idle
        capabilityState = .stopped
        let continuations = finishContinuations
        finishContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

actor JarvisStreamingSpeechService {
    enum Mode: Equatable {
        case textOnly
        case silentStreaming
        case streamingSpeech
    }

    private let speechOutputService: JarvisSpeechOutputService
    private let diagnostics: DiagnosticsService?
    private var mode: Mode = .streamingSpeech
    private var buffer: String = ""
    private var queue: [String] = []
    private var runnerTask: Task<Void, Never>?

    init(speechOutputService: JarvisSpeechOutputService, diagnostics: DiagnosticsService? = nil) {
        self.speechOutputService = speechOutputService
        self.diagnostics = diagnostics
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
    }

    func push(chunk: String) {
        guard mode == .streamingSpeech else { return }
        buffer.append(chunk)
        flushIfNeeded(force: false)
    }

    func finish() {
        guard mode == .streamingSpeech else {
            buffer = ""
            queue.removeAll()
            return
        }
        flushIfNeeded(force: true)
    }

    func cancel() async {
        buffer = ""
        queue.removeAll()
        runnerTask?.cancel()
        runnerTask = nil
        await MainActor.run {
            speechOutputService.stopSpeaking()
        }
        diagnostics?.logEvent(feature: "Voice runtime", type: "tts.cancelled", summary: "Cancelled streaming speech queue")
    }

    private func flushIfNeeded(force: Bool) {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if force { buffer = "" }
            return
        }

        let breakCharacters = CharacterSet(charactersIn: ".!?:;\n")
        let shouldFlush = force || trimmed.count > 160 || trimmed.unicodeScalars.contains(where: breakCharacters.contains)
        guard shouldFlush else { return }

        let segment: String
        if force {
            segment = trimmed
            buffer = ""
        } else if let range = buffer.rangeOfCharacter(from: breakCharacters, options: .backwards) {
            segment = String(buffer[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            segment = trimmed
            buffer = ""
        }

        guard !segment.isEmpty else { return }
        queue.append(segment)
        diagnostics?.logEvent(feature: "Voice runtime", type: "tts.chunk_enqueued", summary: "Queued incremental speech chunk", metadata: ["length": String(segment.count)])
        startRunnerIfNeeded()
    }

    private func startRunnerIfNeeded() {
        guard runnerTask == nil else { return }
        runnerTask = Task {
            while !Task.isCancelled {
                let next = await dequeue()
                guard let next else { break }
                diagnostics?.logEvent(feature: "Voice runtime", type: "tts.chunk_started", summary: "Started speaking incremental chunk", metadata: ["length": String(next.count)])
                let success = await speechOutputService.speakAndWait(next)
                diagnostics?.logEvent(
                    feature: "Voice runtime",
                    type: success ? "tts.chunk_finished" : "tts.chunk_skipped",
                    summary: success ? "Finished speaking incremental chunk" : "Skipped incremental speech chunk",
                    metadata: ["length": String(next.count)]
                )
            }
            await setRunnerFinished()
        }
    }

    private func dequeue() -> String? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    private func setRunnerFinished() {
        runnerTask = nil
    }
}
