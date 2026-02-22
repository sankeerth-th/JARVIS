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
            contextChunks.append("Document Title: \(doc.title)\n\(doc.content.prefix(4000))")
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
            stream: true
        )
        return ollama.streamGenerate(request: request)
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
}

struct ToolInvocationParser {
    func extractInvocations(from text: String) -> (cleaned: String, invocations: [ToolInvocation]) {
        var remaining = text
        var collected: [ToolInvocation] = []
        while let startRange = remaining.range(of: "<<tool"), let endRange = remaining.range(of: ">>", range: startRange.lowerBound..<remaining.endIndex) {
            let jsonRange = startRange.upperBound..<endRange.lowerBound
            let jsonString = remaining[jsonRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonString.data(using: .utf8), let invocation = try? JSONDecoder().decode(ToolInvocation.self, from: data) {
                collected.append(invocation)
            }
            remaining.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }
        return (remaining, collected)
    }
}
