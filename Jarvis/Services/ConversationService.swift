import Foundation

struct ConversationContext {
    var selectedDocument: Document?
    var notificationDigest: String?
    var clipboardPreview: String?
    var knowledgeBaseSnippets: [String]
    var macroSummary: String?
    var requestedAction: QuickAction?

    static let empty = ConversationContext(selectedDocument: nil, notificationDigest: nil, clipboardPreview: nil, knowledgeBaseSnippets: [], macroSummary: nil, requestedAction: nil)
}

final class ConversationService {
    private let database: JarvisDatabase
    private let ollama: OllamaClient
    private let toolParser = ToolInvocationParser()

    init(database: JarvisDatabase, ollama: OllamaClient) {
        self.database = database
        self.ollama = ollama
    }

    func loadRecentConversations() -> [Conversation] {
        database.loadConversations()
    }

    func persist(_ conversation: Conversation) {
        database.saveConversation(conversation)
    }

    func clearHistory() {
        database.deleteHistory()
    }

    func streamResponse(conversation: Conversation, context: ConversationContext, settings: AppSettings) -> AsyncThrowingStream<String, Error> {
        var contextChunks: [String] = []
        if let doc = context.selectedDocument {
            contextChunks.append("Document Title: \(doc.title)\n\(doc.content.prefix(1800))")
        }
        if let notifications = context.notificationDigest {
            contextChunks.append("Notification Digest:\n\(notifications)")
        }
        if let preview = context.clipboardPreview {
            contextChunks.append("Clipboard:\n\(preview)")
        }
        if !context.knowledgeBaseSnippets.isEmpty {
            let snippets = context.knowledgeBaseSnippets.joined(separator: "\n---\n")
            contextChunks.append("Local Knowledge Base:\n\(snippets)")
        }
        if let macro = context.macroSummary {
            contextChunks.append("Active Macro Context:\n\(macro)")
        }
        if let action = context.requestedAction {
            contextChunks.append("Requested quick action: \(action.title)")
        }
        let systemPrompt = buildSystemPrompt(settings: settings)
        var messages: [OllamaChatMessage] = [
            OllamaChatMessage(role: "system", content: systemPrompt)
        ]
        if !contextChunks.isEmpty {
            messages.append(
                OllamaChatMessage(
                    role: "user",
                    content: "Context:\n" + contextChunks.joined(separator: "\n\n")
                )
            )
        }
        messages.append(contentsOf: conversation.messages.compactMap { mapToOllamaChatMessage($0) })
        let latestPrompt = conversation.messages.last(where: { $0.role == .user })?.text ?? ""
        let request = ChatRequest(
            model: settings.selectedModel,
            messages: messages,
            stream: true,
            options: streamOptions(latestPrompt: latestPrompt, hasExtraContext: !contextChunks.isEmpty)
        )
        return ollama.streamChat(request: request)
    }

    func performDocumentAction(document: Document, action: DocumentAction, settings: AppSettings) async throws -> String {
        let instruction: String
        switch action {
        case .summarize:
            instruction = "Summarize this document in 6-8 concise lines."
        case .bulletKeyPoints:
            instruction = "Return only bullet points with the key points."
        case .actionItems:
            instruction = "Extract concrete action items as a checklist."
        case .rewriteCleaner:
            instruction = "Rewrite the document to be cleaner and more professional while keeping original meaning."
        case .fixGrammar:
            instruction = "Fix grammar and spelling while preserving wording as much as possible."
        case .convertToTable:
            instruction = "Convert important structured information into a markdown table. Return only a markdown table with a header row and no commentary."
        }

        let prompt = """
        \(instruction)
        Never emit tool syntax like <<tool{...}>>.
        Avoid duplicate lines or repeated bullets.

        Document title: \(document.title)
        Document content:
        \(document.content.prefix(5000))
        """
        let request = GenerateRequest(
            model: settings.selectedModel,
            prompt: prompt,
            system: settings.systemPrompt,
            stream: false,
            options: ["temperature": 0.2, "num_predict": 420]
        )
        let raw = try await ollama.generate(request: request)
        return sanitizeModelOutput(raw)
    }

    func inferTable(text: String, settings: AppSettings) async throws -> TableExtractionResult? {
        let prompt = """
        Convert the input into strict JSON with this schema:
        {"headers":["col1","col2"],"rows":[["r1c1","r1c2"]]}
        Rules:
        - Output JSON only.
        - No markdown, no prose.
        - Preserve original values.
        - If no tabular structure is present, return {"headers":[],"rows":[]}.

        Input:
        \(text.prefix(5000))
        """
        let request = GenerateRequest(
            model: settings.selectedModel,
            prompt: prompt,
            system: settings.systemPrompt,
            stream: false,
            options: ["temperature": 0.0, "num_predict": 520]
        )
        let raw = try await ollama.generate(request: request)
        let cleaned = sanitizeModelOutput(raw)
        guard let json = extractJSONObject(from: cleaned),
              let data = json.data(using: .utf8) else {
            return nil
        }
        struct ParsedTable: Codable {
            let headers: [String]
            let rows: [[String]]
        }
        let parsed = try JSONDecoder().decode(ParsedTable.self, from: data)
        guard parsed.headers.isEmpty == false, parsed.rows.isEmpty == false else {
            return nil
        }
        let width = max(parsed.headers.count, parsed.rows.map(\.count).max() ?? 0)
        guard width > 0 else { return nil }
        let headers = normalizedHeaders(parsed.headers, width: width)
        let rows = parsed.rows.map { row -> [String] in
            if row.count >= width {
                return Array(row.prefix(width))
            }
            return row + Array(repeating: "", count: width - row.count)
        }
        return TableExtractionResult(headers: headers, rows: rows)
    }

