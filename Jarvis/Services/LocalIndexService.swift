import Foundation

final class LocalIndexService {
    private let database: JarvisDatabase
    private let importService: DocumentImportService
    private let ollama: OllamaClient
    private let embeddingModel: String
    private let fileManager = FileManager.default

    private let ingestionService: SearchIngestionService
    private let chunker = SearchChunker()
    private let queryAnalyzer = SearchQueryAnalyzer()
    private let ranker = SearchRanker()
    private let diagnosticsLogger: SearchDiagnosticsLogger

    private let searchIndexVersion = 2

    init(database: JarvisDatabase, importService: DocumentImportService, ollama: OllamaClient, embeddingModel: String = "nomic-embed-text") {
        self.database = database
        self.importService = importService
        self.ollama = ollama
        self.embeddingModel = embeddingModel
        self.ingestionService = SearchIngestionService(importService: importService)
        self.diagnosticsLogger = SearchDiagnosticsLogger(database: database)
    }

    func indexFolder(_ folder: URL, progress: ((Int, Int) -> Void)? = nil) async throws -> Int {
        ensureSearchIndexVersion()

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var fileURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if values.isDirectory == true { continue }
            if !SearchIngestionService.supportedExtensions.contains(fileURL.pathExtension.lowercased()) { continue }
            fileURLs.append(fileURL)
        }

        var indexedCount = 0
        let totalFiles = fileURLs.count
        progress?(0, totalFiles)

