import Foundation

public final class JarvisConversationStore {
    private struct StorePayload: Codable {
        var conversations: [JarvisConversationRecord]
        var knowledgeItems: [JarvisKnowledgeItem]
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "jarvis.phone.conversation.store", qos: .utility)
    private let securityEnvelope: JarvisIOSSecurityEnvelope

    public init(filename: String = "JarvisPhoneStore.json", securityEnvelope: JarvisIOSSecurityEnvelope = .shared) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = appSupport.appendingPathComponent("JarvisPhone", isDirectory: true)
        JarvisIOSStorageProtection.prepareSensitiveDirectory(directory)
        self.fileURL = directory.appendingPathComponent(filename)
        self.securityEnvelope = securityEnvelope
    }

    public func loadConversations() -> [JarvisConversationRecord] {
        queue.sync {
            loadPayload().conversations
                .map(Self.sanitizedConversation)
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func saveConversation(_ conversation: JarvisConversationRecord) {
        queue.sync {
            var payload = loadPayload()
            let sanitizedConversation = Self.sanitizedConversation(conversation)
            payload.conversations.removeAll { $0.id == sanitizedConversation.id }
            payload.conversations.append(sanitizedConversation)
            persist(payload)
        }
    }

    public func deleteConversations() {
        queue.sync {
            var payload = loadPayload()
            payload.conversations = []
            persist(payload)
        }
    }

    public func loadKnowledgeItems() -> [JarvisKnowledgeItem] {
        queue.sync {
            loadPayload().knowledgeItems.sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func addKnowledgeItem(_ item: JarvisKnowledgeItem) {
        queue.sync {
            var payload = loadPayload()
            payload.knowledgeItems.removeAll { $0.id == item.id }
            payload.knowledgeItems.insert(item, at: 0)
            payload.knowledgeItems = Array(payload.knowledgeItems.prefix(150))
            persist(payload)
        }
    }

    public func clearKnowledgeItems() {
        queue.sync {
            var payload = loadPayload()
            payload.knowledgeItems = []
            persist(payload)
        }
    }

    public func searchKnowledge(query: String, limit: Int = 20) -> [JarvisKnowledgeResult] {
        let terms = Self.queryTerms(for: query)
        guard !terms.isEmpty else { return [] }

        return loadKnowledgeItems()
            .compactMap { item in
                let haystack = "\(item.title.lowercased()) \(item.text.lowercased()) \(item.source.lowercased())"
                let hitCount = terms.reduce(0) { partial, term in
                    partial + (haystack.contains(term) ? 1 : 0)
                }
                guard hitCount > 0 else { return nil }
                let score = Double(hitCount) / Double(terms.count)
                return JarvisKnowledgeResult(item: item, score: score, snippet: Self.snippet(for: item.text, query: terms))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.item.createdAt > rhs.item.createdAt
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private func loadPayload() -> StorePayload {
        guard let data = try? Data(contentsOf: fileURL) else {
            return StorePayload(conversations: [], knowledgeItems: [])
        }
        if let opened = try? securityEnvelope.open(data, purpose: fileURL.lastPathComponent),
           let decoded = try? JSONDecoder().decode(StorePayload.self, from: opened) {
            return decoded
        }
        if let decoded = try? JSONDecoder().decode(StorePayload.self, from: data) {
            return decoded
        }
        return StorePayload(conversations: [], knowledgeItems: [])
    }

    private func persist(_ payload: StorePayload) {
        guard let encoded = try? JSONEncoder().encode(payload),
              let sealed = try? securityEnvelope.seal(encoded, purpose: fileURL.lastPathComponent) else { return }
        try? sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
        JarvisIOSStorageProtection.protectSensitiveFile(at: fileURL)
    }

    private static func queryTerms(for query: String) -> [String] {
        query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 }
    }

    private static func snippet(for text: String, query: [String]) -> String {
        let lowered = text.lowercased()
        guard let firstHit = query.compactMap({ lowered.range(of: $0)?.lowerBound }).min() else {
            return String(text.prefix(160))
        }
        let start = text.distance(from: text.startIndex, to: firstHit)
        let location = max(0, start - 40)
        let startIndex = text.index(text.startIndex, offsetBy: min(location, max(0, text.count - 1)))
        let preview = String(text[startIndex...])
        return String(preview.prefix(180))
    }

    private static func sanitizedConversation(_ conversation: JarvisConversationRecord) -> JarvisConversationRecord {
        var copy = conversation
        copy.messages.removeAll { message in
            message.role == .assistant &&
            message.isStreaming &&
            message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return copy
    }
}
