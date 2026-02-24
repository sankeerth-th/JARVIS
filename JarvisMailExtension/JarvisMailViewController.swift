import AppKit
import MailKit
import OSLog
import SwiftUI

final class JarvisMailViewController: MEExtensionViewController {
    private let viewModel: JarvisMailPanelViewModel
    private var hostingController: NSHostingController<JarvisMailPanelView>?
    private let logger = Logger(subsystem: "com.offline.Jarvis.MailExtension", category: "ViewController")

    init(session: MEComposeSession, sessionBegan: Bool) {
        self.viewModel = JarvisMailPanelViewModel(session: session, sessionBegan: sessionBegan)
        super.init(nibName: nil, bundle: nil)
        self.title = "Jarvis"
        self.preferredContentSize = NSSize(width: 460, height: 360)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        logger.info("JarvisMailViewController loadView")
        let rootView = JarvisMailPanelView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: rootView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 360))
        container.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        self.hostingController = hosting
        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        logger.info("JarvisMailViewController viewDidAppear")
        viewModel.onAppear()
    }
}

@MainActor
private final class JarvisMailPanelViewModel: ObservableObject {
    enum Action: String {
        case draft = "Draft with Jarvis"
        case improve = "Improve tone"
        case summarize = "Summarize thread"
    }

    @Published var modelName: String = "gemma3:12b"
    @Published var outputText: String = ""
    @Published var statusText: String = "Ready"
    @Published var isRunning: Bool = false
    @Published var clipboardPreview: String = ""
    @Published var troubleshootingMessage: String?
    @Published var contextSummary: String = ""

    private let session: MEComposeSession
    private let logger = Logger(subsystem: "com.offline.Jarvis.MailExtension", category: "PanelVM")

    init(session: MEComposeSession, sessionBegan: Bool) {
        self.session = session
        if !sessionBegan {
            troubleshootingMessage = "Compose session not available yet. Open a new compose/reply window and click Jarvis again."
        }
    }

    func onAppear() {
        logger.info("Panel onAppear. session=\(self.session.sessionID.uuidString, privacy: .public)")
        contextSummary = buildContextSummary()
    }

    func run(_ action: Action) {
        logger.info("Action tapped: \(action.rawValue, privacy: .public)")
        Task {
            await streamResponse(for: action)
        }
    }

    func loadClipboard() {
        let value = NSPasteboard.general.string(forType: .string) ?? ""
        clipboardPreview = String(value.prefix(6000))
        if clipboardPreview.isEmpty {
            statusText = "Clipboard is empty. Select email text in Mail and copy first."
        } else {
            statusText = "Loaded text from clipboard."
        }
    }

    func copyOutput() {
        guard !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        statusText = "Copied draft to clipboard."
        logger.info("Copied output to clipboard")
    }

    func insertFallback() {
        statusText = "Direct insert is not available in MailKit. Use Copy and paste into the compose body."
        logger.info("Insert requested, fallback to clipboard")
    }

