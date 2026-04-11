import AppKit
import ApplicationServices
import Carbon.HIToolbox
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
        self.preferredContentSize = NSSize(width: 520, height: 620)
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
    @Published var userInstruction: String = ""
    @Published var clipboardPreview: String = ""
    @Published var troubleshootingMessage: String?
    @Published var contextSummary: String = ""
    @Published var extractedThreadPreview: String = ""

    private let session: MEComposeSession
    private let sessionID: UUID
    private let logger = Logger(subsystem: "com.offline.Jarvis.MailExtension", category: "PanelVM")
    private let ollamaClient = OllamaClient()

    init(session: MEComposeSession, sessionBegan: Bool) {
        self.session = session
        self.sessionID = session.sessionID
        if let persisted = JarvisMailPanelDraftStore.load(sessionID: sessionID) {
            modelName = persisted.modelName
            userInstruction = persisted.userInstruction
            extractedThreadPreview = persisted.extractedThreadPreview
            outputText = persisted.outputText
        }
        if !sessionBegan {
            troubleshootingMessage = "Compose session not available yet. Open a new compose/reply window and click Jarvis again."
        }
    }

    func onAppear() {
        logger.info("Panel onAppear. session=\(self.session.sessionID.uuidString, privacy: .public)")
        refreshContext()
        contextSummary = buildContextSummary()
        persistDraft()
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
        if extractedThreadPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !clipboardPreview.isEmpty {
            extractedThreadPreview = clipboardPreview
        }
        if clipboardPreview.isEmpty {
            statusText = "Clipboard is empty. Select email text in Mail and copy first."
        } else {
            statusText = "Loaded text from clipboard."
        }
        contextSummary = buildContextSummary()
        persistDraft()
    }

    func copyOutput() {
        guard !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        statusText = "Copied draft to clipboard."
        logger.info("Copied output to clipboard")
        persistDraft()
    }

    func copyForMailBody() {
        guard !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        statusText = "Copied for Mail body. Click message body and press Cmd+V."
        logger.info("Copied output for Mail body paste")
        persistDraft()
    }

    func insertFallback() {
        guard !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        let trusted = AXIsProcessTrusted()
        if trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                Self.sendCommandVKeystroke()
            }
            statusText = "Insert attempted. If not pasted, click message body and press Cmd+V."
            logger.info("Insert attempted via Cmd+V event")
        } else {
            // Keep flow non-blocking; avoid opening Settings repeatedly.
            statusText = "Copied. Auto-insert needs Accessibility in this extension context. Click body and press Cmd+V."
            logger.info("Insert fallback: accessibility unavailable for extension context")
        }
        persistDraft()
    }

    private func streamResponse(for action: Action) async {
        let prompt = promptForAction(action)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "Add a request or paste thread text from clipboard."
            return
        }
        isRunning = true
        outputText = ""
        statusText = "Contacting local Ollama..."
        persistDraft()
        defer { isRunning = false }
        do {
            logger.info("Starting Ollama call for action \(action.rawValue, privacy: .public)")
            var aggregated = ""
            let stream = ollamaClient.streamGenerate(
                request: GenerateRequest(
                    model: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                    prompt: prompt,
                    system: "You are Jarvis Mail Assistant. Be concise, practical, and avoid placeholders.",
                    stream: true,
                    options: ["temperature": 0.25, "num_predict": 500]
                )
            )
            for try await token in stream {
                guard !token.isEmpty else { continue }
                aggregated.append(token)
                outputText = aggregated
                statusText = "Generating..."
            }
            statusText = aggregated.isEmpty ? "No output generated. Try a different model." : "Done. Copy the output into Mail."
            logger.info("Ollama call completed. chars=\(aggregated.count, privacy: .public)")
            persistDraft()
        } catch {
            statusText = "Ollama request failed: \(error.localizedDescription)"
            logger.error("Ollama call failed: \(error.localizedDescription, privacy: .public)")
            persistDraft()
        }
    }

    private func promptForAction(_ action: Action) -> String {
        let message = session.mailMessage
        let compose = session.composeContext
        let composeSubject = normalizedSubject()
        let from = emailString(message.fromAddress)
        let originalFrom = compose.originalMessage.map { emailString($0.fromAddress) } ?? "Unknown"
        let threadSnippet = extractedThreadPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipboardText = clipboardPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = userInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = !threadSnippet.isEmpty ? threadSnippet : clipboardText

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
            Draft an email body from this local context. Keep it concise and ready to send.
            If user request is present, follow it exactly.

            Compose action: \(actionLabel)
            Subject: \(composeSubject)
            From: \(from)
            Original sender: \(originalFrom)
            Recipients: \(recipientText)
            User request:
            \(instruction)
            Context:
            \(source)
            """
        case .improve:
            return """
            Improve the tone and grammar of this email draft/context.
            Return only the improved email body.

            Subject: \(composeSubject)
            User request:
            \(instruction)
            Text:
            \(source)
            """
        case .summarize:
            return """
            Summarize this email thread in bullets:
            - Key points
            - Open items
            - Suggested short reply

            Subject: \(composeSubject)
            User request:
            \(instruction)
            Thread:
            \(source)
            """
        }
    }

    private func buildContextSummary() -> String {
        let message = session.mailMessage
        let compose = session.composeContext
        let from = emailString(message.fromAddress)
        let to = message.toAddresses.map(emailString).joined(separator: ", ")
        let cc = message.ccAddresses.map(emailString).joined(separator: ", ")
        let bcc = message.bccAddresses.map(emailString).joined(separator: ", ")
        let originalSubject = compose.originalMessage?.subject ?? "None"
        let originalFrom = compose.originalMessage.map { emailString($0.fromAddress) } ?? "None"
        let threadCount = extractedThreadPreview.trimmingCharacters(in: .whitespacesAndNewlines).count
        let headerCount = compose.originalMessage?.headers?.count ?? 0
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
        Subject: \(normalizedSubject())
        From: \(from)
        To: \(to.isEmpty ? "None" : to)
        Cc: \(cc.isEmpty ? "None" : cc)
        Bcc: \(bcc.isEmpty ? "None" : bcc)
        Original subject: \(originalSubject)
        Original sender: \(originalFrom)
        Original header count: \(headerCount)
        Thread text: \(threadCount > 0 ? "\(threadCount) chars extracted" : "No body available from MailKit")
        """
    }

    private func refreshContext() {
        let original = extractedBodyText(from: session.composeContext.originalMessage?.rawData)
        let draft = extractedBodyText(from: session.mailMessage.rawData)
        if !original.isEmpty {
            extractedThreadPreview = original
        } else if !draft.isEmpty {
            extractedThreadPreview = draft
        } else if !clipboardPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extractedThreadPreview = clipboardPreview
        } else if !extractedThreadPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Preserve previously restored user work when MailKit recreates the panel without body data.
        } else {
            extractedThreadPreview = ""
            statusText = "MailKit did not provide thread body. Copy thread text and click Paste from clipboard."
        }
        persistDraft()
    }

    private func normalizedSubject() -> String {
        let composeSubject = session.mailMessage.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !composeSubject.isEmpty {
            return composeSubject
        }
        let original = session.composeContext.originalMessage?.subject.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return original.isEmpty ? "No subject" : original
    }

    private func extractedBodyText(from rawData: Data?) -> String {
        guard let rawData else { return "" }
        return RFC822TextExtractor.extract(rawData, maxLength: 9000)
    }

    private func emailString(_ address: MEEmailAddress) -> String {
        address.addressString ?? address.rawString
    }

    private static func sendCommandVKeystroke() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func persistDraft() {
        let state = JarvisMailPanelDraftState(
            modelName: modelName,
            userInstruction: userInstruction,
            extractedThreadPreview: extractedThreadPreview,
            outputText: outputText,
            updatedAt: Date()
        )
        JarvisMailPanelDraftStore.save(state, sessionID: sessionID)
    }
}

