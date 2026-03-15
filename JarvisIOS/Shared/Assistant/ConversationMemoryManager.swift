import Foundation
import Combine

@MainActor
public final class ConversationMemoryManager: ObservableObject {
    @Published public private(set) var currentSummary: ConversationSummary?
    @Published public private(set) var recentMessages: [JarvisChatMessage] = []
    @Published public private(set) var totalMessageCount: Int = 0
    @Published public private(set) var retrievedMemories: [JarvisMemoryMatch] = []

    private let store: JarvisMemoryStore
    private var policy: MemoryRetentionPolicy
    private var messageHistory: [JarvisChatMessage] = []
    private var currentConversationID: UUID?

    public init(
        store: JarvisMemoryStore = JarvisMemoryStore(),
        policy: MemoryRetentionPolicy = .default
    ) {
        self.store = store
        self.policy = policy
    }

    public func updatePolicy(_ policy: MemoryRetentionPolicy) {
        self.policy = policy
        recomputeRecentMessages()
    }

    public func setConversation(_ conversation: JarvisConversationRecord) {
        currentConversationID = conversation.id
        messageHistory = conversation.messages.filter { !$0.isStreaming }
        totalMessageCount = messageHistory.count
        currentSummary = store.latestSummary(for: conversation.id)
        recomputeRecentMessages()
    }

    public func clear() {
        currentConversationID = nil
        messageHistory.removeAll()
        recentMessages = []
        currentSummary = nil
        retrievedMemories = []
        totalMessageCount = 0
    }

    public func prepareContext(
        conversation: JarvisConversationRecord,
        prompt: String,
        task: JarvisAssistantTask,
        taskBudget: Int
    ) -> MemoryContext {
        if currentConversationID != conversation.id || messageHistory.count != conversation.messages.count {
            setConversation(conversation)
        }

        let effectiveRecentCount = min(policy.maxRecentMessages, max(taskBudget, 3))
        let recent = Array(messageHistory.suffix(effectiveRecentCount))
        let compressedCount = max(0, messageHistory.count - recent.count)
        let summary = summaryForConversationIfNeeded(conversation)
        let memories = retrieveRelevantMemories(
            prompt: prompt,
            conversationID: conversation.id,
            task: task,
            limit: policy.maxRetrievedMemories
        )

        retrievedMemories = memories

        return MemoryContext(
            recentMessages: recent,
            summary: summary,
            retrievedMemories: memories,
            totalMessages: totalMessageCount,
            compressedMessageCount: compressedCount
        )
    }

    public func recordInteraction(
        conversationID: UUID,
        userMessage: JarvisChatMessage,
        assistantMessage: JarvisChatMessage,
        task: JarvisAssistantTask,
        classification: JarvisTaskClassification
    ) {
        currentConversationID = conversationID
        messageHistory.append(userMessage)
        messageHistory.append(assistantMessage)
        totalMessageCount = messageHistory.count
        recomputeRecentMessages()

        for memory in memoryCandidates(
            conversationID: conversationID,
            userText: userMessage.text,
            assistantText: assistantMessage.text,
            task: task,
            classification: classification
        ) {
            store.upsertMemory(resolveExistingMemory(for: memory), maxCount: policy.maxStoredMemories)
        }

        if shouldRefreshSummary(for: messageHistory) {
            let summary = buildSummary(for: conversationID, messages: messageHistory)
            store.upsertSummary(summary)
            currentSummary = summary

            let summaryMemory = JarvisMemoryRecord(
                kind: .conversationSummary,
                title: "Conversation summary",
                content: summary.summaryText,
                conversationID: conversationID,
                confidence: 0.72,
                importance: 0.7,
                tags: summary.keyTopics
            )
            store.upsertMemory(resolveExistingMemory(for: summaryMemory), maxCount: policy.maxStoredMemories)
        }
    }

    public func continuityLabel(from context: MemoryContext) -> String? {
        if !context.retrievedMemories.isEmpty {
            let labels = context.memoryLabels
            return labels.isEmpty ? "Using memory" : "Using memory: \(labels.joined(separator: ", "))"
        }
        if let summary = context.summary, !summary.summaryText.isEmpty {
            return "Using conversation summary"
        }
        return nil
    }