    private func streamResponse(for action: Action) async {
        let prompt = promptForAction(action)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "No context available. Add recipients/subject or paste thread text from clipboard."
            return
        }
        isRunning = true
        outputText = ""
        statusText = "Contacting local Ollama..."
        defer { isRunning = false }
        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/generate")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "model": modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                "prompt": prompt,
                "system": "You are Jarvis Mail Assistant. Be concise, practical, and avoid placeholders.",
                "stream": true,
                "options": ["temperature": 0.25, "num_predict": 500]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            logger.info("Starting Ollama call for action \(action.rawValue, privacy: .public)")
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                statusText = "Ollama returned an invalid response."
                logger.error("Ollama call failed with non-200 response")
                return
            }
            var aggregated = ""
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if let token = json["response"] as? String, !token.isEmpty {
                    aggregated.append(token)
                    outputText = aggregated
                    statusText = "Generating..."
                }
                if let done = json["done"] as? Bool, done {
                    break
                }
            }
            statusText = aggregated.isEmpty ? "No output generated. Try a different model." : "Done. Copy the output into Mail."
            logger.info("Ollama call completed. chars=\(aggregated.count, privacy: .public)")
        } catch {
            statusText = "Ollama request failed: \(error.localizedDescription)"
            logger.error("Ollama call failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func promptForAction(_ action: Action) -> String {
        let message = session.mailMessage
        let compose = session.composeContext
        let threadSnippet = decodedBodySnippet(from: compose.originalMessage?.rawData)
        let clipboardText = clipboardPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextText = threadSnippet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = !contextText.isEmpty ? contextText : clipboardText

        let recipientText = ([message.toAddresses, message.ccAddresses, message.bccAddresses].flatMap { $0 })
            .map(emailString)
            .joined(separator: ", ")
        let actionLabel: String
        switch compose.action {
        case .newMessage: actionLabel = "New message"
        case .reply: actionLabel = "Reply"
        case .replyAll: actionLabel = "Reply all"
        case .forward: actionLabel = "Forward"
        @unknown default: actionLabel = "Unknown"
        }

        switch action {
        case .draft:
            return """
            Draft an email body from this local context.
            Keep it concise and ready to send.

            Compose action: \(actionLabel)
            Subject: \(message.subject)
            Recipients: \(recipientText)
            Context:
            \(source)
            """
        case .improve:
            return """
            Improve the tone and grammar of this email draft/context.
            Return only the improved email body.

            Subject: \(message.subject)
            Text:
            \(source)
            """
        case .summarize:
            return """
            Summarize this email thread in bullets:
            - Key points
            - Open items
            - Suggested short reply

            Thread:
            \(source)
            """
        }
    }

    private func buildContextSummary() -> String {
        let message = session.mailMessage
        let compose = session.composeContext
        let to = message.toAddresses.map(emailString).joined(separator: ", ")
        let cc = message.ccAddresses.map(emailString).joined(separator: ", ")
        let originalSubject = compose.originalMessage?.subject ?? "None"
        let actionLabel: String
        switch compose.action {
        case .newMessage: actionLabel = "New message"
        case .reply: actionLabel = "Reply"
        case .replyAll: actionLabel = "Reply all"
        case .forward: actionLabel = "Forward"
        @unknown default: actionLabel = "Unknown"
        }
        return """
        Action: \(actionLabel)
        Subject: \(message.subject)
        To: \(to.isEmpty ? "None" : to)
        Cc: \(cc.isEmpty ? "None" : cc)
        Original subject: \(originalSubject)
        """
    }

    private func decodedBodySnippet(from rawData: Data?) -> String? {
        guard let rawData else { return nil }
        let text = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .isoLatin1)
        guard let text else { return nil }
        return String(text.prefix(8000))
    }

    private func emailString(_ address: MEEmailAddress) -> String {
        address.addressString ?? address.rawString
    }
}

private struct JarvisMailPanelView: View {
    @ObservedObject var viewModel: JarvisMailPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Jarvis")
                    .font(.headline)
                Text("Mail Assistant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let troubleshooting = viewModel.troubleshootingMessage {
                Text(troubleshooting)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("gemma3:12b", text: $viewModel.modelName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Compose context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(viewModel.contextSummary)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 84)
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                Button("Draft with Jarvis") { viewModel.run(.draft) }
                    .buttonStyle(.borderedProminent)
                Button("Improve tone") { viewModel.run(.improve) }
                    .buttonStyle(.bordered)
                Button("Summarize thread") { viewModel.run(.summarize) }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Paste from clipboard", action: viewModel.loadClipboard)
                    .buttonStyle(.bordered)
                if !viewModel.clipboardPreview.isEmpty {
                    Text("Clipboard loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $viewModel.outputText)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            HStack {
                Button("Copy to clipboard", action: viewModel.copyOutput)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Insert", action: viewModel.insertFallback)
                    .buttonStyle(.bordered)
                Spacer()
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(12)
        .frame(minWidth: 430, minHeight: 340)
    }
}