private struct JarvisMailPanelView: View {
    @ObservedObject var viewModel: JarvisMailPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ask Jarvis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.userInstruction)
                            .font(.body)
                            .frame(height: 62)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extracted thread preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(viewModel.extractedThreadPreview.isEmpty ? "No body extracted yet. Use Paste from clipboard for reliable thread text." : viewModel.extractedThreadPreview)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 66)
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
                        .frame(minHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Copy to clipboard", action: viewModel.copyOutput)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Copy for Mail body", action: viewModel.copyForMailBody)
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
        .onChange(of: viewModel.userInstruction) { viewModel.persistDraft() }
        .onChange(of: viewModel.modelName) { viewModel.persistDraft() }
        .onChange(of: viewModel.outputText) { viewModel.persistDraft() }
        .padding(12)
        .frame(minWidth: 480, minHeight: 560)
    }
}

private enum RFC822TextExtractor {
    private struct Part {
        let headers: [String: String]
        let body: String
    }

    static func extract(_ rawData: Data, maxLength: Int) -> String {
        guard let rawText = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .isoLatin1) else {
            return ""
        }
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let split = splitHeadersAndBody(normalized)
        guard let split else { return clipped(cleanWhitespace(normalized), maxLength) }
        let (headers, body) = split
        if let boundary = mimeBoundary(from: headers) {
            let parts = multipartParts(body: body, boundary: boundary)
            if let best = preferredTextPart(from: parts) {
                return clipped(cleanWhitespace(decoded(part: best)), maxLength)
            }
        }
        return clipped(cleanWhitespace(decoded(headers: headers, body: body)), maxLength)
    }

    private static func splitHeadersAndBody(_ text: String) -> ([String: String], String)? {
        guard let separator = text.range(of: "\n\n") else { return nil }
        let headerBlock = String(text[..<separator.lowerBound])
        let body = String(text[separator.upperBound...])
        return (parseHeaders(headerBlock), body)
    }

    private static func parseHeaders(_ headerBlock: String) -> [String: String] {
        var headers: [String: String] = [:]
        var lastKey: String?
        for line in headerBlock.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), let key = lastKey {
                headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
            lastKey = key
        }
        return headers
    }

    private static func mimeBoundary(from headers: [String: String]) -> String? {
        guard let contentType = headers["content-type"]?.lowercased(),
              contentType.contains("multipart/") else {
            return nil
        }
        guard let boundaryRange = contentType.range(of: "boundary=") else { return nil }
        let rawBoundary = contentType[boundaryRange.upperBound...]
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return rawBoundary?.isEmpty == false ? rawBoundary : nil
    }

    private static func multipartParts(body: String, boundary: String) -> [Part] {
        let marker = "--\(boundary)"
        return body.components(separatedBy: marker).compactMap { chunk in
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "--", let split = splitHeadersAndBody(trimmed) else { return nil }
            return Part(headers: split.0, body: split.1)
        }
    }

    private static func preferredTextPart(from parts: [Part]) -> Part? {
        if let plain = parts.first(where: { ($0.headers["content-type"] ?? "").lowercased().contains("text/plain") }) {
            return plain
        }
        if let html = parts.first(where: { ($0.headers["content-type"] ?? "").lowercased().contains("text/html") }) {
            return html
        }
        return parts.first
    }

    private static func decoded(part: Part) -> String {
        decoded(headers: part.headers, body: part.body)
    }

    private static func decoded(headers: [String: String], body: String) -> String {
        let encoding = headers["content-transfer-encoding"]?.lowercased() ?? ""
        var decoded = body
        if encoding.contains("base64"), let data = Data(base64Encoded: body.replacingOccurrences(of: "\n", with: "")) {
            decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? body
        } else if encoding.contains("quoted-printable") {
            decoded = decodeQuotedPrintable(body)
        }
        if (headers["content-type"] ?? "").lowercased().contains("text/html") {
            return htmlToText(decoded)
        }
        return decoded
    }

    private static func decodeQuotedPrintable(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 61 { // '='
                if index + 1 < bytes.count, bytes[index + 1] == 10 {
                    index += 2
                    continue
                }
                if index + 2 < bytes.count, bytes[index + 1] == 13, bytes[index + 2] == 10 {
                    index += 3
                    continue
                }
                if index + 2 < bytes.count,
                   let hi = hexValue(bytes[index + 1]),
                   let lo = hexValue(bytes[index + 2]) {
                    output.append((hi << 4) | lo)
                    index += 3
                    continue
                }
            }
            output.append(byte)
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func htmlToText(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let text = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ).string else {
            return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        return text
    }

    private static func cleanWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clipped(_ text: String, _ maxLength: Int) -> String {
        String(text.prefix(maxLength))
    }
}
