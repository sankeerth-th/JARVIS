import Foundation

public struct JarvisSemanticMemoryProvider: JarvisAssistantMemoryProviding {
    private let store: JarvisMemoryStore
    private let isLongTermMemoryEnabled: () -> Bool

    public init(
        store: JarvisMemoryStore,
        isLongTermMemoryEnabled: @escaping () -> Bool
    ) {
        self.store = store
        self.isLongTermMemoryEnabled = isLongTermMemoryEnabled
    }

    public func augmentation(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification
    ) async -> JarvisAssistantMemoryAugmentation {
        guard isLongTermMemoryEnabled() else { return .none }

        let resolvedSkill = JarvisSkillPolicyResolver.resolve(for: request, classification: classification)

        let matches = store.searchMemories(
            query: request.prompt,
            conversationID: request.conversationID,
            limit: resolvedSkill.policy.maxMemoryItems,
            classification: classification,
            skill: resolvedSkill.skill
        )

        guard !matches.isEmpty else { return .none }

        var usedCharacters = 0
        var lines: [String] = []
        for match in matches {
            let compact = compactLine(for: match, skill: resolvedSkill.skill)
            let budgeted = String(compact.prefix(140))
            let cost = budgeted.count
            if !lines.isEmpty, usedCharacters + cost > resolvedSkill.policy.maxMemoryCharacters {
                break
            }
            usedCharacters += cost
            lines.append(budgeted)
        }

        guard !lines.isEmpty else { return .none }

        let summary = "Relevant Context:\n" + lines.joined(separator: "\n")
        return JarvisAssistantMemoryAugmentation(
            supplementalContext: [
                JarvisPromptContextBlock(
                    title: "Relevant Context",
                    content: lines.joined(separator: "\n")
                )
            ],
            summary: summary
        )
    }

    private func compactLine(for match: JarvisMemoryMatch, skill: JarvisSkill) -> String {
        let prefix: String
        switch match.record.kind {
        case .preference:
            prefix = "Preference"
        case .project:
            prefix = skill.id.hasPrefix("code_") ? "Project" : "Project context"
        case .task:
            prefix = "Active task"
        case .conversationSummary:
            prefix = "Summary"
        case .knowledge:
            prefix = "Knowledge"
        case .recentContext:
            prefix = "Recent context"
        case .personalFact:
            prefix = "Profile"
        }

        return "- \(prefix): \(match.record.content)"
    }
}
