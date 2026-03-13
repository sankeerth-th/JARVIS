import XCTest
@testable import Jarvis

final class SearchPipelineTests: XCTestCase {
    func testPlaceholderTextIsIgnoredByIngestionNormalizer() {
        XCTAssertTrue(SearchIngestionService.isPlaceholderText("No text detected in image."))
        XCTAssertTrue(SearchIngestionService.isPlaceholderText("No extractable text found in PDF."))
        XCTAssertFalse(SearchIngestionService.isPlaceholderText("invoice number NK-12"))
    }

    func testNormalizationFixesHyphenatedOCRLineBreaks() {
        let raw = "Employ-\nment Authori-\nzation Request"
        let normalized = SearchIngestionService.normalizeText(raw)
        XCTAssertEqual(normalized, "Employment Authorization Request")
    }

    func testIntentAwareRankingPrioritizesResumeForAngularQuery() {
        let analyzer = SearchQueryAnalyzer()
        let analysis = analyzer.analyze("find the resume with angular")
        let ranker = SearchRanker()

        let resumeCandidate = makeCandidate(
            fileID: UUID(),
            title: "resume_angular.txt",
            path: "/tmp/resume_angular.txt",
            sourceType: "text",
            category: "resume",
            chunkText: "Skills include Angular and TypeScript with strong UI development experience.",
            lexical: 0.95
        )

        let screenshotCandidate = makeCandidate(
            fileID: UUID(),
            title: "random_car_screenshot_ocr.txt",
            path: "/tmp/random_car_screenshot_ocr.txt",
            sourceType: "image",
            category: "screenshot",
            chunkText: "i20s dashboard average fuel 29.1 mpg",
            lexical: 0.12
        )

        let results = ranker.rank(candidates: [screenshotCandidate, resumeCandidate], analysis: analysis, queryEmbedding: nil, limit: 3)
        XCTAssertEqual(results.first?.file.title, "resume_angular.txt")
    }

    func testFilenameTargetedQueryPrefersFilenameHit() {
        let analyzer = SearchQueryAnalyzer()
        let analysis = analyzer.analyze("find filename invoice_nk_2026")
        let ranker = SearchRanker()

        let filenameMatch = makeCandidate(
            fileID: UUID(),
            title: "invoice_nk_2026.txt",
            path: "/tmp/invoice_nk_2026.txt",
            sourceType: "pdf",
            category: "invoice",
            chunkText: "Amount Due and invoice details",
            lexical: 0.60
        )
        let contentOnly = makeCandidate(
            fileID: UUID(),
            title: "finance_notes.txt",
            path: "/tmp/finance_notes.txt",
            sourceType: "text",
            category: "notes",
            chunkText: "invoice nk 2026 appears in this content but not filename",
            lexical: 0.62
        )

        let results = ranker.rank(candidates: [contentOnly, filenameMatch], analysis: analysis, queryEmbedding: nil, limit: 2)
        XCTAssertEqual(results.first?.file.title, "invoice_nk_2026.txt")
    }

    func testContentTargetedQueryPrefersTextRelevanceOverFilename() {
        let analyzer = SearchQueryAnalyzer()
        let analysis = analyzer.analyze("angular architecture")
        let ranker = SearchRanker()

        let contentMatch = makeCandidate(
            fileID: UUID(),
            title: "engineering_notes.txt",
            path: "/tmp/engineering_notes.txt",
            sourceType: "text",
            category: "notes",
            chunkText: "Angular architecture patterns and modular boundaries for large systems.",
            lexical: 0.92
        )
        let filenameMatch = makeCandidate(
            fileID: UUID(),
            title: "angular.txt",
            path: "/tmp/angular.txt",
            sourceType: "text",
            category: nil,
            chunkText: "shopping list and recipes",
            lexical: 0.35
        )

        let results = ranker.rank(candidates: [filenameMatch, contentMatch], analysis: analysis, queryEmbedding: nil, limit: 2)
        XCTAssertEqual(results.first?.file.title, "engineering_notes.txt")
    }

