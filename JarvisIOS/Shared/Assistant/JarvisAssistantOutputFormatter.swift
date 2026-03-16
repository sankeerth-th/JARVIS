import Foundation

enum JarvisAssistantOutputFormatter {
    static func format(
        text: String,
        classification: JarvisTaskClassification,
        memoryContext: MemoryContext,
        skill: JarvisSkill? = nil
    ) -> JarvisAssistantStructuredOutput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var cards: [JarvisAssistantCard] = []
        let checklistItems = extractListItems(from: trimmed)

        switch classification.category {
        case .draftingEmail, .draftingMessage, .contextAwareReply:
            cards.append(
                JarvisAssistantCard(
                    kind: .draft,
                    title: classification.task == .draftEmail ? "Draft Email" : "Ready-to-send Draft",
                    body: trimmed,
                    callout: memoryContext.isMemoryInformed ? "Adjusted using saved context." : nil
                )
            )
        case .planning, .coding:
            if !checklistItems.isEmpty {
                cards.append(
                    JarvisAssistantCard(
                        kind: classification.category == .coding ? .multiStepPlan : .checklist,
                        title: classification.category == .coding ? "Implementation Plan" : "Action Plan",
                        body: leadingParagraph(from: trimmed),
                        items: checklistItems,
                        callout: "Structured for execution."
                    )
                )
            } else {
                cards.append(
                    JarvisAssistantCard(
                        kind: classification.category == .coding ? .codeAnswer : .action,
                        title: classification.category == .coding ? "Code Answer" : "Recommended Action",
                        body: trimmed,
                        callout: "Turn this into the next concrete step."
                    )
                )
            }
            if classification.category == .coding, let codeBlock = extractCodeBlock(from: trimmed) {
                if cards.first(where: { $0.kind == .codeAnswer }) == nil {
                    cards.insert(
                        JarvisAssistantCard(
                            kind: .codeAnswer,
                            title: "Code Answer",
                            body: leadingParagraph(from: trimmed),
                            callout: memoryContext.isMemoryInformed ? "Grounded in your recent project context." : nil
                        ),
                        at: 0
                    )
                }
                cards.append(
                    JarvisAssistantCard(
                        kind: .codeBlock,
                        title: "Code",
                        body: codeBlock
                    )
                )
            }
        case .summarization:
            cards.append(
                JarvisAssistantCard(
                    kind: .summary,
                    title: "Summary",
                    body: leadingParagraph(from: trimmed),
                    items: checklistItems
                )
            )
            if containsProsAndCons(trimmed) {
                cards.append(
                    JarvisAssistantCard(
                        kind: .prosCons,
                        title: "Pros / Cons",
                        body: trimmed
                    )
                )
            }
        case .questionAnswering, .explainingSomething:
            if looksLikeClarification(trimmed) {
                cards.append(
                    JarvisAssistantCard(
                        kind: .clarification,
                        title: "Need Clarification",
                        body: trimmed,
                        callout: "A tighter follow-up will improve the answer."
                    )
                )
            } else if classification.shouldInjectKnowledge || classification.task == .knowledgeAnswer {
                cards.append(
                    JarvisAssistantCard(
                        kind: .knowledgeAnswer,
                        title: "Knowledge Answer",
                        body: leadingParagraph(from: trimmed),
                        items: checklistItems,
                        callout: memoryContext.isMemoryInformed ? "Includes relevant saved context." : nil
                    )
                )
            }
        case .generalChat, .rewritingText:
            if looksLikeBrainstorm(trimmed), !checklistItems.isEmpty {
                cards.append(
                    JarvisAssistantCard(
                        kind: .brainstorm,
                        title: "Ideas",
                        items: checklistItems
                    )
                )
            }
            break
        }

        cards.append(contentsOf: fallbackCards(for: skill, text: trimmed, checklistItems: checklistItems, memoryContext: memoryContext, existing: cards))

        return cards.isEmpty ? nil : JarvisAssistantStructuredOutput(cards: cards)
    }

    private static func fallbackCards(
        for skill: JarvisSkill?,
        text: String,
        checklistItems: [String],
        memoryContext: MemoryContext,
        existing: [JarvisAssistantCard]
    ) -> [JarvisAssistantCard] {
        guard let skill else { return [] }
        guard existing.isEmpty else { return [] }

        switch skill.preferredOutputKind {
        case .codeAnswer:
            return [
                JarvisAssistantCard(
                    kind: .codeAnswer,
                    title: "Code Answer",
                    body: leadingParagraph(from: text),
                    callout: memoryContext.isMemoryInformed ? "Prepared with project context." : nil
                )
            ]
        case .draft:
            return [
                JarvisAssistantCard(
                    kind: .draft,
                    title: skill.name,
                    body: text,
                    callout: memoryContext.isMemoryInformed ? "Adjusted using saved preferences." : nil
                )
            ]
        case .checklist:
            return [
                JarvisAssistantCard(
                    kind: .checklist,
                    title: "Plan",
                    body: leadingParagraph(from: text),
                    items: checklistItems,
                    callout: "Structured for action."
                )
            ]
        case .knowledgeAnswer:
            return [
                JarvisAssistantCard(
                    kind: .knowledgeAnswer,
                    title: "Answer",
                    body: leadingParagraph(from: text),
                    items: checklistItems
                )
            ]
        case .clarification:
            return [
                JarvisAssistantCard(
                    kind: .clarification,
                    title: "Need Clarification",
                    body: text
                )
            ]
        case .brainstorm:
            return [
                JarvisAssistantCard(
                    kind: .brainstorm,
                    title: "Ideas",
                    body: checklistItems.isEmpty ? leadingParagraph(from: text) : "",
                    items: checklistItems
                )
            ]
        case .summary:
            return [
                JarvisAssistantCard(
                    kind: .summary,
                    title: "Summary",
                    body: leadingParagraph(from: text),
                    items: checklistItems
                )
            ]
        case .text:
            return []
        }
    }

    private static func extractListItems(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { line in
                let cleaned = line.replacingOccurrences(of: "•", with: "-")
                if cleaned.hasPrefix("- ") {
                    return String(cleaned.dropFirst(2))
                }
                if cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                    return cleaned.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
                }
                if cleaned.lowercased().hasPrefix("step ") {
                    return cleaned
                }
                return nil
            }
    }

    private static func leadingParagraph(from text: String) -> String {
        text.components(separatedBy: "\n\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    private static func looksLikeClarification(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("could you clarify") ||
            lowercased.contains("can you clarify") ||
            lowercased.contains("which one") ||
            lowercased.contains("i need more detail")
    }

    private static func extractCodeBlock(from text: String) -> String? {
        guard let start = text.range(of: "```"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsProsAndCons(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("pros") && lowercased.contains("cons")
    }

    private static func looksLikeBrainstorm(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("ideas") || lowercased.contains("options") || lowercased.contains("brainstorm")
    }
}
