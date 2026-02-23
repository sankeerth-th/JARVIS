import Foundation

final class LocalIndexService {
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
        let results = try await searchFiles(query: query, limit: limit, queryExpansionModel: nil)
        return results.map { $0.document }
    }

    func searchFiles(query: String, limit: Int, queryExpansionModel: String?) async throws -> [FileSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        let docs = database.loadIndexedDocuments(limit: 500)
        guard !docs.isEmpty else { return [] }
        let queryEmbedding = try? await embedding(for: trimmedQuery)
        let queryTerms = await expandedTerms(for: trimmedQuery, model: queryExpansionModel)
        let ranked = docs.map { doc -> FileSearchResult in
            let semanticScore: Double
            if let queryEmbedding {
                semanticScore = Self.cosineSimilarity(queryEmbedding, doc.embedding)
            } else {
                semanticScore = 0
            }
            let keywordScore = Self.keywordMatchScore(terms: queryTerms, path: doc.path, title: doc.title, text: doc.extractedText)
            let score = queryEmbedding == nil ? keywordScore : ((semanticScore * 0.75) + (keywordScore * 0.25))
            return FileSearchResult(document: doc, snippet: Self.bestSnippet(from: doc.extractedText, terms: queryTerms), score: max(0, score))
        }.sorted(by: { $0.score > $1.score })
        return ranked.prefix(limit).filter { $0.score > 0.02 }.map { $0 }
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

    private static func keywordMatchScore(terms: [String], path: String, title: String) -> Double {
        keywordMatchScore(terms: terms, path: path, title: title, text: "")
    }

    private static func keywordMatchScore(terms: [String], path: String, title: String, text: String) -> Double {
        guard !terms.isEmpty else { return 0 }
        let haystack = "\(title.lowercased()) \(path.lowercased()) \(text.lowercased())"
        let matchCount = terms.filter { haystack.contains($0) }.count
        let tfScore = terms.reduce(0.0) { partial, term in
            partial + Double(haystack.components(separatedBy: term).count - 1)
        }
        return (Double(matchCount) / Double(terms.count)) * 0.6 + min(tfScore / 20.0, 0.4)
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

    private static let supportedExtensions = ["md", "txt", "rtf", "text", "markdown", "pdf", "docx", "png", "jpg", "jpeg", "heic", "tif", "tiff"]
}
