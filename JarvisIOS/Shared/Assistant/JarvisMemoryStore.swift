import Foundation

public final class JarvisMemoryStore {
    private struct StorePayload: Codable {
        var memories: [JarvisMemoryRecord]
        var summaries: [ConversationSummary]
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "jarvis.assistant.memory.store", qos: .utility)

    public init(filename: String = "JarvisAssistantMemory.json") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = appSupport.appendingPathComponent("JarvisPhone", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.fileURL = directory.appendingPathComponent(filename)
    }

    public func loadMemories() -> [JarvisMemoryRecord] {
        queue.sync {
            loadPayload().memories.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    public func upsertMemory(_ memory: JarvisMemoryRecord, maxCount: Int) {
        queue.sync {
            var payload = loadPayload()
            payload.memories.removeAll { $0.id == memory.id }
            payload.memories.append(memory)
            payload.memories = payload.memories
                .sorted { lhs, rhs in
                    let lhsScore = (lhs.isPinned ? 1.0 : 0.0) + lhs.importance + lhs.confidence
                    let rhsScore = (rhs.isPinned ? 1.0 : 0.0) + rhs.importance + rhs.confidence
                    if lhsScore == rhsScore {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhsScore > rhsScore
                }
                .prefix(maxCount)
                .map { $0 }
            persist(payload)
        }
    }

    public func latestSummary(for conversationID: UUID) -> ConversationSummary? {
        queue.sync {
            loadPayload().summaries
                .filter { $0.conversationID == conversationID }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
        }
    }

    public func upsertSummary(_ summary: ConversationSummary) {
        queue.sync {
            var payload = loadPayload()
            payload.summaries.removeAll { $0.id == summary.id || $0.conversationID == summary.conversationID }
            payload.summaries.append(summary)
            persist(payload)
        }
    }

    public func searchMemories(
        query: String,
        conversationID: UUID?,
        limit: Int,
        classification: JarvisTaskClassification? = nil,
        skill: JarvisSkill? = nil
    ) -> [JarvisMemoryMatch] {
        let queryTerms = JarvisMemoryText.terms(for: query)
        guard !queryTerms.isEmpty else { return [] }

        let matches: [JarvisMemoryMatch] = queue.sync {
            let payload = loadPayload()
            return rankMatches(
                from: payload.memories,
                queryTerms: queryTerms,
                conversationID: conversationID,
                limit: limit,
                classification: classification,
                skill: skill
            )
        }

        return matches
    }

    public func clearAll() {
        queue.sync {
            persist(StorePayload(memories: [], summaries: []))
        }
    }

    public func clearMemories() {
        queue.sync {
            var payload = loadPayload()
            payload.memories = []
            persist(payload)
        }
    }

    public func clearSummaries() {
        queue.sync {
            var payload = loadPayload()
            payload.summaries = []
            persist(payload)
        }
    }

    private func loadPayload() -> StorePayload {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(StorePayload.self, from: data) else {
            return StorePayload(memories: [], summaries: [])
        }
        return payload
    }

    private func persist(_ payload: StorePayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func rankMatches(
        from memories: [JarvisMemoryRecord],
        queryTerms: [String],
        conversationID: UUID?,
        limit: Int,
        classification: JarvisTaskClassification?,
        skill: JarvisSkill?
    ) -> [JarvisMemoryMatch] {
        var matches: [JarvisMemoryMatch] = []
        matches.reserveCapacity(memories.count)

        for record in memories {
            let titleTerms = JarvisMemoryText.terms(for: record.title)
            let contentTerms = JarvisMemoryText.terms(for: record.content)
            let tagTerms = record.tags.map { $0.lowercased() }
            let entityTerms = record.entityHints.map { $0.lowercased() }

            let titleMatches = queryTerms.filter { titleTerms.contains($0) }
            let contentMatches = queryTerms.filter { contentTerms.contains($0) }
            let tagMatches = queryTerms.filter { tagTerms.contains($0) || entityTerms.contains($0) }

            guard !titleMatches.isEmpty || !contentMatches.isEmpty || !tagMatches.isEmpty else {
                continue
            }

            let recencyDays = max(record.updatedAt.distance(to: Date()) / 86_400, 0)
            let recencyBoost = max(0.1, 1.0 - min(recencyDays / 30.0, 0.9))
            let conversationBoost = record.conversationID == conversationID ? 0.7 : 0.0
            let pinnedBoost = record.isPinned ? 0.8 : 0.0
            let overlapScore = Double(titleMatches.count * 3 + contentMatches.count * 2 + tagMatches.count * 4)
            let taskBoost = taskAwareBoost(for: record, classification: classification, skill: skill)
            let score = overlapScore
                + record.kind.retrievalWeight
                + conversationBoost
                + pinnedBoost
                + record.importance
                + record.confidence
                + recencyBoost
                + taskBoost

            var reasons: [String] = []
            if !titleMatches.isEmpty {
                reasons.append("title match")
            }
            if !tagMatches.isEmpty {
                reasons.append("tag match")
            }
            if record.conversationID == conversationID {
                reasons.append("same conversation")
            }
            if record.isPinned {
                reasons.append("pinned")
            }
            if taskBoost > 0 {
                reasons.append("task-aware")
            }

            matches.append(JarvisMemoryMatch(record: record, score: score, reasons: reasons))
        }

        let sorted = matches.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.record.updatedAt > rhs.record.updatedAt
            }
            return lhs.score > rhs.score
        }

        return Array(sorted.prefix(limit))
    }

    private func taskAwareBoost(
        for record: JarvisMemoryRecord,
        classification: JarvisTaskClassification?,
        skill: JarvisSkill?
    ) -> Double {
        guard let classification else { return 0 }

        var boost = 0.0

        if let skill, skill.preferredMemoryKinds.contains(record.kind) {
            boost += 1.35
        }

        switch classification.category {
        case .coding:
            switch record.kind {
            case .project:
                boost += 1.4
            case .task:
                boost += 1.2
            case .recentContext:
                boost += 1.0
            case .conversationSummary:
                boost += 0.8
            case .personalFact, .preference, .knowledge:
                boost += 0.15
            }
        case .draftingEmail, .draftingMessage, .contextAwareReply, .rewritingText:
            switch record.kind {
            case .preference:
                boost += 1.5
            case .recentContext:
                boost += 1.2
            case .conversationSummary:
                boost += 0.9
            case .project, .task:
                boost += 0.4
            case .personalFact, .knowledge:
                boost += 0.2
            }
        case .planning:
            switch record.kind {
            case .task:
                boost += 1.5
            case .project:
                boost += 1.3
            case .conversationSummary:
                boost += 1.0
            case .recentContext:
                boost += 0.9
            case .preference:
                boost += 0.3
            case .personalFact, .knowledge:
                boost += 0.15
            }
        case .summarization:
            switch record.kind {
            case .conversationSummary:
                boost += 1.4
            case .knowledge:
                boost += 0.9
            case .recentContext:
                boost += 0.6
            case .project, .task:
                boost += 0.4
            case .preference, .personalFact:
                boost += 0.1
            }
        case .questionAnswering, .explainingSomething:
            switch record.kind {
            case .knowledge:
                boost += 1.5
            case .conversationSummary:
                boost += 1.0
            case .project:
                boost += 0.8
            case .preference:
                boost += 0.6
            case .task, .recentContext:
                boost += 0.4
            case .personalFact:
                boost += 0.2
            }
        case .generalChat:
            switch record.kind {
            case .project:
                boost += 0.8
            case .preference:
                boost += 0.8
            case .conversationSummary:
                boost += 0.7
            case .recentContext:
                boost += 0.6
            case .task:
                boost += 0.5
            case .personalFact, .knowledge:
                boost += 0.3
            }
        }

        return boost
    }
}
