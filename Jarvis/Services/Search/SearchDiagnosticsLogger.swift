import Foundation

final class SearchDiagnosticsLogger {
    private let database: JarvisDatabase

    init(database: JarvisDatabase) {
        self.database = database
    }

    func logIngestion(filePath: String, status: String, metadata: [String: String] = [:]) {
        database.logFeatureEvent(
            FeatureEvent(
                feature: "Semantic search",
                type: "ingestion.\(status)",
                summary: "Indexed file \(URL(fileURLWithPath: filePath).lastPathComponent)",
                metadata: metadata.merging(["path": filePath]) { _, new in new }
            )
        )
    }

    func logSearchRun(_ run: SearchRunRecord) {
        database.saveSearchRunV2(run)
        database.logFeatureEvent(
            FeatureEvent(
                feature: "Semantic search",
                type: "search.run",
                summary: "Search strategy: \(run.strategy)",
                metadata: [
                    "query": run.query,
                    "intent": run.intent.rawValue,
                    "results": "\(run.resultCount)",
                    "latency_ms": "\(run.latencyMs)"
                ]
            )
        )
    }

    func logSearchFailure(query: String, error: Error) {
        database.logFeatureEvent(
            FeatureEvent(
                feature: "Semantic search",
                type: "search.error",
                summary: "Search failed",
                metadata: ["query": query, "error": error.localizedDescription]
            )
        )
    }
}
