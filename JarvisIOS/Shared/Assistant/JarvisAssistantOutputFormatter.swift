import Foundation

enum JarvisAssistantOutputFormatter {
    static func format(
        text: String,
        classification: JarvisTaskClassification,
        memoryContext: MemoryContext
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
                        kind: .checklist,
                        title: classification.category == .coding ? "Implementation Plan" : "Action Plan",
                        body: leadingParagraph(from: trimmed),
                        items: checklistItems,
                        callout: "Structured for execution."
                    )
                )
            } else {
                cards.append(
                    JarvisAssistantCard(
                        kind: .action,
                        title: "Recommended Action",
                        body: trimmed,
                        callout: "Turn this into the next concrete step."
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
            }
        case .generalChat, .rewritingText:
            break
        }

        return cards.isEmpty ? nil : JarvisAssistantStructuredOutput(cards: cards)
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
}
