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

    func streamResponse(for prompt: String, conversation: Conversation, context: ConversationContext, settings: AppSettings) -> AsyncThrowingStream<String, Error> {
        let conversationText = renderConversation(conversation) + "\nUser: \(prompt)\nAssistant:"
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
        let contextualPrompt = (contextChunks.isEmpty ? "" : "Context:\n" + contextChunks.joined(separator: "\n\n"))
        let systemPrompt = buildSystemPrompt(settings: settings)
        let request = GenerateRequest(
            model: settings.selectedModel,
            prompt: contextualPrompt + "\n" + conversationText,
            system: systemPrompt,
            stream: true,
            options: ["temperature": 0.2, "num_predict": 320]
        )
        return ollama.streamGenerate(request: request)
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

    private func buildSystemPrompt(settings: AppSettings) -> String {
        let base = settings.systemPrompt
        let toolGuide = "Use the offline tools via the syntax <<tool{\"name\":\"toolName\",\"arguments\":{...}}>>. Available tools: calculate(expression), ocrCurrentWindow(reason), listNotifications(apps,limit), searchLocalDocs(query,topK), summarize(text,style). Request confirmation before OCR or file actions and wait for the tool result before continuing. Maintain \(settings.tone.promptValue) tone. Never claim to read files or screens unless given tool output."
        return base + "\n" + toolGuide
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