    private func retrieveRelevantMemories(
        prompt: String,
        conversationID: UUID,
        task: JarvisAssistantTask,
        limit: Int
    ) -> [JarvisMemoryMatch] {
        let augmentedQuery = "\(prompt) \(task.displayName)"
        return store.searchMemories(query: augmentedQuery, conversationID: conversationID, limit: limit)
    }

    private func summaryForConversationIfNeeded(_ conversation: JarvisConversationRecord) -> ConversationSummary? {
        if let currentSummary, currentSummary.conversationID == conversation.id {
            return currentSummary
        }
        let summary = store.latestSummary(for: conversation.id)
        currentSummary = summary
        return summary
    }

    private func recomputeRecentMessages() {
        recentMessages = Array(messageHistory.suffix(policy.maxRecentMessages))
    }

    private func shouldRefreshSummary(for messages: [JarvisChatMessage]) -> Bool {
        guard policy.enableSemanticCompression else { return false }
        guard messages.count >= policy.maxSummaryMessages else { return false }
        guard let oldestCandidate = messages.dropLast(policy.maxRecentMessages).first else { return false }
        return Date().timeIntervalSince(oldestCandidate.createdAt) >= policy.minMessageAgeForCompression
    }

    private func buildSummary(for conversationID: UUID, messages: [JarvisChatMessage]) -> ConversationSummary {
        let archivedMessages = Array(messages.dropLast(min(policy.maxRecentMessages, messages.count)))
        let userMessages = archivedMessages.filter { $0.role == .user }.map(\.text)
        let assistantMessages = archivedMessages.filter { $0.role == .assistant }.map(\.text)

        let topics = extractTopics(from: archivedMessages)
        let userIntent = inferUserIntent(from: userMessages)
        let assistantActions = inferAssistantActions(from: assistantMessages)

        let summaryLead = topics.isEmpty
            ? "Conversation covered prior requests and assistant responses."
            : "Conversation covered \(topics.joined(separator: ", "))."
        let summaryText = [
            summaryLead,
            userIntent.isEmpty ? nil : "User intent: \(userIntent).",
            assistantActions.isEmpty ? nil : "Jarvis actions: \(assistantActions.joined(separator: ", "))."
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return ConversationSummary(
            conversationID: conversationID,
            updatedAt: Date(),
            messageCount: archivedMessages.count,
            summaryText: summaryText.isEmpty ? "Previous discussion included assistant guidance and follow-up context." : summaryText,
            keyTopics: topics,
            userIntent: userIntent,
            assistantActions: assistantActions
        )
    }

    private func memoryCandidates(
        conversationID: UUID,
        userText: String,
        assistantText: String,
        task: JarvisAssistantTask,
        classification: JarvisTaskClassification
    ) -> [JarvisMemoryRecord] {
        let cleanUser = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else { return [] }

        var records: [JarvisMemoryRecord] = []
        let lowercased = cleanUser.lowercased()
        let tags = Array(extractTopics(from: [JarvisChatMessage(role: .user, text: cleanUser)]).prefix(4))

        func append(kind: JarvisMemoryKind, title: String, content: String, confidence: Double, importance: Double, pinned: Bool = false) {
            records.append(
                JarvisMemoryRecord(
                    kind: kind,
                    title: title,
                    content: content,
                    conversationID: conversationID,
                    confidence: confidence,
                    importance: importance,
                    isPinned: pinned,
                    tags: tags,
                    entityHints: tags
                )
            )
        }

        if lowercased.contains("i prefer") || lowercased.contains("please use") || lowercased.contains("always ") || lowercased.contains("never ") {
            append(
                kind: .preference,
                title: "User preference",
                content: cleanUser,
                confidence: 0.88,
                importance: 0.84,
                pinned: true
            )
        }

        if lowercased.contains("my name is") || lowercased.contains("i work") || lowercased.contains("i am ") {
            append(
                kind: .personalFact,
                title: "Personal fact",
                content: cleanUser,
                confidence: 0.8,
                importance: 0.65
            )
        }

        if lowercased.contains("project") || lowercased.contains("we're building") || lowercased.contains("working on") {
            append(
                kind: .project,
                title: "Project detail",
                content: cleanUser,
                confidence: 0.78,
                importance: 0.76
            )
        }

        if lowercased.contains("goal") || lowercased.contains("need to") || lowercased.contains("next step") || classification.category == .planning {
            append(
                kind: .task,
                title: "Active task",
                content: cleanUser,
                confidence: 0.74,
                importance: 0.7
            )
        }

        if task == .quickCapture || lowercased.count > 160 {
            append(
                kind: .recentContext,
                title: "Recent context",
                content: String(cleanUser.prefix(240)),
                confidence: 0.62,
                importance: 0.52
            )
        }

        if records.isEmpty, !assistantText.isEmpty, classification.category == .planning {
            append(
                kind: .task,
                title: "Planned work",
                content: String(assistantText.prefix(220)),
                confidence: 0.58,
                importance: 0.55
            )
        }

        return records
    }

    private func resolveExistingMemory(for memory: JarvisMemoryRecord) -> JarvisMemoryRecord {
        let existing = store.loadMemories().first { record in
            record.kind == memory.kind &&
            record.title.caseInsensitiveCompare(memory.title) == .orderedSame &&
            (
                record.conversationID == memory.conversationID ||
                record.normalizedContent.contains(memory.normalizedContent) ||
                memory.normalizedContent.contains(record.normalizedContent)
            )
        }

        guard let existing else { return memory }

        return JarvisMemoryRecord(
            id: existing.id,
            kind: memory.kind,
            title: memory.title,
            content: memory.content,
            conversationID: memory.conversationID,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            lastAccessedAt: existing.lastAccessedAt,
            confidence: max(existing.confidence, memory.confidence),
            importance: max(existing.importance, memory.importance),
            isPinned: existing.isPinned || memory.isPinned,
            tags: Array(Set(existing.tags + memory.tags)).sorted(),
            entityHints: Array(Set(existing.entityHints + memory.entityHints)).sorted(),
            embeddingPlaceholder: existing.embeddingPlaceholder
        )
    }

    private func extractTopics(from messages: [JarvisChatMessage]) -> [String] {
        let keywordMap: [(String, [String])] = [
            ("code", ["code", "swift", "xcode", "debug", "compile"]),
            ("writing", ["write", "draft", "email", "reply"]),
            ("planning", ["plan", "roadmap", "checklist", "next step"]),
            ("research", ["research", "search", "find", "notes"]),
            ("summary", ["summarize", "summary", "key points"]),
            ("project", ["project", "build", "launch", "ship"])
        ]

        let haystack = messages.map(\.text).joined(separator: " ").lowercased()
        return keywordMap.compactMap { topic, keywords in
            keywords.contains(where: haystack.contains) ? topic : nil
        }
    }

    private func inferUserIntent(from userMessages: [String]) -> String {
        let joined = userMessages.joined(separator: " ").lowercased()
        if joined.contains("summar") {
            return "summarization"
        }
        if joined.contains("reply") || joined.contains("draft") {
            return "drafting"
        }
        if joined.contains("plan") || joined.contains("checklist") {
            return "planning"
        }
        if joined.contains("?") || joined.contains("what") || joined.contains("how") {
            return "question answering"
        }
        return joined.isEmpty ? "" : "general assistance"
    }

    private func inferAssistantActions(from assistantMessages: [String]) -> [String] {
        var actions: [String] = []
        for message in assistantMessages {
            let lowercased = message.lowercased()
            if lowercased.contains("step") || lowercased.contains("1.") {
                actions.append("provided steps")
            }
            if lowercased.contains("draft") || lowercased.contains("subject") {
                actions.append("drafted content")
            }
            if lowercased.contains("summary") || lowercased.contains("key points") {
                actions.append("summarized context")
            }
        }
        return Array(Set(actions)).sorted()
    }
}