    func testOCRTargetedQueryPrefersScreenshotCategory() {
        let analyzer = SearchQueryAnalyzer()
        let analysis = analyzer.analyze("that screenshot about opt form")
        let ranker = SearchRanker()

        let screenshot = makeCandidate(
            fileID: UUID(),
            title: "screenshot_opt_form_ocr.txt",
            path: "/tmp/screenshot_opt_form_ocr.txt",
            sourceType: "image",
            category: "screenshot",
            chunkText: "USCIS OPT Form Receipt Notice",
            lexical: 0.70
        )
        let pdf = makeCandidate(
            fileID: UUID(),
            title: "immigration_notes.pdf",
            path: "/tmp/immigration_notes.pdf",
            sourceType: "pdf",
            category: "notes",
            chunkText: "OPT checklist and timelines",
            lexical: 0.72
        )

        let results = ranker.rank(candidates: [pdf, screenshot], analysis: analysis, queryEmbedding: nil, limit: 2)
        XCTAssertEqual(results.first?.file.title, "screenshot_opt_form_ocr.txt")
    }

    func testDiversityReturnsBestChunkPerFile() {
        let analyzer = SearchQueryAnalyzer()
        let analysis = analyzer.analyze("invoice payment failed")
        let ranker = SearchRanker()

        let sharedFileID = UUID()
        let firstChunk = makeCandidate(
            fileID: sharedFileID,
            title: "invoice_nk_2026.txt",
            path: "/tmp/invoice_nk_2026.txt",
            sourceType: "pdf",
            category: "invoice",
            chunkText: "Invoice amount due and payment status pending",
            lexical: 0.85
        )
        let secondChunk = makeCandidate(
            fileID: sharedFileID,
            title: "invoice_nk_2026.txt",
            path: "/tmp/invoice_nk_2026.txt",
            sourceType: "pdf",
            category: "invoice",
            chunkText: "Payment failed retry immediately",
            lexical: 0.82
        )
        let otherFile = makeCandidate(
            fileID: UUID(),
            title: "notes.txt",
            path: "/tmp/notes.txt",
            sourceType: "text",
            category: "notes",
            chunkText: "Unrelated meeting notes",
            lexical: 0.20
        )

        let results = ranker.rank(candidates: [firstChunk, secondChunk, otherFile], analysis: analysis, queryEmbedding: nil, limit: 5)
        let invoiceCount = results.filter { $0.file.title == "invoice_nk_2026.txt" }.count
        XCTAssertEqual(invoiceCount, 1)
    }

