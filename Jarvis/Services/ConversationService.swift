import Foundation

struct KnowledgeSearchResult: Equatable {
    let title: String
    let path: String
    let excerpt: String
    let score: Double
    let sourceType: String?
}

struct ConversationContext {
    var selectedDocument: Document?
    var notificationDigest: String?
    var clipboardPreview: String?
    var knowledgeBaseSnippets: [String]
    var knowledgeSearchResults: [KnowledgeSearchResult]
    var macroSummary: String?
    var requestedAction: QuickAction?

    static let empty = ConversationContext(
        selectedDocument: nil,
        notificationDigest: nil,
        clipboardPreview: nil,
        knowledgeBaseSnippets: [],
        knowledgeSearchResults: [],
        macroSummary: nil,
        requestedAction: nil
    )
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

    func streamResponse(conversation: Conversation, context: ConversationContext, routePlan: RoutePlan, settings: AppSettings) -> AsyncThrowingStream<String, Error> {
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
        
        // Enhanced knowledge base context with full excerpts
        if !context.knowledgeSearchResults.isEmpty {
            let knowledgeContext = buildKnowledgeContext(results: context.knowledgeSearchResults, maxTokens: 3000)
            contextChunks.append(knowledgeContext)
        } else if !context.knowledgeBaseSnippets.isEmpty {
            // Fallback to legacy snippets
            let snippets = context.knowledgeBaseSnippets.joined(separator: "\n---\n")
            contextChunks.append("Local Knowledge Base:\n\(snippets)")
        }
        
        if let macro = context.macroSummary {
            contextChunks.append("Active Macro Context:\n\(macro)")
        }
        if let action = context.requestedAction {
            contextChunks.append("Requested quick action: \(action.title)")
        }
        contextChunks.append("Memory scope: \(routePlan.memoryScope.rawValue)")
        let systemPrompt = buildSystemPrompt(settings: settings, routePlan: routePlan)
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
        let scopedMessages = ConversationScopeFilter.messages(for: conversation, routePlan: routePlan)
        messages.append(contentsOf: scopedMessages.compactMap { mapToOllamaChatMessage($0) })
        let latestPrompt = conversation.messages.last(where: { $0.role == .user })?.text ?? ""
        let request = ChatRequest(
            model: settings.selectedModel,
            messages: messages,
            stream: true,
            options: streamOptions(latestPrompt: latestPrompt, hasExtraContext: !contextChunks.isEmpty, routePlan: routePlan)
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

    private func buildSystemPrompt(settings: AppSettings, routePlan: RoutePlan) -> String {
        let base = settings.systemPrompt
        let toolGuide = allowedToolGuide(for: routePlan, tone: settings.tone)
        let routePrompt = promptTemplateInstructions(for: routePlan.promptTemplate)
        let strictBehavior = """
        Strict response rules:
        - Do not return generic assistant greetings.
        - Do not ask "What can I do for you?".
        - Answer the latest user question directly in the first line.
        - If information is missing, ask one focused clarification question.
        - Keep responses concise and actionable.
        """
        return [base, routePrompt, toolGuide, strictBehavior].joined(separator: "\n")
    }

    private func streamOptions(latestPrompt: String, hasExtraContext: Bool, routePlan: RoutePlan) -> [String: Double] {
        let tokenCount = latestPrompt
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .count
        let likelyUnclear = tokenCount < 3 || latestPrompt.contains("??")
        if routePlan.intent == .searchQuery || routePlan.intent == .diagnosticsQuery {
            return ["temperature": 0.1, "num_predict": 260]
        }
        if routePlan.intent == .reflectiveMode || routePlan.intent == .explanationMode {
            return ["temperature": 0.25, "num_predict": 460]
        }
        if !hasExtraContext && tokenCount > 0 && tokenCount <= 8 && !likelyUnclear {
            return ["temperature": 0.1, "num_predict": 220]
        }
        if likelyUnclear {
            return ["temperature": 0.2, "num_predict": 320]
        }
        return ["temperature": 0.2, "num_predict": 420]
    }

    private func promptTemplateInstructions(for template: PromptTemplateID) -> String {
        switch template {
        case .generalChat:
            return "Template: General Chat. Answer clearly and directly. Use only explicitly provided context."
        case .searchAssistant:
            return "Template: Search Assistant. Focus on retrieval intent, quote matching snippets, and mention confidence."
        case .documentRewrite:
            return "Template: Document Rewrite. Operate only on the provided document content and requested transformation."
        case .ocrInterpreter:
            return "Template: OCR Interpreter. Treat OCR text as noisy. Clarify uncertain reads before strong claims."
        case .mailDraft:
            return "Template: Mail Draft. Produce concise, actionable draft language with explicit assumptions."
        case .diagnostics:
            return "Template: Diagnostics. Use only local signals, cite what was used, and include uncertainty."
        case .reflective:
            return "Template: Reflective. Ask one focused follow-up question when needed and structure tradeoffs."
        case .explanation:
            return "Template: Explanation. Explain root cause, evidence, and next checks in order."
        case .quickAction:
            return "Template: Quick Action. Perform only the requested quick action and do not switch modes."
        }
    }

    private func allowedToolGuide(for routePlan: RoutePlan, tone: ToneStyle) -> String {
        let available = routePlan.allowedTools
        if available.isEmpty {
            return "Tool policy: No tool calls allowed for this route. Never emit tool syntax. Maintain \(tone.promptValue) tone."
        }
        let signatures: [ToolInvocation.ToolName: String] = [
            .calculate: "calculate(expression)",
            .ocrCurrentWindow: "ocrCurrentWindow(reason)",
            .listNotifications: "listNotifications(apps,limit)",
            .searchLocalDocs: "searchLocalDocs(query,topK)",
            .summarize: "summarize(text,style)",
            .appOpen: "app.open(target)",
            .appFocus: "app.focus(target)",
            .finderReveal: "finder.reveal(path)",
            .systemOpenURL: "system.open_url(url)",
            .projectOpen: "project.open(path)",
            .projectScaffold: "project.scaffold(path,template)",
            .shellRunSafe: "shell.run.safe(command,arguments,workingDirectory,timeout)",
            .voiceListen: "voice.listen(locale)",
            .voiceSpeak: "voice.speak(text)",
            .voiceStop: "voice.stop()"
        ]
        let ordered = available.compactMap { signatures[$0] }
        return "Tool policy: Use offline tools only via <<tool{\"name\":\"toolName\",\"arguments\":{...}}>>. Allowed tools for this route: \(ordered.joined(separator: ", ")). Maintain \(tone.promptValue) tone. Never claim to read files or screens unless given tool output."
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

    private func buildKnowledgeContext(results: [KnowledgeSearchResult], maxTokens: Int) -> String {
        var parts: [String] = []
        parts.append("Retrieved local documents (ranked by relevance):")
        
        var remainingChars = maxTokens * 4 // Approximate 4 chars per token
        for (index, result) in results.enumerated() {
            let rank = index + 1
            let excerpt = result.excerpt.prefix(800)
            let entry = """
            [Source \(rank)] \(result.title) (\(result.sourceType ?? "document"))
            Path: \(result.path)
            Excerpt: \(excerpt)
            """
            if entry.count > remainingChars {
                break
            }
            parts.append(entry)
            remainingChars -= entry.count
        }
        
        parts.append("Use the above excerpts to answer the user's question. Cite sources like [Source 1], [Source 2] when referencing specific information.")
        return parts.joined(separator: "\n\n")
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

enum ConversationScopeFilter {
    static func messages(for conversation: Conversation, routePlan: RoutePlan, maxCount: Int = 24) -> [ChatMessage] {
        let targetScope = routePlan.memoryScope.rawValue
        let filtered = conversation.messages.filter { message in
            let taggedScope = message.metadata["memoryScope"]
            switch routePlan.memoryScope {
            case .chatThread:
                // Preserve legacy untagged messages for default chat, but drop explicitly transient scopes.
                return taggedScope == nil || taggedScope == targetScope
            default:
                // Non-chat routes are strictly scoped to matching memory context only.
                return taggedScope == targetScope
            }
        }

        var output = filtered
        if routePlan.memoryScope != .chatThread,
           let latestUser = conversation.messages.last(where: { $0.role == .user }),
           output.contains(where: { $0.id == latestUser.id }) == false {
            // Legacy fallback: always include latest user turn so new scoped routes stay usable.
            output.append(latestUser)
        }

        if output.count > max(1, maxCount) {
            return Array(output.suffix(maxCount))
        }
        return output
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

final class IntentClassifier {
    func classify(prompt: String, signal: RouteSignal) -> IntentClassification {
        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var reasons: [String] = []

        if signal.quickActionKind != nil {
            reasons.append("Quick action was explicitly selected")
            return IntentClassification(intent: .quickActionCommand, confidence: 0.95, reasons: reasons)
        }

        if signal.selectedSurface == .fileSearch
            || containsAny(normalized, terms: ["search my files", "find file", "latest invoice", "where is", "in my docs", "search docs"]) {
            reasons.append("Query asks to locate content or files")
            return IntentClassification(intent: .searchQuery, confidence: 0.88, reasons: reasons)
        }
        
        // Auto-detect file/knowledge queries even without explicit "search" command
        if shouldAutoTriggerKnowledgeSearch(normalized, signal: signal) {
            reasons.append("Query likely refers to local documents or knowledge")
            return IntentClassification(intent: .searchQuery, confidence: 0.75, reasons: reasons)
        }

        if signal.selectedSurface == .documents
            || containsAny(normalized, terms: ["rewrite this document", "summarize this document", "fix grammar", "action items", "convert to table"]) {
            reasons.append("Prompt references document transformation workflow")
            return IntentClassification(intent: .documentTransform, confidence: 0.84, reasons: reasons)
        }

        if containsAny(normalized, terms: ["ocr", "screenshot", "screen text", "scan this", "extract text from image"]) {
            reasons.append("Prompt requests OCR-derived extraction or interpretation")
            return IntentClassification(intent: .ocrExtract, confidence: 0.82, reasons: reasons)
        }

        if signal.selectedSurface == .diagnostics
            || signal.selectedSurface == .why
            || containsAny(normalized, terms: ["why did this happen", "diagnose", "root cause", "what failed", "debug this"]) {
            reasons.append("Prompt is diagnostic or explanation-seeking")
            return IntentClassification(intent: .diagnosticsQuery, confidence: 0.86, reasons: reasons)
        }

        if signal.selectedSurface == .macros || containsAny(normalized, terms: ["run macro", "workflow step", "execute macro"]) {
            reasons.append("Prompt targets macro execution")
            return IntentClassification(intent: .macroExecution, confidence: 0.83, reasons: reasons)
        }

        if signal.selectedSurface == .thinking || containsAny(normalized, terms: ["think with me", "brainstorm", "tradeoffs", "options analysis"]) {
            reasons.append("Prompt asks for reflective reasoning mode")
            return IntentClassification(intent: .reflectiveMode, confidence: 0.81, reasons: reasons)
        }

        if containsAny(normalized, terms: ["explain why", "explain this", "how did this happen"]) {
            reasons.append("Prompt asks for explanatory mode")
            return IntentClassification(intent: .explanationMode, confidence: 0.72, reasons: reasons)
        }

        if signal.selectedSurface == .email || containsAny(normalized, terms: ["draft email", "reply email", "mail response"]) {
            reasons.append("Prompt is email drafting oriented")
            return IntentClassification(intent: .mailDraft, confidence: 0.70, reasons: reasons)
        }

        let confidence = tokens.count <= 2 ? 0.45 : 0.62
        reasons.append("No strong mode signal, defaulting to general chat")
        return IntentClassification(intent: .generalChat, confidence: confidence, reasons: reasons)
    }

    private func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
    
    private func shouldAutoTriggerKnowledgeSearch(_ normalized: String, signal: RouteSignal) -> Bool {
        // Triggers for questions that likely refer to user's own files/content
        let knowledgeIndicators = [
            "my resume", "my cv", "my notes", "my document", "my pdf",
            "the report", "the invoice", "the contract", "the agreement",
            "what did i write about", "what does my", "where did i save",
            "summarize my", "what's in my", "content of my", "text from my",
            "screenshot about", "image showing", "photo of",
            "meeting notes", "project notes", "research notes",
            "last week", "yesterday", "recent file", "latest version"
        ]
        
        // Check for possessive file references
        if containsAny(normalized, terms: knowledgeIndicators) {
            return true
        }
        
        // Check for question patterns about content
        let questionPatterns = [
            "what does",
            "where is",
            "summarize",
            "explain the",
            "content of",
            "information about"
        ]
        if questionPatterns.contains(where: { normalized.hasPrefix($0) }) && signal.hasIndexedFolders {
            return true
        }
        
        return false
    }
}

final class RoutePlanner {
    func makePlan(classification: IntentClassification, signal: RouteSignal) -> RoutePlan {
        switch classification.intent {
        case .generalChat:
            return RoutePlan(
                intent: .generalChat,
                promptTemplate: .generalChat,
                memoryScope: .chatThread,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: false,
                    includeNotificationContext: false,
                    includeClipboardContext: false,
                    includeKnowledgeContext: false,
                    includeMacroContext: false
                ),
                allowedTools: [.calculate, .summarize, .appOpen, .appFocus, .finderReveal, .systemOpenURL, .projectOpen, .projectScaffold, .shellRunSafe, .voiceListen, .voiceSpeak, .voiceStop],
                fallback: .askClarification,
                enableStreaming: true
            )
        case .searchQuery:
            return RoutePlan(
                intent: .searchQuery,
                promptTemplate: .searchAssistant,
                memoryScope: .searchTransient,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: false,
                    includeNotificationContext: false,
                    includeClipboardContext: false,
                    includeKnowledgeContext: true,
                    includeMacroContext: false
                ),
                allowedTools: [.searchLocalDocs],
                fallback: .askClarification,
                enableStreaming: true
            )
        case .documentTransform:
            return RoutePlan(
                intent: .documentTransform,
                promptTemplate: .documentRewrite,
                memoryScope: .documentTask,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: true,
                    includeNotificationContext: false,
                    includeClipboardContext: false,
                    includeKnowledgeContext: false,
                    includeMacroContext: false
                ),
                allowedTools: [],
                fallback: .askClarification,
                enableStreaming: true
            )
        case .ocrExtract:
            return RoutePlan(
                intent: .ocrExtract,
                promptTemplate: .ocrInterpreter,
                memoryScope: .ocrTask,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: false,
                    includeNotificationContext: false,
                    includeClipboardContext: true,
                    includeKnowledgeContext: false,
                    includeMacroContext: false
                ),
                allowedTools: [.ocrCurrentWindow, .summarize],
                fallback: .askClarification,
                enableStreaming: true
            )
        case .mailDraft:
            return RoutePlan(
                intent: .mailDraft,
                promptTemplate: .mailDraft,
                memoryScope: .mailSession,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: false,
                    includeNotificationContext: false,
                    includeClipboardContext: true,
                    includeKnowledgeContext: false,
                    includeMacroContext: false
                ),
                allowedTools: [.summarize],
                fallback: .fallbackToGeneralChat,
                enableStreaming: true
            )
        case .diagnosticsQuery:
            return RoutePlan(
                intent: .diagnosticsQuery,
                promptTemplate: .diagnostics,
                memoryScope: .diagnosticsTask,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: false,
                    includeNotificationContext: true,
                    includeClipboardContext: false,
                    includeKnowledgeContext: false,
                    includeMacroContext: false
                ),
                allowedTools: [.listNotifications],
                fallback: .askClarification,
                enableStreaming: true
            )
        case .macroExecution:
            return RoutePlan(
                intent: .macroExecution,
                promptTemplate: .quickAction,
                memoryScope: .macroTask,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: false,
                    includeNotificationContext: false,
                    includeClipboardContext: false,
                    includeKnowledgeContext: false,
                    includeMacroContext: true
                ),
                allowedTools: [],
                fallback: .fallbackToGeneralChat,
                enableStreaming: true
            )
        case .reflectiveMode:
            return RoutePlan(
                intent: .reflectiveMode,
                promptTemplate: .reflective,
                memoryScope: .reflectiveScratch,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: false,
                    includeNotificationContext: false,
                    includeClipboardContext: false,
                    includeKnowledgeContext: false,
                    includeMacroContext: false
                ),
                allowedTools: [],
                fallback: .askClarification,
                enableStreaming: true
            )
        case .explanationMode:
            return RoutePlan(
                intent: .explanationMode,
                promptTemplate: .explanation,
                memoryScope: .explanationScratch,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: false,
                    includeNotificationContext: signal.selectedSurface == .why,
                    includeClipboardContext: false,
                    includeKnowledgeContext: false,
                    includeMacroContext: false
                ),
                allowedTools: [.summarize],
                fallback: .askClarification,
                enableStreaming: true
            )
        case .quickActionCommand:
            return RoutePlan(
                intent: .quickActionCommand,
                promptTemplate: .quickAction,
                memoryScope: .quickActionTransient,
                output: .chatTimeline,
                contextPolicy: RouteContextPolicy(
                    includeDocumentContext: signal.hasImportedDocument,
                    includeNotificationContext: signal.selectedSurface == .notifications,
                    includeClipboardContext: signal.hasClipboardText,
                    includeKnowledgeContext: signal.hasIndexedFolders || signal.selectedSurface == .fileSearch,
                    includeMacroContext: signal.selectedSurface == .macros
                ),
                allowedTools: [.calculate, .summarize, .searchLocalDocs, .appOpen, .appFocus, .finderReveal, .systemOpenURL, .projectOpen, .projectScaffold, .shellRunSafe, .voiceListen, .voiceSpeak, .voiceStop],
                fallback: .fallbackToGeneralChat,
                enableStreaming: true
            )
        }
    }
}

struct StreamOwnershipController {
    private(set) var activeRequest: StreamRequest?

    mutating func begin(conversationID: UUID, routePlan: RoutePlan) -> StreamRequest {
        let request = StreamRequest(
            requestID: UUID(),
            conversationID: conversationID,
            routePlan: routePlan,
            startedAt: Date()
        )
        activeRequest = request
        return request
    }

    mutating func cancelActive() -> StreamRequest? {
        let active = activeRequest
        activeRequest = nil
        return active
    }

    mutating func complete(requestID: UUID) {
        guard activeRequest?.requestID == requestID else { return }
        activeRequest = nil
    }

    func owns(_ requestID: UUID) -> Bool {
        activeRequest?.requestID == requestID
    }
}
