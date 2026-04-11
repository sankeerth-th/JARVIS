import Foundation

enum JarvisAssistantOutputFormatter {
    static func format(
        text: String,
        classification: JarvisTaskClassification,
        memoryContext: MemoryContext,
        skill: JarvisSkill? = nil,
        capabilitySurfaces: [JarvisAssistantCapabilitySurface] = []
    ) -> JarvisAssistantStructuredOutput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldFormatText = isSubstantiveText(trimmed) && !isGreetingOnly(trimmed)

        var cards: [JarvisAssistantCard] = []
        if shouldFormatText {
            let checklistItems = extractListItems(from: trimmed)
            let codeBlock = extractCodeBlock(from: trimmed)
            let preferredKinds = preferredCardKinds(classification: classification, skill: skill)

            for kind in preferredKinds {
                switch kind {
                case .draft:
                    guard qualifiesAsDraft(trimmed) else { continue }
                    cards.append(
                        JarvisAssistantCard(
                            kind: .draft,
                            title: classification.task == .draftEmail || skill?.id == "draft_email" ? "Draft Email" : "Draft",
                            body: trimmed,
                            callout: memoryContext.isMemoryInformed ? "Adjusted using saved context." : nil
                        )
                    )
                case .checklist:
                    guard qualifiesAsPlan(trimmed, checklistItems: checklistItems) else { continue }
                    cards.append(
                        JarvisAssistantCard(
                            kind: .checklist,
                            title: "Action Plan",
                            body: leadingParagraph(from: trimmed),
                            items: checklistItems,
                            callout: "Structured for execution."
                        )
                    )
                case .codeAnswer:
                    guard qualifiesAsCode(trimmed, codeBlock: codeBlock) else { continue }
                    cards.append(
                        JarvisAssistantCard(
                            kind: .codeAnswer,
                            title: "Code Answer",
                            body: codeSummary(from: trimmed, codeBlock: codeBlock),
                            callout: memoryContext.isMemoryInformed ? "Grounded in your recent project context." : nil
                        )
                    )
                    if let codeBlock, !codeBlock.isEmpty {
                        cards.append(
                            JarvisAssistantCard(
                                kind: .codeBlock,
                                title: "Code",
                                body: codeBlock
                            )
                        )
                    }
                case .summary:
                    guard qualifiesAsSummary(trimmed, checklistItems: checklistItems) else { continue }
                    cards.append(
                        JarvisAssistantCard(
                            kind: .summary,
                            title: "Summary",
                            body: leadingParagraph(from: trimmed),
                            items: checklistItems
                        )
                    )
                    if qualifiesAsProsAndCons(trimmed) {
                        cards.append(
                            JarvisAssistantCard(
                                kind: .prosCons,
                                title: "Pros / Cons",
                                body: trimmed
                            )
                        )
                    }
                case .knowledgeAnswer:
                    guard qualifiesAsKnowledgeAnswer(trimmed, checklistItems: checklistItems) else { continue }
                    cards.append(
                        JarvisAssistantCard(
                            kind: .knowledgeAnswer,
                            title: "Knowledge Answer",
                            body: leadingParagraph(from: trimmed),
                            items: checklistItems,
                            callout: memoryContext.isMemoryInformed ? "Includes relevant saved context." : nil
                        )
                    )
                case .clarification:
                    guard qualifiesAsClarification(trimmed) else { continue }
                    cards.append(
                        JarvisAssistantCard(
                            kind: .clarification,
                            title: "Need Clarification",
                            body: trimmed,
                            callout: "A tighter follow-up will improve the answer."
                        )
                    )
                case .brainstorm:
                    guard qualifiesAsBrainstorm(trimmed, checklistItems: checklistItems) else { continue }
                    cards.append(
                        JarvisAssistantCard(
                            kind: .brainstorm,
                            title: "Ideas",
                            body: checklistItems.isEmpty ? leadingParagraph(from: trimmed) : "",
                            items: checklistItems
                        )
                    )
                case .text:
                    continue
                }
            }
        }