        for (index, fileURL) in fileURLs.enumerated() {
            defer { progress?(index + 1, totalFiles) }

            do {
                guard var payload = try ingestionService.ingestFile(at: fileURL, indexVersion: searchIndexVersion) else {
                    diagnosticsLogger.logIngestion(filePath: fileURL.path, status: "skipped", metadata: ["reason": "empty_or_placeholder_text"])
                    continue
                }

                if let existing = database.loadIndexedFileV2(path: payload.file.path),
                   shouldSkipReindex(existing: existing, incoming: payload.file) {
                    diagnosticsLogger.logIngestion(filePath: fileURL.path, status: "dedup", metadata: ["reason": "unchanged_hash_and_metadata"])
                    continue
                }

                if let existing = database.loadIndexedFileV2(path: payload.file.path) {
                    payload.file.id = existing.id
                }

                let chunks = chunker.chunk(payload: payload)
                if chunks.isEmpty {
                    diagnosticsLogger.logIngestion(filePath: fileURL.path, status: "skipped", metadata: ["reason": "no_chunks"])
                    continue
                }

                database.upsertIndexedFileV2(payload.file)
                database.replaceChunksV2(fileID: payload.file.id, chunks: chunks)

                // Keep legacy index populated so existing callers remain compatible.
                let legacyEmbedding = try await embedding(for: payload.normalizedText)
                let legacyDoc = IndexedDocument(
                    title: payload.file.title,
                    path: payload.file.path,
                    embedding: legacyEmbedding,
                    extractedText: String(payload.normalizedText.prefix(50_000)),
                    lastModified: payload.file.modifiedAt,
                    lastIndexed: payload.file.lastIndexed
                )
                database.saveIndexedDocument(legacyDoc)

                indexedCount += 1
                diagnosticsLogger.logIngestion(
                    filePath: fileURL.path,
                    status: "success",
                    metadata: [
                        "chunks": "\(chunks.count)",
                        "source_type": payload.file.sourceType,
                        "content_hash": payload.file.contentHash.prefix(12).description,
                        "ocr_confidence": payload.file.ocrConfidence.map { String(format: "%.2f", $0) } ?? "n/a"
                    ]
                )
            } catch {
                diagnosticsLogger.logIngestion(filePath: fileURL.path, status: "error", metadata: ["error": error.localizedDescription])
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
        _ = queryExpansionModel // Reserved for future local query expansion.
        let started = Date()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let analysis = queryAnalyzer.analyze(trimmed)

        do {
            if database.countIndexedFilesV2() == 0 {
                let fallback = legacySearch(query: trimmed, limit: limit, rootFolders: rootFolders)
                diagnosticsLogger.logSearchRun(
                    SearchRunRecord(
                        query: trimmed,
                        intent: analysis.intent,
                        strategy: "legacy_fallback",
                        resultCount: fallback.count,
                        latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                        debugSummary: "v2 index empty, used legacy table",
                        createdAt: Date()
                    )
                )
                return fallback
            }

            let matchQuery = queryAnalyzer.buildFTSQuery(from: analysis)
            var candidates = database.searchChunkCandidatesV2(
                matchQuery: matchQuery,
                rootFolders: rootFolders,
                limit: max(limit * 20, analysis.strategy.maxCandidates)
            )

            if candidates.isEmpty {
                let broadCandidates = database.loadAllChunkCandidatesV2(rootFolders: rootFolders, limit: 2000)
                candidates = broadCandidates
                    .map { candidate in
                        var mutable = candidate
                        mutable.lexicalScore = lexicalScore(queryTerms: analysis.terms, file: candidate.file, chunk: candidate.chunk)
                        return mutable
                    }
                    .filter { $0.lexicalScore > 0.05 }
            }

            guard !candidates.isEmpty else {
                diagnosticsLogger.logSearchRun(
                    SearchRunRecord(
                        query: trimmed,
                        intent: analysis.intent,
                        strategy: analysis.strategy.description,
                        resultCount: 0,
                        latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                        debugSummary: "no_candidates",
                        createdAt: Date()
                    )
                )
                return []
            }

            let queryEmbedding = try await queryEmbeddingIfCompatible(with: candidates, query: trimmed)
            let ranked = ranker.rank(candidates: candidates, analysis: analysis, queryEmbedding: queryEmbedding, limit: limit)

            let results = ranked.map { rankedFile in
                let doc = IndexedDocument(
                    title: rankedFile.file.title,
                    path: rankedFile.file.path,
                    embedding: [],
                    extractedText: rankedFile.chunk.text,
                    lastModified: rankedFile.file.modifiedAt,
                    lastIndexed: rankedFile.file.lastIndexed
                )
                return FileSearchResult(
                    document: doc,
                    snippet: bestSnippet(from: rankedFile.chunk.text, terms: analysis.terms),
                    score: rankedFile.score,
                    reasons: rankedFile.reasons,
                    debugSummary: debugSummary(for: rankedFile.debugTrace)
                )
            }

            let runDebugSummary = ranked.prefix(3).map {
                "\($0.file.filename): \(String(format: "%.2f", $0.score)) [\($0.debugTrace.strategy)]"
            }.joined(separator: " | ")

            diagnosticsLogger.logSearchRun(
                SearchRunRecord(
                    query: trimmed,
                    intent: analysis.intent,
                    strategy: analysis.strategy.description,
                    resultCount: results.count,
                    latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                    debugSummary: runDebugSummary,
                    createdAt: Date()
                )
            )

            return results
        } catch {
            diagnosticsLogger.logSearchFailure(query: trimmed, error: error)
            throw error
        }
    }

    private func ensureSearchIndexVersion() {
        let current = database.searchIndexVersion()
        if current != searchIndexVersion {
            database.clearSearchIndexV2()
            database.setSearchIndexVersion(searchIndexVersion)
        }
    }

    private func shouldSkipReindex(existing: IndexedFileRecord, incoming: IndexedFileRecord) -> Bool {
        existing.title == incoming.title
            && existing.path == incoming.path
            && existing.filename == incoming.filename
            && existing.fileExtension == incoming.fileExtension
            && existing.sourceType == incoming.sourceType
            && existing.category == incoming.category
            && existing.contentHash == incoming.contentHash
            && existing.fileSize == incoming.fileSize
            && existing.createdAt == incoming.createdAt
            && existing.modifiedAt == incoming.modifiedAt
            && existing.pageCount == incoming.pageCount
            && existing.ocrConfidence == incoming.ocrConfidence
            && existing.indexVersion == incoming.indexVersion
            && existing.embeddingModel == incoming.embeddingModel
            && existing.embeddingDim == incoming.embeddingDim
    }

    private func embedding(for text: String) async throws -> [Double] {
        if text.isEmpty { return [] }
        return try await ollama.embeddings(for: String(text.prefix(3000)), model: embeddingModel)
    }

    private func queryEmbeddingIfCompatible(with candidates: [SearchChunkCandidate], query: String) async throws -> [Double]? {
        let hasCompatibleEmbeddings = candidates.contains { candidate in
            guard let embedding = candidate.chunk.embedding else { return false }
            guard !embedding.isEmpty else { return false }
            return candidate.chunk.embeddingModel == embeddingModel
        }
        guard hasCompatibleEmbeddings else { return nil }
        return try await ollama.embeddings(for: String(query.prefix(2000)), model: embeddingModel)
    }

    private func lexicalScore(queryTerms: [String], file: IndexedFileRecord, chunk: IndexedChunkRecord) -> Double {
        guard !queryTerms.isEmpty else { return 0 }
        let hay = "\(file.title.lowercased()) \(file.path.lowercased()) \(chunk.normalizedText.lowercased())"
        let hits = queryTerms.reduce(0) { partial, term in
            partial + (hay.contains(term) ? 1 : 0)
        }
        return min(1, Double(hits) / Double(max(1, queryTerms.count)))
    }

    private func debugSummary(for trace: SearchDebugTrace) -> String {
        "intent=\(trace.intent.rawValue), strategy=\(trace.strategy), lexical=\(String(format: "%.2f", trace.lexicalScore)), semantic=\(String(format: "%.2f", trace.semanticScore)), filename=\(String(format: "%.2f", trace.filenameScore)), meta=\(String(format: "%.2f", trace.metadataScore)), recency=\(String(format: "%.2f", trace.recencyScore)), ocr=\(String(format: "%.2f", trace.ocrScore)), dup=\(String(format: "%.2f", trace.duplicatePenalty)), final=\(String(format: "%.2f", trace.finalScore))"
    }

    private func legacySearch(query: String, limit: Int, rootFolders: [String]?) -> [FileSearchResult] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 }

