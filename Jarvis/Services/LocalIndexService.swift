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
        var indexedCount = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if values.isDirectory == true { continue }
            if !Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) { continue }
            do {
                let document = try importService.importDocument(at: fileURL)
                let embedding = try await embedding(for: document.content)
                let indexed = IndexedDocument(title: document.title, path: fileURL.path, embedding: embedding)
                database.saveIndexedDocument(indexed)
                indexedCount += 1
            } catch {
                continue
            }
        }
        return indexedCount
    }

    func search(query: String, limit: Int) async throws -> [IndexedDocument] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        let docs = database.loadIndexedDocuments(limit: 200)
        guard !docs.isEmpty else { return [] }
        let queryEmbedding = try? await embedding(for: trimmedQuery)
        let queryTerms = Self.terms(from: trimmedQuery)
        let ranked = docs.map { doc -> (IndexedDocument, Double) in
            let semanticScore: Double
            if let queryEmbedding {
                semanticScore = Self.cosineSimilarity(queryEmbedding, doc.embedding)
            } else {
                semanticScore = 0
            }
            let keywordScore = Self.keywordMatchScore(terms: queryTerms, path: doc.path, title: doc.title)
            let score = queryEmbedding == nil ? keywordScore : ((semanticScore * 0.85) + (keywordScore * 0.15))
            return (doc, score)
        }.sorted(by: { $0.1 > $1.1 })
        return ranked.prefix(limit).map { $0.0 }
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
        guard !terms.isEmpty else { return 0 }
        let haystack = "\(title.lowercased()) \(path.lowercased())"
        let matches = terms.filter { haystack.contains($0) }.count
        return Double(matches) / Double(terms.count)
    }

    private static let supportedExtensions = ["md", "txt", "rtf", "text", "markdown", "pdf", "docx", "png", "jpg", "jpeg", "heic", "tif", "tiff"]
}