        let output = JarvisAssistantStructuredOutput(cards: cards, capabilitySurfaces: capabilitySurfaces)
        return output.isEmpty ? nil : output
    }

    private static func preferredCardKinds(
        classification: JarvisTaskClassification,
        skill: JarvisSkill?
    ) -> [JarvisSkillOutputKind] {
        var kinds: [JarvisSkillOutputKind] = []

        if qualifiesTaskForClarification(category: classification.category) {
            kinds.append(.clarification)
        }

        switch classification.category {
        case .draftingEmail, .draftingMessage, .contextAwareReply, .rewritingText:
            kinds.append(.draft)
        case .planning:
            kinds.append(.checklist)
        case .coding:
            kinds.append(.codeAnswer)
        case .summarization:
            kinds.append(.summary)
        case .questionAnswering, .explainingSomething:
            if classification.shouldInjectKnowledge || classification.task == .knowledgeAnswer {
                kinds.append(.knowledgeAnswer)
            }
        case .generalChat:
            break
        }

        if let skill {
            kinds.append(skill.preferredOutputKind)
        }

        if classification.category == .generalChat {
            kinds.append(.brainstorm)
        }

        return unique(kinds)
    }

    private static func qualifiesTaskForClarification(category: JarvisTaskCategory) -> Bool {
        switch category {
        case .questionAnswering, .explainingSomething, .draftingEmail, .draftingMessage, .contextAwareReply, .rewritingText:
            return true
        case .generalChat, .summarization, .planning, .coding:
            return false
        }
    }

    private static func isSubstantiveText(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count >= 8 else { return false }
        let alphanumericCount = compact.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        guard alphanumericCount >= 4 else { return false }
        let wordCount = words(in: compact).count
        return wordCount >= 2 || compact.count >= 20
    }

    private static func isGreetingOnly(_ text: String) -> Bool {
        let normalized = words(in: text).joined(separator: " ")
        let greetingSet: Set<String> = [
            "hi", "hello", "hey", "thanks", "thank you", "okay", "ok", "sure", "got it", "sounds good", "good morning", "good afternoon"
        ]
        return greetingSet.contains(normalized)
    }

    private static func qualifiesAsDraft(_ text: String) -> Bool {
        guard !looksLikeCode(text) else { return false }
        guard !looksLikeBrainstorm(text) else { return false }
        let wordCount = words(in: text).count
        guard text.count >= 40, wordCount >= 8 else { return false }
        let greetingPrefix = ["hi ", "hello ", "dear ", "hey "]
        let hasGreeting = greetingPrefix.contains { text.lowercased().hasPrefix($0) }
        let hasClosing = ["thanks", "thank you", "best", "regards"].contains { text.lowercased().contains($0) }
        let sentenceLike = sentenceCount(in: text) >= 2 || text.contains(":")
        return hasGreeting || hasClosing || sentenceLike
    }

    private static func qualifiesAsCode(_ text: String, codeBlock: String?) -> Bool {
        if let codeBlock, !codeBlock.isEmpty {
            return true
        }
        guard text.count >= 20 else { return false }
        return looksLikeCode(text)
    }

    private static func qualifiesAsPlan(_ text: String, checklistItems: [String]) -> Bool {
        if checklistItems.count >= 3 {
            return true
        }
        let lowercased = text.lowercased()
        let planningMarkers = ["step 1", "next step", "plan", "checklist", "roadmap", "first,", "second,"]
        let markerCount = planningMarkers.reduce(0) { partial, marker in
            partial + (lowercased.contains(marker) ? 1 : 0)
        }
        return markerCount >= 2 && text.count >= 50
    }

    private static func qualifiesAsClarification(_ text: String) -> Bool {
        guard text.contains("?") else { return false }
        guard text.count >= 18 else { return false }
        let lowercased = text.lowercased()
        let clarificationMarkers = [
            "could you clarify", "can you clarify", "which one", "which version", "what kind", "what exactly", "do you want", "should i", "can you share", "i need more detail"
        ]
        return clarificationMarkers.contains { lowercased.contains($0) }
    }

    private static func qualifiesAsSummary(_ text: String, checklistItems: [String]) -> Bool {
        guard text.count >= 40 else { return false }
        let lowercased = text.lowercased()
        let summaryMarkers = ["summary", "in short", "overall", "key points", "takeaways", "decisions", "high level"]
        if summaryMarkers.contains(where: { lowercased.contains($0) }) {
            return true
        }
        return checklistItems.count >= 3 && sentenceCount(in: text) >= 2
    }

    private static func qualifiesAsKnowledgeAnswer(_ text: String, checklistItems: [String]) -> Bool {
        guard text.count >= 40 else { return false }
        guard !looksLikeCode(text) else { return false }
        return sentenceCount(in: text) >= 2 || checklistItems.count >= 2 || words(in: text).count >= 10
    }

    private static func qualifiesAsProsAndCons(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("pros") && lowercased.contains("cons") && text.count >= 40
    }

    private static func qualifiesAsBrainstorm(_ text: String, checklistItems: [String]) -> Bool {
        guard looksLikeBrainstorm(text) else { return false }
        return checklistItems.count >= 3 || sentenceCount(in: text) >= 3
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

    private static func extractCodeBlock(from text: String) -> String? {
        guard let start = text.range(of: "```"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeBrainstorm(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("ideas") || lowercased.contains("options") || lowercased.contains("brainstorm") || lowercased.contains("approaches")
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let markers = ["func ", "class ", "struct ", "let ", "var ", "return ", "import ", "print(", "if ", "for ", "while ", "=", "{" , "}"]
        let score = markers.reduce(0) { partial, marker in
            partial + (lowercased.contains(marker) ? 1 : 0)
        }
        let newlineSeparated = text.contains("\n")
        return score >= 3 || (score >= 2 && newlineSeparated)
    }

    private static func codeSummary(from text: String, codeBlock: String?) -> String {
        if let codeBlock, !codeBlock.isEmpty {
            let leading = leadingParagraph(from: text)
            return leading == codeBlock ? "Provided code." : leading
        }
        return leadingParagraph(from: text)
    }

    private static func words(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func sentenceCount(in text: String) -> Int {
        text.split(whereSeparator: { ".!?\n".contains($0) }).count
    }

    private static func unique(_ kinds: [JarvisSkillOutputKind]) -> [JarvisSkillOutputKind] {
        var seen: Set<JarvisSkillOutputKind> = []
        var result: [JarvisSkillOutputKind] = []
        for kind in kinds where !seen.contains(kind) {
            seen.insert(kind)
            result.append(kind)
        }
        return result
    }
}
