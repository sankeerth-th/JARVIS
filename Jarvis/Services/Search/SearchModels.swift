import Foundation

enum SearchIntent: String, Codable {
    case filenameLookup
    case contentLookup
    case recentLookup
    case ocrLookup
    case exactPhraseLookup
    case broadSemanticLookup
}

struct SearchStrategy: Codable, Equatable {
    var lexicalWeight: Double
    var semanticWeight: Double
    var filenameWeight: Double
    var metadataWeight: Double
    var recencyWeight: Double
    var ocrWeight: Double
    var maxCandidates: Int
    var maxChunksPerFile: Int
    var requirePhrase: Bool
    var description: String
}

struct SearchQueryAnalysis: Equatable {
    var rawQuery: String
    var normalizedQuery: String
    var terms: [String]
    var phrase: String?
    var intent: SearchIntent
    var strategy: SearchStrategy
    var prefersDocumentFiles: Bool
    var prefersImageFiles: Bool
    var wantsRecent: Bool
    var targetedCategory: String?
}

struct IndexedFileRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var path: String
    var filename: String
    var fileExtension: String
    var sourceType: String
    var category: String?
    var contentHash: String
    var fileSize: Int64
    var createdAt: Date?
    var modifiedAt: Date?
    var lastIndexed: Date
    var pageCount: Int?
    var ocrConfidence: Double?
    var indexVersion: Int
    var embeddingModel: String?
    var embeddingDim: Int?
}

struct IndexedChunkRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var fileID: UUID
    var ordinal: Int
    var page: Int?
    var chunkHash: String
    var text: String
    var normalizedText: String
    var embedding: [Double]?
    var embeddingModel: String?
    var embeddingDim: Int?
}

struct SearchChunkCandidate: Equatable {
    var file: IndexedFileRecord
    var chunk: IndexedChunkRecord
    var lexicalScore: Double
}

struct SearchResultReason: Codable, Equatable, Hashable {
    var label: String
    var value: String
}

struct SearchDebugTrace: Codable, Equatable {
    var intent: SearchIntent
    var strategy: String
    var lexicalScore: Double
    var semanticScore: Double
    var filenameScore: Double
    var metadataScore: Double
    var recencyScore: Double
    var ocrScore: Double
    var duplicatePenalty: Double
    var finalScore: Double
}

struct SearchRankedFileResult: Equatable {
    var file: IndexedFileRecord
    var chunk: IndexedChunkRecord
    var score: Double
    var reasons: [SearchResultReason]
    var debugTrace: SearchDebugTrace
}

struct SearchRunRecord {
    var query: String
    var intent: SearchIntent
    var strategy: String
    var resultCount: Int
    var latencyMs: Int
    var debugSummary: String
    var createdAt: Date
}