        let docs = database.loadIndexedDocuments(limit: 10_000).filter { doc in
            guard let rootFolders, !rootFolders.isEmpty else { return true }
            let path = URL(fileURLWithPath: doc.path).standardizedFileURL.path
            return rootFolders.contains { root in
                let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
                return path.hasPrefix(normalizedRoot + "/") || path == normalizedRoot
            }
        }

        let ranked = docs.map { doc -> FileSearchResult in
            let haystack = "\(doc.title.lowercased()) \(doc.path.lowercased()) \(doc.extractedText.lowercased())"
            let hits = terms.filter { haystack.contains($0) }.count
            let score = terms.isEmpty ? 0 : Double(hits) / Double(max(terms.count, 1))
            return FileSearchResult(
                document: doc,
                snippet: bestSnippet(from: doc.extractedText, terms: terms),
                score: score,
                reasons: [.init(label: "Legacy lexical", value: String(format: "%.2f", score))],
                debugSummary: "legacy_index"
            )
        }
        .filter { $0.score > 0.05 }
        .sorted { $0.score > $1.score }

        return Array(ranked.prefix(limit))
    }

    private func bestSnippet(from text: String, terms: [String]) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "No preview available." }
        if let match = terms.first(where: { cleaned.localizedCaseInsensitiveContains($0) }),
           let range = cleaned.range(of: match, options: .caseInsensitive) {
            let start = cleaned.index(range.lowerBound, offsetBy: -90, limitedBy: cleaned.startIndex) ?? cleaned.startIndex
            let end = cleaned.index(range.lowerBound, offsetBy: 180, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            return String(cleaned[start..<end]).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(cleaned.prefix(220)).replacingOccurrences(of: "\n", with: " ")
    }
}
