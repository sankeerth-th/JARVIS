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
    @Published var selectedTone: ToneStyle = .professional

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
        self.selectedTone = settingsStore.tone()
    }

    func captureActiveWindow() {
        runCapture {
            try self.screenshotService.captureActiveWindow()
        }
    }

    func captureFullScreen() {
        runCapture {
            try self.screenshotService.captureFullScreen()
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
                let toneValue = tone ?? selectedTone
                let prompt = "Draft an email reply in a \(toneValue.promptValue) tone based on the following email thread. Cite the lines you used.\nThread:\n\(extractedText)"
                let request = GenerateRequest(model: settingsStore.selectedModel(), prompt: prompt, system: settingsStore.systemPrompt(), stream: false)
                let response = try await ollama.generate(request: request)
                await MainActor.run {
                    draft = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    selectedTone = toneValue
                    settingsStore.setTone(toneValue)
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
                    selectedTone = tone
                    settingsStore.setTone(tone)
                    statusMessage = "Tone updated: \(tone.rawValue.capitalized)"
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
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            openMailApplication(message: "Mail opened.")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-mail-\(UUID().uuidString).txt")
        do {
            try body.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            statusMessage = "Failed to prepare draft: \(error.localizedDescription)"
            return
        }
        let escapedPath = tempURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Mail"
            activate
            set messageText to read POSIX file "\(escapedPath)"
            set newMessage to make new outgoing message with properties {visible:true, subject:"", content:messageText}
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error == nil {
                statusMessage = "Opened draft in Mail"
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        openMailApplication(message: "Mail opened. Draft copied to clipboard.", failure: "Could not open Mail app. Draft copied to clipboard.")
        try? FileManager.default.removeItem(at: tempURL)
    }

    func loadMailContext(subject: String?, to: [String], cc: [String], bcc: [String], thread: String?) {
        var lines: [String] = []
        if let subject, !subject.isEmpty {
            lines.append("Subject: \(subject)")
        }
        if !to.isEmpty {
            lines.append("To: \(to.joined(separator: ", "))")
        }
        if !cc.isEmpty {
            lines.append("Cc: \(cc.joined(separator: ", "))")
        }
        if !bcc.isEmpty {
            lines.append("Bcc: \(bcc.joined(separator: ", "))")
        }
        if let thread, !thread.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Thread:\n\(thread)")
        }
        let merged = lines.joined(separator: "\n")
        guard !merged.isEmpty else { return }
        extractedText = merged
        citations = merged.split(separator: "\n").prefix(5).map { String($0.prefix(120)) }
        statusMessage = "Loaded context from Mail extension"
    }

    private func runCapture(_ capture: @escaping () throws -> NSImage) {
        Task {
            isCapturing = true
            defer { isCapturing = false }
            let shouldTemporarilyHide = NSApp.isActive
            do {
                if shouldTemporarilyHide {
                    NSApp.hide(nil)
                    try await Task.sleep(nanoseconds: 350_000_000)
                }
                let image = try capture()
                let text = try ocrService.recognizeText(from: image)
                if shouldTemporarilyHide {
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                extractedText = text
                citations = text.split(separator: "\n").prefix(5).map { String($0.prefix(120)) }
                statusMessage = "Extracted \(extractedText.count) characters"
            } catch {
                if shouldTemporarilyHide {
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                statusMessage = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    private func openMailApplication(message: String, failure: String = "Could not open Mail app.") {
        let possibleMailApps = [
            URL(fileURLWithPath: "/System/Applications/Mail.app"),
            URL(fileURLWithPath: "/Applications/Mail.app")
        ]
        if let mailAppURL = possibleMailApps.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
           #available(macOS 13.0, *) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: mailAppURL, configuration: config) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.statusMessage = "Mail open failed: \(error.localizedDescription)"
                    } else {
                        self?.statusMessage = message
                    }
                }
            }
            return
        }
        if let legacyMailURL = URL(string: "message://"),
           NSWorkspace.shared.open(legacyMailURL) {
            statusMessage = message
        } else {
            statusMessage = failure
        }
    }
}
