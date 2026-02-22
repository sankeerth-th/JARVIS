import Foundation

final class LocalIndexService {
    enum IndexError: Error {
        case embeddingsUnavailable
    }

    private let database: JarvisDatabase
    private let importService: DocumentImportService
    private let ollama: OllamaClient
    private let embeddingModel: String
    private let fileManager = FileManager.default

    init(database: JarvisDatabase, importService: DocumentImportService, ollama: OllamaClient, embeddingModel: String = "nomic-embed-text") {
        self.database = database
        self.importService = importService
        self.ollama = ollama
        self.embeddingModel = embeddingModel
    }

    func indexFolder(_ folder: URL) async throws {
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: resourceKeys) else { return }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if values.isDirectory == true { continue }
            if !Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) { continue }
            let document = try importService.importDocument(at: fileURL)
            let embedding = try await embedding(for: document.content)
            let indexed = IndexedDocument(title: document.title, path: fileURL.path, embedding: embedding)
            database.saveIndexedDocument(indexed)
        }
    }

    func search(query: String, limit: Int) async throws -> [IndexedDocument] {
        let docs = database.loadIndexedDocuments(limit: 200)
        guard !docs.isEmpty else { return [] }
        let queryEmbedding: [Double]
        do {
            queryEmbedding = try await embedding(for: query)
        } catch {
            throw IndexError.embeddingsUnavailable
        }
        let ranked = docs.map { doc -> (IndexedDocument, Double) in
            let similarity = Self.cosineSimilarity(queryEmbedding, doc.embedding)
            return (doc, similarity)
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
        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter })
        let counts = tokens.reduce(into: [String: Double]()) { dict, token in
            dict[String(token), default: 0] += 1
        }
        return Array(counts.values)
    }

    private static let supportedExtensions = ["md", "txt", "rtf", "text", "markdown", "pdf", "docx"]
}
