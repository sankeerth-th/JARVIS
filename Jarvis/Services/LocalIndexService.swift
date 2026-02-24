import Foundation

final class LocalIndexService {
    private struct QueryIntent {
        let rawQuery: String
        let normalizedQuery: String
        let terms: [String]
        let requiredTerms: [String]
        let prefersDocumentFiles: Bool
        let prefersImageFiles: Bool
        let isResumeQuery: Bool
    }

    private let database: JarvisDatabase
    private let importService: DocumentImportService
    private let ollama: OllamaClient
    private let embeddingModel: String
    private let fileManager = FileManager.default
    private static let fallbackVectorSize = 512

    init(database: JarvisDatabase, importService: DocumentImportService, ollama: OllamaClient, embeddingModel: String = "nomic-embed-text") {
        self.database = database
        self.importService = importService
        self.ollama = ollama
        self.embeddingModel = embeddingModel
    }

    func indexFolder(_ folder: URL) async throws -> Int {
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: resourceKeys) else { return 0 }
        let existingByPath = Dictionary(uniqueKeysWithValues: database.loadIndexedDocuments(limit: 10_000).map { ($0.path, $0) })
        var indexedCount = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if values.isDirectory == true { continue }
            if !Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) { continue }
            do {
                let document = try importService.importDocument(at: fileURL)
                if let existing = existingByPath[fileURL.path],
                   let oldModified = existing.lastModified,
                   let newModified = document.lastModified,
                   oldModified >= newModified {
                    continue
                }
                let embedding = try await embedding(for: document.content)
                let indexed = IndexedDocument(
                    title: document.title,
                    path: fileURL.path,
                    embedding: embedding,
                    extractedText: String(document.content.prefix(50_000)),
                    lastModified: document.lastModified
                )
                database.saveIndexedDocument(indexed)
                indexedCount += 1
            } catch {
                continue
            }
        }
        return indexedCount
    }

    func search(query: String, limit: Int) async throws -> [IndexedDocument] {
        let results = try await searchFiles(query: query, limit: limit, queryExpansionModel: nil, rootFolders: nil)
        return results.map { $0.document }
    }

    func searchFiles(query: String, limit: Int, queryExpansionModel: String?, rootFolders: [String]?) async throws -> [FileSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        let intent = Self.intent(for: trimmedQuery)
        let loaded = database.loadIndexedDocuments(limit: 10_000)
        let docs = filterDocuments(loaded, rootFolders: rootFolders)
        guard !docs.isEmpty else { return [] }
        let queryEmbedding = try? await embedding(for: trimmedQuery)
        let queryTerms = await expandedTerms(for: trimmedQuery, model: queryExpansionModel)
        let rankingTerms = Array(Set(intent.terms + queryTerms))
        let ranked = docs.map { doc -> FileSearchResult in
            let semanticScore: Double
            if let queryEmbedding {
                semanticScore = Self.cosineSimilarity(queryEmbedding, doc.embedding)
            } else {
                semanticScore = 0
            }
            let lexical = Self.lexicalMatchScore(terms: rankingTerms, path: doc.path, title: doc.title, text: doc.extractedText)
            let category = Self.categoryAffinityScore(intent: intent, path: doc.path, title: doc.title, text: doc.extractedText)
            let quality = Self.ocrQualityAdjustment(intent: intent, path: doc.path, text: doc.extractedText)
            let requiredMatches = Self.requiredTermMatches(intent.requiredTerms, path: doc.path, title: doc.title, text: doc.extractedText)

            var score: Double
            if queryEmbedding == nil {
                score = (lexical.score * 0.8) + (category * 0.2)
            } else if intent.terms.isEmpty {
                score = (semanticScore * 0.75) + (lexical.score * 0.15) + (category * 0.10)
            } else {
                score = (lexical.score * 0.62) + (semanticScore * 0.25) + (category * 0.13)
            }

            if !intent.requiredTerms.isEmpty && requiredMatches == 0 {
                score *= semanticScore > 0.78 ? 0.5 : 0.08
            }

            score = max(0, min(1, score + quality))
            return FileSearchResult(document: doc, snippet: Self.bestSnippet(from: doc.extractedText, terms: rankingTerms), score: score)
        }.sorted(by: { $0.score > $1.score })
        let threshold = intent.prefersDocumentFiles || intent.prefersImageFiles ? 0.08 : 0.06
        return ranked.prefix(limit).filter { $0.score > threshold }.map { $0 }
    }

    private func filterDocuments(_ docs: [IndexedDocument], rootFolders: [String]?) -> [IndexedDocument] {
        guard let rootFolders, !rootFolders.isEmpty else { return docs }
        let normalizedRoots = rootFolders.map { root -> String in
            let standardized = URL(fileURLWithPath: root).standardizedFileURL.path
            return standardized.hasSuffix("/") ? standardized : standardized + "/"
        }
        return docs.filter { doc in
            let path = URL(fileURLWithPath: doc.path).standardizedFileURL.path
            return normalizedRoots.contains(where: { path.hasPrefix($0) || path == String($0.dropLast()) })
        }
    }

    private func embedding(for text: String) async throws -> [Double] {
        do {
            return try await ollama.embeddings(for: text, model: embeddingModel)
        } catch {
            return Self.keywordVector(for: text)
        }
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let length = min(a.count, b.count)
        var dot: Double = 0
        var aNorm: Double = 0
        var bNorm: Double = 0
        for i in 0..<length {
            dot += a[i] * b[i]
            aNorm += a[i] * a[i]
            bNorm += b[i] * b[i]
        }
        guard aNorm > 0, bNorm > 0 else { return 0 }
        return dot / (sqrt(aNorm) * sqrt(bNorm))
    }

    private static func keywordVector(for text: String) -> [Double] {
        let tokens = terms(from: text)
        var vector = Array(repeating: 0.0, count: fallbackVectorSize)
        for token in tokens {
            let index = stableBucket(for: token, modulo: fallbackVectorSize)
            vector[index] += 1
        }
        let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private static func terms(from text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 }
    }

    private static func stableBucket(for token: String, modulo: Int) -> Int {
        var hash = 5381
        for byte in token.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return (hash & Int.max) % max(modulo, 1)
    }

    private static func lexicalMatchScore(terms: [String], path: String, title: String, text: String) -> (score: Double, matchedTerms: Set<String>) {
        guard !terms.isEmpty else { return (0, []) }
        let normalizedPath = path.lowercased()
        let normalizedTitle = title.lowercased()
        let normalizedText = text.lowercased()
        var matched: Set<String> = []
        var weightedHits = 0.0
        for term in terms {
            let titleHits = occurrenceCount(of: term, in: normalizedTitle)
            let pathHits = occurrenceCount(of: term, in: normalizedPath)
            let textHits = occurrenceCount(of: term, in: normalizedText)
            let total = titleHits + pathHits + textHits
            if total > 0 {
                matched.insert(term)
            }
            let termWeight = 1.0 + min(2.0, Double(term.count) / 6.0)
            let contribution = termWeight * min(4.0, (Double(titleHits) * 2.8) + (Double(pathHits) * 2.2) + (Double(textHits) * 1.0))
            weightedHits += contribution
        }
        let normalized = min(1.0, weightedHits / (Double(max(terms.count, 1)) * 4.2))
        return (normalized, matched)
    }

    private static func requiredTermMatches(_ requiredTerms: [String], path: String, title: String, text: String) -> Int {
        guard !requiredTerms.isEmpty else { return 0 }
        let haystack = "\(title.lowercased()) \(path.lowercased()) \(text.lowercased())"
        return requiredTerms.filter { haystack.contains($0) }.count
    }

    private static func categoryAffinityScore(intent: QueryIntent, path: String, title: String, text: String) -> Double {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let normalizedPath = path.lowercased()
        let normalizedTitle = title.lowercased()
        let normalizedText = text.lowercased()
        var score = 0.0

        if intent.prefersDocumentFiles {
            if documentExtensions.contains(ext) { score += 0.28 }
            if imageExtensions.contains(ext) { score -= 0.35 }
        }
        if intent.prefersImageFiles {
            if imageExtensions.contains(ext) { score += 0.30 }
            if documentExtensions.contains(ext) { score -= 0.12 }
        }
        if intent.isResumeQuery {
            if normalizedTitle.contains("resume")
                || normalizedTitle.contains("cv")
                || normalizedPath.contains("resume")
                || normalizedPath.contains("cv") {
                score += 0.32
            }
            if normalizedText.contains("experience") && normalizedText.contains("education") {
                score += 0.10
            }
            if imageExtensions.contains(ext) {
                score -= 0.25
            }
        }
        return max(-0.5, min(0.5, score))
    }

    private static func ocrQualityAdjustment(intent: QueryIntent, path: String, text: String) -> Double {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard imageExtensions.contains(ext), !intent.prefersImageFiles else { return 0 }
        let tokens = terms(from: text)
        if tokens.count < 10 {
            return -0.22
        }
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        if digits > letters {
            return -0.12
        }
        return 0
    }

    private func expandedTerms(for query: String, model: String?) async -> [String] {
        var terms = Self.terms(from: query)
        guard !terms.isEmpty else { return [] }
        guard let model, !model.isEmpty else { return terms }
        let expansionPrompt = """
        Expand this local file search query into short keyword synonyms.
        Output JSON only in this shape: {"terms":["word1","word2"]}.
        Query: \(query)
        """
        let request = GenerateRequest(
            model: model,
            prompt: expansionPrompt,
            system: "You are a local search helper. Return only JSON.",
            stream: false,
            options: ["temperature": 0.0, "num_predict": 120]
        )
        if let raw = try? await ollama.generate(request: request),
           let start = raw.firstIndex(of: "{"),
           let end = raw.lastIndex(of: "}"),
           let data = String(raw[start...end]).data(using: .utf8) {
            struct Expansion: Codable { let terms: [String] }
            if let parsed = try? JSONDecoder().decode(Expansion.self, from: data) {
                terms.append(contentsOf: parsed.terms.map { $0.lowercased() })
            }
        }
        return Array(Set(terms)).filter { $0.count > 1 }
    }

    private static func bestSnippet(from text: String, terms: [String]) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "No preview available." }
        if let match = terms.first(where: { cleaned.localizedCaseInsensitiveContains($0) }),
           let range = cleaned.range(of: match, options: .caseInsensitive) {
            let originalIndex = range.lowerBound
            let start = cleaned.index(originalIndex, offsetBy: -90, limitedBy: cleaned.startIndex) ?? cleaned.startIndex
            let end = cleaned.index(originalIndex, offsetBy: 180, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            let snippet = String(cleaned[start..<end]).replacingOccurrences(of: "\n", with: " ")
            return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(cleaned.prefix(220)).replacingOccurrences(of: "\n", with: " ")
    }

    private static func intent(for query: String) -> QueryIntent {
        let normalized = query.lowercased()
        let rawTerms = terms(from: normalized)
        let intentTerms = rawTerms.filter { !stopWords.contains($0) }
        let isResumeQuery = rawTerms.contains { ["resume", "cv", "curriculum", "vitae"].contains($0) }
        let prefersImageFiles = rawTerms.contains { ["image", "photo", "picture", "screenshot", "scan", "scanned"].contains($0) }
        let explicitDocHint = rawTerms.contains { ["pdf", "doc", "docx", "word", "document", "text", "notes"].contains($0) }
        let prefersDocumentFiles = (isResumeQuery || explicitDocHint) && !prefersImageFiles
        let requiredTerms = intentTerms.filter { !categoryTerms.contains($0) }
        return QueryIntent(
            rawQuery: query,
            normalizedQuery: normalized,
            terms: intentTerms,
            requiredTerms: requiredTerms,
            prefersDocumentFiles: prefersDocumentFiles,
            prefersImageFiles: prefersImageFiles,
            isResumeQuery: isResumeQuery
        )
    }

    private static func occurrenceCount(of term: String, in text: String) -> Int {
        guard !term.isEmpty, !text.isEmpty else { return 0 }
        var count = 0
        var searchRange: Range<String.Index>? = text.startIndex..<text.endIndex
        while let range = text.range(of: term, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private static let supportedExtensions = ["md", "txt", "rtf", "text", "markdown", "pdf", "docx", "png", "jpg", "jpeg", "heic", "tif", "tiff"]
    private static let documentExtensions: Set<String> = ["md", "txt", "rtf", "text", "markdown", "pdf", "docx", "doc", "pages"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp", "webp"]
    private static let stopWords: Set<String> = [
        "a", "an", "the", "of", "for", "in", "on", "to", "from", "with", "that",
        "this", "these", "those", "is", "are", "was", "were", "be", "it", "its",
        "find", "search", "show", "get", "me", "my", "which", "has", "have", "had"
    ]
    private static let categoryTerms: Set<String> = [
        "resume", "cv", "curriculum", "vitae", "pdf", "doc", "docx", "word",
        "document", "text", "note", "notes", "image", "photo", "picture", "screenshot", "scan"
    ]
}