    func testDuplicateContentSuppressionKeepsCanonicalResult() {
        let analyzer = SearchQueryAnalyzer()
        let analysis = analyzer.analyze("angular profile skills")
        let ranker = SearchRanker()

        let sharedText = "Angular TypeScript resume profile"
        let first = makeCandidate(
            fileID: UUID(),
            title: "resume_angular.txt",
            path: "/tmp/resume_angular.txt",
            sourceType: "text",
            category: "resume",
            chunkText: sharedText,
            lexical: 0.9
        )
        let second = makeCandidate(
            fileID: UUID(),
            title: "resume_copy.txt",
            path: "/tmp/resume_copy.txt",
            sourceType: "text",
            category: "resume",
            chunkText: sharedText,
            lexical: 0.89
        )

        let results = ranker.rank(candidates: [first, second], analysis: analysis, queryEmbedding: nil, limit: 5)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.file.title, "resume_angular.txt")
    }

    func testSameQueryWithDifferentIntentChangesTopResult() {
        let analyzer = SearchQueryAnalyzer()
        let ranker = SearchRanker()

        let filenameIntentFile = makeCandidate(
            fileID: UUID(),
            title: "resume_angular.txt",
            path: "/tmp/resume_angular.txt",
            sourceType: "text",
            category: "resume",
            chunkText: "general profile",
            lexical: 0.82
        )
        let filenameIntentContent = makeCandidate(
            fileID: UUID(),
            title: "career_notes.txt",
            path: "/tmp/career_notes.txt",
            sourceType: "text",
            category: "notes",
            chunkText: "This document discusses Angular architecture in depth",
            lexical: 0.20
        )

        let broadIntentFile = makeCandidate(
            fileID: UUID(),
            title: "resume_angular.txt",
            path: "/tmp/resume_angular.txt",
            sourceType: "text",
            category: "resume",
            chunkText: "general profile",
            lexical: 0.30
        )
        let broadIntentContent = makeCandidate(
            fileID: UUID(),
            title: "career_notes.txt",
            path: "/tmp/career_notes.txt",
            sourceType: "text",
            category: "notes",
            chunkText: "This document discusses Angular architecture in depth",
            lexical: 0.92
        )

        let filenameIntent = analyzer.analyze("find filename resume angular")
        let broadIntent = analyzer.analyze("angular architecture")

        let filenameResults = ranker.rank(candidates: [filenameIntentFile, filenameIntentContent], analysis: filenameIntent, queryEmbedding: nil, limit: 2)
        let broadResults = ranker.rank(candidates: [broadIntentFile, broadIntentContent], analysis: broadIntent, queryEmbedding: nil, limit: 2)

        XCTAssertEqual(filenameResults.first?.file.title, "resume_angular.txt")
        XCTAssertEqual(broadResults.first?.file.title, "career_notes.txt")
        XCTAssertNotEqual(filenameResults.first?.file.title, broadResults.first?.file.title)
    }

    func testSearchIndexVersionRoundTrip() {
        let db = JarvisDatabase(filename: "JarvisSearchPipelineTests.sqlite")
        db.clearSearchIndexV2()
        db.setSearchIndexVersion(2)
        XCTAssertEqual(db.searchIndexVersion(), 2)
    }

    func testChunkReplacementRemovesStaleChunksForUpdatedFileVersion() {
        let db = JarvisDatabase(filename: "JarvisSearchPipelineStale.sqlite")
        db.clearSearchIndexV2()
        db.setSearchIndexVersion(2)

        let fileID = UUID()
        let baseDate = Date()
        var file = IndexedFileRecord(
            id: fileID,
            title: "invoice_nk_2026.txt",
            path: "/tmp/invoice_nk_2026.txt",
            filename: "invoice_nk_2026.txt",
            fileExtension: "txt",
            sourceType: "text",
            category: "invoice",
            contentHash: SearchIngestionService.sha256Hex("old invoice body"),
            fileSize: 120,
            createdAt: baseDate,
            modifiedAt: baseDate,
            lastIndexed: baseDate,
            pageCount: 1,
            ocrConfidence: nil,
            indexVersion: 2,
            embeddingModel: nil,
            embeddingDim: nil
        )
        db.upsertIndexedFileV2(file)
        let oldChunk = IndexedChunkRecord(
            id: UUID(),
            fileID: fileID,
            ordinal: 0,
            page: 1,
            chunkHash: SearchIngestionService.sha256Hex("old invoice body"),
            text: "old invoice body",
            normalizedText: SearchIngestionService.normalizeText("old invoice body"),
            embedding: nil,
            embeddingModel: nil,
            embeddingDim: nil
        )
        db.replaceChunksV2(fileID: fileID, chunks: [oldChunk])

        file.contentHash = SearchIngestionService.sha256Hex("new invoice body")
        file.modifiedAt = baseDate.addingTimeInterval(5)
        file.lastIndexed = baseDate.addingTimeInterval(5)
        db.upsertIndexedFileV2(file)
        let newChunk = IndexedChunkRecord(
            id: UUID(),
            fileID: fileID,
            ordinal: 0,
            page: 1,
            chunkHash: SearchIngestionService.sha256Hex("new invoice body"),
            text: "new invoice body",
            normalizedText: SearchIngestionService.normalizeText("new invoice body"),
            embedding: nil,
            embeddingModel: nil,
            embeddingDim: nil
        )
        db.replaceChunksV2(fileID: fileID, chunks: [newChunk])

        let candidates = db.loadAllChunkCandidatesV2(rootFolders: nil, limit: 20).filter { $0.file.id == fileID }
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.chunk.text, "new invoice body")
    }

    private func makeCandidate(
        fileID: UUID,
        title: String,
        path: String,
        sourceType: String,
        category: String?,
        chunkText: String,
        lexical: Double
    ) -> SearchChunkCandidate {
        let file = IndexedFileRecord(
            id: fileID,
            title: title,
            path: path,
            filename: title,
            fileExtension: URL(fileURLWithPath: title).pathExtension,
            sourceType: sourceType,
            category: category,
            contentHash: SearchIngestionService.sha256Hex(chunkText),
            fileSize: Int64(chunkText.count),
            createdAt: Date(),
            modifiedAt: Date(),
            lastIndexed: Date(),
            pageCount: 1,
            ocrConfidence: sourceType == "image" ? 0.65 : nil,
            indexVersion: 2,
            embeddingModel: nil,
            embeddingDim: nil
        )
        let chunk = IndexedChunkRecord(
            id: UUID(),
            fileID: fileID,
            ordinal: 0,
            page: nil,
            chunkHash: SearchIngestionService.sha256Hex(chunkText),
            text: chunkText,
            normalizedText: SearchIngestionService.normalizeText(chunkText),
            embedding: nil,
            embeddingModel: nil,
            embeddingDim: nil
        )
        return SearchChunkCandidate(file: file, chunk: chunk, lexicalScore: lexical)
    }
}
