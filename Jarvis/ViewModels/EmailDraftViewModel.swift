import Foundation
import AppKit

@MainActor
final class EmailDraftViewModel: ObservableObject {
    @Published var extractedText: String = ""
    @Published var draft: String = ""
    @Published var citations: [String] = []
    @Published var isCapturing: Bool = false
    @Published var isGenerating: Bool = false
    @Published var statusMessage: String? = nil

    private let screenshotService: ScreenshotService
    private let ocrService: OCRService
    private let ollama: OllamaClient
    private let settingsStore: SettingsStore

    init(screenshotService: ScreenshotService,
         ocrService: OCRService,
         ollama: OllamaClient,
         settingsStore: SettingsStore) {
        self.screenshotService = screenshotService
        self.ocrService = ocrService
        self.ollama = ollama
        self.settingsStore = settingsStore
    }

    func captureActiveWindow() {
        Task {
            do {
                isCapturing = true
                let image = try screenshotService.captureActiveWindow()
                let text = try ocrService.recognizeText(from: image)
                await MainActor.run {
                    extractedText = text
                    citations = text.split(separator: "\n").prefix(5).map { String($0.prefix(120)) }
                    statusMessage = "Extracted \(extractedText.count) characters"
                }
            } catch {
                statusMessage = "Capture failed: \(error.localizedDescription)"
            }
            isCapturing = false
        }
    }

    func captureFullScreen() {
        Task {
            do {
                isCapturing = true
                let image = try screenshotService.captureFullScreen()
                let text = try ocrService.recognizeText(from: image)
                await MainActor.run {
                    extractedText = text
                    citations = text.split(separator: "\n").prefix(5).map { String($0.prefix(120)) }
                }
            } catch {
                statusMessage = "Capture failed: \(error.localizedDescription)"
            }
            isCapturing = false
        }
    }

    func draftReply(tone: ToneStyle? = nil) {
        guard !extractedText.isEmpty else {
            statusMessage = "Capture or paste content first."
            return
        }
        Task {
            do {
                isGenerating = true
                let toneValue = tone ?? settingsStore.tone()
                let prompt = "Draft an email reply in a \(toneValue.promptValue) tone based on the following email thread. Cite the lines you used.\nThread:\n\(extractedText)"
                let request = GenerateRequest(model: settingsStore.selectedModel(), prompt: prompt, system: settingsStore.systemPrompt(), stream: false)
                let response = try await ollama.generate(request: request)
                await MainActor.run {
                    draft = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    statusMessage = "Draft updated"
                }
            } catch {
                statusMessage = "Draft failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    func improveTone(_ tone: ToneStyle) {
        guard !draft.isEmpty else { return }
        Task {
            do {
                isGenerating = true
                let prompt = "Rewrite the reply below to sound \(tone.promptValue) while keeping citations.\nReply:\n\(draft)"
                let request = GenerateRequest(model: settingsStore.selectedModel(), prompt: prompt, system: settingsStore.systemPrompt(), stream: false)
                let response = try await ollama.generate(request: request)
                await MainActor.run {
                    draft = response.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                statusMessage = "Tone tweak failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    func copyDraft() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft, forType: .string)
        statusMessage = "Copied to clipboard"
    }

    func openMail() {
        let encodedBody = draft.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:?body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }
}
