import Foundation

final class SearchQueryAnalyzer {
    private static let stopWords: Set<String> = [
        "a", "an", "the", "in", "on", "of", "for", "to", "from", "with", "that", "this",
        "is", "are", "was", "were", "be", "my", "me", "show", "find", "search", "get", "latest"
    ]

    func analyze(_ query: String) -> SearchQueryAnalysis {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let phrase = Self.extractQuotedPhrase(from: normalized)
        let allTerms = Self.tokenize(normalized)
        let terms = allTerms.filter { !Self.stopWords.contains($0) }

        let wantsRecent = allTerms.contains(where: { ["latest", "recent", "newest", "today", "yesterday"].contains($0) })
        let wantsFilename = normalized.contains("filename")
            || normalized.contains("file")
            || normalized.contains("files")
            || normalized.contains("file name")
            || normalized.contains("named")
            || normalized.contains("called")
            || normalized.contains("path")
            || normalized.contains("resume")
            || normalized.contains("cv")
            || normalized.contains("document")
            || normalized.contains("pdf")
        let wantsOCR = allTerms.contains(where: { ["screenshot", "photo", "image", "scan", "ocr", "picture"].contains($0) })
        let wantsDocs = allTerms.contains(where: { ["pdf", "doc", "docx", "word", "notes", "resume", "invoice", "document"].contains($0) })
        let targetedCategory: String? = {
            if allTerms.contains("resume") || allTerms.contains("cv") { return "resume" }
            if allTerms.contains("invoice") || allTerms.contains("receipt") || allTerms.contains("bill") { return "invoice" }
            if allTerms.contains("screenshot") || allTerms.contains("photo") || allTerms.contains("image") { return "screenshot" }
            if allTerms.contains("notes") || allTerms.contains("meeting") { return "notes" }
            return nil
        }()

        let intent: SearchIntent
        if phrase != nil {
            intent = .exactPhraseLookup
        } else if wantsFilename {
            intent = .filenameLookup
        } else if wantsRecent {
            intent = .recentLookup
        } else if wantsOCR {
            intent = .ocrLookup
        } else if terms.count <= 2 {
            intent = .contentLookup
        } else {
            intent = .broadSemanticLookup
        }

        let strategy = strategy(for: intent)
        return SearchQueryAnalysis(
            rawQuery: query,
            normalizedQuery: normalized,
            terms: terms,
            phrase: phrase,
            intent: intent,
            strategy: strategy,
            prefersDocumentFiles: wantsDocs && !wantsOCR,
            prefersImageFiles: wantsOCR,
            wantsRecent: wantsRecent,
            targetedCategory: targetedCategory
        )
    }

    func buildFTSQuery(from analysis: SearchQueryAnalysis) -> String {
        if let phrase = analysis.phrase, !phrase.isEmpty {
            return "\"\(sanitizedFTSTerm(phrase))\""
        }
        let terms = analysis.terms.map(sanitizedFTSTerm).filter { !$0.isEmpty }
        if terms.isEmpty {
            return sanitizedFTSTerm(analysis.normalizedQuery)
        }
        return terms.joined(separator: " OR ")
    }

    private func strategy(for intent: SearchIntent) -> SearchStrategy {
        switch intent {
        case .filenameLookup:
            return SearchStrategy(lexicalWeight: 0.45, semanticWeight: 0.10, filenameWeight: 0.30, metadataWeight: 0.10, recencyWeight: 0.03, ocrWeight: 0.02, maxCandidates: 180, maxChunksPerFile: 2, requirePhrase: false, description: "filename_lexical")
        case .contentLookup:
            return SearchStrategy(lexicalWeight: 0.54, semanticWeight: 0.18, filenameWeight: 0.10, metadataWeight: 0.10, recencyWeight: 0.05, ocrWeight: 0.03, maxCandidates: 220, maxChunksPerFile: 2, requirePhrase: false, description: "content_hybrid")
        case .recentLookup:
            return SearchStrategy(lexicalWeight: 0.42, semanticWeight: 0.12, filenameWeight: 0.10, metadataWeight: 0.12, recencyWeight: 0.20, ocrWeight: 0.04, maxCandidates: 200, maxChunksPerFile: 2, requirePhrase: false, description: "recent_weighted")
        case .ocrLookup:
            return SearchStrategy(lexicalWeight: 0.50, semanticWeight: 0.10, filenameWeight: 0.08, metadataWeight: 0.12, recencyWeight: 0.08, ocrWeight: 0.12, maxCandidates: 240, maxChunksPerFile: 3, requirePhrase: false, description: "ocr_text_heavy")
        case .exactPhraseLookup:
            return SearchStrategy(lexicalWeight: 0.66, semanticWeight: 0.08, filenameWeight: 0.08, metadataWeight: 0.10, recencyWeight: 0.05, ocrWeight: 0.03, maxCandidates: 140, maxChunksPerFile: 1, requirePhrase: true, description: "exact_phrase")
        case .broadSemanticLookup:
            return SearchStrategy(lexicalWeight: 0.46, semanticWeight: 0.24, filenameWeight: 0.08, metadataWeight: 0.11, recencyWeight: 0.07, ocrWeight: 0.04, maxCandidates: 260, maxChunksPerFile: 3, requirePhrase: false, description: "broad_hybrid")
        }
    }

    private static func tokenize(_ input: String) -> [String] {
        input
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0) }
            .filter { $0.count > 1 }
    }

    private static func extractQuotedPhrase(from input: String) -> String? {
        guard let firstQuote = input.firstIndex(of: "\""),
              let lastQuote = input.lastIndex(of: "\""),
              firstQuote < lastQuote else {
            return nil
        }
        let phrase = String(input[input.index(after: firstQuote)..<lastQuote])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.isEmpty ? nil : phrase
    }

    private func sanitizedFTSTerm(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