    private func renderConversation(_ conversation: Conversation) -> String {
        conversation.messages.map { message in
            let speaker: String
            switch message.role {
            case .assistant: speaker = "Assistant"
            case .user: speaker = "User"
            case .system: speaker = "System"
            case .tool: speaker = "Tool"
            }
            return "\(speaker): \(message.text)"
        }.joined(separator: "\n")
    }

    private func mapToOllamaChatMessage(_ message: ChatMessage) -> OllamaChatMessage? {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        switch message.role {
        case .user:
            return OllamaChatMessage(role: "user", content: text)
        case .assistant:
            return OllamaChatMessage(role: "assistant", content: text)
        case .system:
            return OllamaChatMessage(role: "system", content: text)
        case .tool:
            return OllamaChatMessage(role: "user", content: "Tool output:\n\(text)")
        }
    }

    private func buildSystemPrompt(settings: AppSettings) -> String {
        let base = settings.systemPrompt
        let toolGuide = "Use the offline tools via the syntax <<tool{\"name\":\"toolName\",\"arguments\":{...}}>>. Available tools: calculate(expression), ocrCurrentWindow(reason), listNotifications(apps,limit), searchLocalDocs(query,topK), summarize(text,style). Request confirmation before OCR or file actions and wait for the tool result before continuing. Maintain \(settings.tone.promptValue) tone. Never claim to read files or screens unless given tool output."
        let strictBehavior = """
        Strict response rules:
        - Do not return generic assistant greetings.
        - Do not ask "What can I do for you?".
        - Answer the latest user question directly in the first line.
        - If information is missing, ask one focused clarification question.
        - Keep responses concise and actionable.
        """
        return [base, toolGuide, strictBehavior].joined(separator: "\n")
    }

    private func streamOptions(latestPrompt: String, hasExtraContext: Bool) -> [String: Double] {
        let tokenCount = latestPrompt
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .count
        let likelyUnclear = tokenCount < 3 || latestPrompt.contains("??")
        if !hasExtraContext && tokenCount > 0 && tokenCount <= 8 && !likelyUnclear {
            return ["temperature": 0.1, "num_predict": 220]
        }
        if likelyUnclear {
            return ["temperature": 0.2, "num_predict": 320]
        }
        return ["temperature": 0.2, "num_predict": 420]
    }

    private func sanitizeModelOutput(_ text: String) -> String {
        let stripped = toolParser.extractInvocations(from: text).cleaned
        var cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains("\\n"), !cleaned.contains("\n") {
            cleaned = cleaned.replacingOccurrences(of: "\\n", with: "\n")
        }
        if cleaned.contains("\\\"") {
            cleaned = cleaned.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractJSONObject(from text: String) -> String? {
        if text.hasPrefix("{"), text.hasSuffix("}") {
            return text
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private func normalizedHeaders(_ headers: [String], width: Int) -> [String] {
        if headers.count >= width {
            return headers.prefix(width).enumerated().map { index, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Column \(index + 1)" : trimmed
            }
        }
        let existing = headers.enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Column \(index + 1)" : trimmed
        }
        let tail = (existing.count + 1...width).map { "Column \($0)" }
        return existing + tail
    }
}

struct ToolInvocationParser {
    func extractInvocations(from text: String) -> (cleaned: String, invocations: [ToolInvocation]) {
        var remaining = text
        var collected: [ToolInvocation] = []

        while let toolRange = remaining.range(of: "tool{") {
            var removeStart = toolRange.lowerBound
            if removeStart > remaining.startIndex {
                let prior = remaining.index(before: removeStart)
                if remaining[prior] == "<" {
                    removeStart = prior
                    if prior > remaining.startIndex {
                        let secondPrior = remaining.index(before: prior)
                        if remaining[secondPrior] == "<" {
                            removeStart = secondPrior
                        }
                    }
                }
            }
            guard let endRange = remaining.range(of: ">>", range: toolRange.lowerBound..<remaining.endIndex) else {
                break
            }

            let jsonStart = remaining.index(toolRange.lowerBound, offsetBy: 4)
            let jsonRange = jsonStart..<endRange.lowerBound
            let jsonString = remaining[jsonRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonString.data(using: .utf8),
               let invocation = try? JSONDecoder().decode(ToolInvocation.self, from: data) {
                collected.append(invocation)
            }
            remaining.removeSubrange(removeStart..<endRange.upperBound)
        }
        if let danglingRange = remaining.range(of: "tool{") {
            var removeStart = danglingRange.lowerBound
            if removeStart > remaining.startIndex {
                let prior = remaining.index(before: removeStart)
                if remaining[prior] == "<" {
                    removeStart = prior
                    if prior > remaining.startIndex {
                        let secondPrior = remaining.index(before: prior)
                        if remaining[secondPrior] == "<" {
                            removeStart = secondPrior
                        }
                    }
                }
            }
            remaining.removeSubrange(removeStart..<remaining.endIndex)
        }
        return (remaining, collected)
    }
}
