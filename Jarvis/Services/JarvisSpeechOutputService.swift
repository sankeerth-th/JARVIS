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
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        state = .idle
        capabilityState = .stopped
    }
}
