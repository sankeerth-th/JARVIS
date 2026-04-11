import Foundation
import SQLite3

final class JarvisDatabase {
    private let url: URL
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.jarvis.database")
    private let securityEnvelope = JarvisSecurityEnvelope.shared

    init(filename: String = "Jarvis.sqlite") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Jarvis", isDirectory: true)
        
        // Create directory with proper error handling
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fatalError("Failed to create database directory: \(error)")
        }
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(directoryValues)
        
        url = directory.appendingPathComponent(filename)
        open()
        migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func open() {
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            assertionFailure("Unable to open database")
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private func migrate() {
        let statements = [
            "CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, title TEXT, model TEXT, createdAt REAL, updatedAt REAL, payload BLOB)",
            "CREATE TABLE IF NOT EXISTS macros (id TEXT PRIMARY KEY, name TEXT, payload BLOB)",
            "CREATE TABLE IF NOT EXISTS indexed_documents (id TEXT PRIMARY KEY, title TEXT, path TEXT UNIQUE, embedding BLOB, extractedText TEXT DEFAULT '', lastModified REAL, lastIndexed REAL)",
            "CREATE TABLE IF NOT EXISTS index_meta (key TEXT PRIMARY KEY, value TEXT)",
            "CREATE TABLE IF NOT EXISTS indexed_files_v2 (id TEXT PRIMARY KEY, title TEXT, path TEXT UNIQUE, filename TEXT, fileExtension TEXT, sourceType TEXT, category TEXT, contentHash TEXT, fileSize INTEGER, createdAt REAL, modifiedAt REAL, lastIndexed REAL, pageCount INTEGER, ocrConfidence REAL, indexVersion INTEGER, embeddingModel TEXT, embeddingDim INTEGER)",
            "CREATE TABLE IF NOT EXISTS indexed_chunks_v2 (id TEXT PRIMARY KEY, fileID TEXT NOT NULL, ordinal INTEGER, page INTEGER, chunkHash TEXT, text TEXT, normalizedText TEXT, embedding BLOB, embeddingModel TEXT, embeddingDim INTEGER, FOREIGN KEY(fileID) REFERENCES indexed_files_v2(id) ON DELETE CASCADE)",
            "CREATE INDEX IF NOT EXISTS idx_indexed_chunks_v2_fileID ON indexed_chunks_v2(fileID)",
            "CREATE INDEX IF NOT EXISTS idx_indexed_chunks_v2_chunkHash ON indexed_chunks_v2(chunkHash)",
            "CREATE VIRTUAL TABLE IF NOT EXISTS indexed_chunks_fts_v2 USING fts5(chunkID UNINDEXED, fileID UNINDEXED, title, path, text, normalizedText)",
            "CREATE TABLE IF NOT EXISTS search_runs_v2 (id TEXT PRIMARY KEY, query TEXT, intent TEXT, strategy TEXT, resultCount INTEGER, latencyMs INTEGER, debugSummary TEXT, createdAt REAL)",
            "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value BLOB)",
            "CREATE TABLE IF NOT EXISTS feature_events (id TEXT PRIMARY KEY, feature TEXT, type TEXT, summary TEXT, metadata BLOB, createdAt REAL)",
            "CREATE TABLE IF NOT EXISTS checklists (id TEXT PRIMARY KEY, title TEXT, items BLOB, createdAt REAL)",
            "CREATE TABLE IF NOT EXISTS thinking_sessions (id TEXT PRIMARY KEY, title TEXT, payload BLOB, summary TEXT, createdAt REAL, updatedAt REAL)"
        ]
        for stmt in statements {
            sqlite3_exec(db, stmt, nil, nil, nil)
        }
        let alterStatements = [
            "ALTER TABLE indexed_documents ADD COLUMN extractedText TEXT DEFAULT ''",
            "ALTER TABLE indexed_documents ADD COLUMN lastModified REAL"
        ]
        for stmt in alterStatements {
            sqlite3_exec(db, stmt, nil, nil, nil)
        }
    }

    func saveConversation(_ conversation: Conversation) {
        queue.sync {
            let sql = "REPLACE INTO conversations (id, title, model, createdAt, updatedAt, payload) VALUES (?,?,?,?,?,?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, conversation.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, conversation.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, conversation.model, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 4, conversation.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 5, conversation.updatedAt.timeIntervalSince1970)
            if let data = try? JSONEncoder().encode(conversation.messages) {
                bindEncryptedBlob(data, to: statement, index: 6, purpose: "conversation.payload")
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func loadConversations(limit: Int = 30) -> [Conversation] {
        queue.sync {
            var conversations: [Conversation] = []
            let sql = "SELECT id, title, model, createdAt, updatedAt, payload FROM conversations ORDER BY updatedAt DESC LIMIT ?"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idC = sqlite3_column_text(statement, 0),
                      let titleC = sqlite3_column_text(statement, 1),
                      let modelC = sqlite3_column_text(statement, 2) else { continue }
                let id = UUID(uuidString: String(cString: idC)) ?? UUID()
                let title = String(cString: titleC)
                let model = String(cString: modelC)
                let created = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                let updated = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                var messages: [ChatMessage] = []
                if let blobPointer = sqlite3_column_blob(statement, 5) {
                    let length = Int(sqlite3_column_bytes(statement, 5))
                    let data = Data(bytes: blobPointer, count: length)
                    let payload = openEncryptedBlob(data, purpose: "conversation.payload") ?? data
                    messages = (try? JSONDecoder().decode([ChatMessage].self, from: payload)) ?? []
                }
                let conversation = Conversation(id: id, title: title, model: model, createdAt: created, updatedAt: updated, messages: messages)
                conversations.append(conversation)
            }
            sqlite3_finalize(statement)
            return conversations
        }
    }

    func deleteHistory() {
        queue.sync {
            sqlite3_exec(db, "DELETE FROM conversations", nil, nil, nil)
        }
    }

    func saveMacro(_ macro: Macro) {
        queue.sync {
            let sql = "REPLACE INTO macros (id, name, payload) VALUES (?,?,?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, macro.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, macro.name, -1, SQLITE_TRANSIENT)
            if let data = try? JSONEncoder().encode(macro.steps) {
                bindEncryptedBlob(data, to: statement, index: 3, purpose: "macro.payload")
            }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func loadMacros() -> [Macro] {
        queue.sync {
            var macros: [Macro] = []
            let sql = "SELECT id, name, payload FROM macros ORDER BY name ASC"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(statement, 0),
                      let nameText = sqlite3_column_text(statement, 1) else { continue }
                let id = UUID(uuidString: String(cString: idText)) ?? UUID()
                let name = String(cString: nameText)
                var steps: [MacroStep] = []
                if let blobPointer = sqlite3_column_blob(statement, 2) {
                    let length = Int(sqlite3_column_bytes(statement, 2))
                    let data = Data(bytes: blobPointer, count: length)
                    let payload = openEncryptedBlob(data, purpose: "macro.payload") ?? data
                    steps = (try? JSONDecoder().decode([MacroStep].self, from: payload)) ?? []
                }
                macros.append(Macro(id: id, name: name, steps: steps))
            }
            sqlite3_finalize(statement)
            return macros
        }
    }

    func deleteMacro(id: UUID) {
        queue.sync {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM macros WHERE id = ?", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func saveIndexedDocument(_ doc: IndexedDocument) {
        queue.sync {
            let sql = "REPLACE INTO indexed_documents (id, title, path, embedding, extractedText, lastModified, lastIndexed) VALUES (?,?,?,?,?,?,?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, doc.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, doc.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, doc.path, -1, SQLITE_TRANSIENT)
            if let data = try? JSONEncoder().encode(doc.embedding) {
                sqlite3_bind_blob(statement, 4, (data as NSData).bytes, Int32(data.count), SQLITE_TRANSIENT)
            }
            bindEncryptedText(doc.extractedText, to: statement, index: 5, purpose: "indexed.document.extractedText")
            if let lastModified = doc.lastModified {
                sqlite3_bind_double(statement, 6, lastModified.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_double(statement, 7, doc.lastIndexed.timeIntervalSince1970)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func loadIndexedDocuments(limit: Int = 50) -> [IndexedDocument] {
        queue.sync {
            var docs: [IndexedDocument] = []
            let sql = "SELECT id, title, path, embedding, extractedText, lastModified, lastIndexed FROM indexed_documents ORDER BY lastIndexed DESC LIMIT ?"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(statement, 0),
                      let titleText = sqlite3_column_text(statement, 1),
                      let pathText = sqlite3_column_text(statement, 2) else { continue }
                let id = UUID(uuidString: String(cString: idText)) ?? UUID()
                let title = String(cString: titleText)
                let path = String(cString: pathText)
                var embedding: [Double] = []
                if let blobPointer = sqlite3_column_blob(statement, 3) {
                    let length = Int(sqlite3_column_bytes(statement, 3))
                    let data = Data(bytes: blobPointer, count: length)
                    embedding = (try? JSONDecoder().decode([Double].self, from: data)) ?? []
                }
                let extractedText = loadEncryptedText(from: statement, index: 4, purpose: "indexed.document.extractedText") ?? ""
                let lastModified: Date?
                if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                    lastModified = nil
                } else {
                    lastModified = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                }
                let lastIndexed = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                docs.append(IndexedDocument(id: id, title: title, path: path, embedding: embedding, extractedText: extractedText, lastModified: lastModified, lastIndexed: lastIndexed))
            }
            sqlite3_finalize(statement)
            return docs
        }
    }

    func deleteIndexedDocument(path: String) {
        queue.sync {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM indexed_documents WHERE path = ?", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func searchIndexVersion() -> Int? {
        queue.sync {
            let sql = "SELECT value FROM index_meta WHERE key = 'search_index_version'"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let value = sqlite3_column_text(statement, 0) else {
                return nil
            }
            return Int(String(cString: value))
        }
    }

    func setSearchIndexVersion(_ version: Int) {
        queue.sync {
            let sql = "REPLACE INTO index_meta (key, value) VALUES ('search_index_version', ?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, String(version), -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func clearSearchIndexV2() {
        queue.sync {
            sqlite3_exec(db, "DELETE FROM indexed_chunks_fts_v2", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM indexed_chunks_v2", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM indexed_files_v2", nil, nil, nil)
        }
    }

    func countIndexedFilesV2() -> Int {
        queue.sync {
            let sql = "SELECT COUNT(*) FROM indexed_files_v2"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    func loadIndexedFileV2(path: String) -> IndexedFileRecord? {
        queue.sync {
            let sql = """
            SELECT id, title, path, filename, fileExtension, sourceType, category, contentHash, fileSize, createdAt, modifiedAt, lastIndexed, pageCount, ocrConfidence, indexVersion, embeddingModel, embeddingDim
            FROM indexed_files_v2
            WHERE path = ?
            LIMIT 1
            """
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return decodeIndexedFileV2(from: statement)
        }
    }

    func loadIndexedFilesV2(limit: Int = 10_000) -> [IndexedFileRecord] {
        queue.sync {
            var results: [IndexedFileRecord] = []
            let sql = """
            SELECT id, title, path, filename, fileExtension, sourceType, category, contentHash, fileSize, createdAt, modifiedAt, lastIndexed, pageCount, ocrConfidence, indexVersion, embeddingModel, embeddingDim
            FROM indexed_files_v2
            ORDER BY lastIndexed DESC
            LIMIT ?
            """
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                if let record = decodeIndexedFileV2(from: statement) {
                    results.append(record)
                }
            }
            sqlite3_finalize(statement)
            return results
        }
    }

    func upsertIndexedFileV2(_ file: IndexedFileRecord) {
        queue.sync {
            let sql = """
            REPLACE INTO indexed_files_v2 (
                id, title, path, filename, fileExtension, sourceType, category, contentHash, fileSize,
                createdAt, modifiedAt, lastIndexed, pageCount, ocrConfidence, indexVersion, embeddingModel, embeddingDim
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, file.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, file.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, file.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, file.filename, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, file.fileExtension, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 6, file.sourceType, -1, SQLITE_TRANSIENT)
            if let category = file.category {
                sqlite3_bind_text(statement, 7, category, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 7)
            }
            sqlite3_bind_text(statement, 8, file.contentHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 9, sqlite3_int64(file.fileSize))
            if let created = file.createdAt {
                sqlite3_bind_double(statement, 10, created.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            if let modified = file.modifiedAt {
                sqlite3_bind_double(statement, 11, modified.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 11)
            }
            sqlite3_bind_double(statement, 12, file.lastIndexed.timeIntervalSince1970)
            if let pageCount = file.pageCount {
                sqlite3_bind_int(statement, 13, Int32(pageCount))
            } else {
                sqlite3_bind_null(statement, 13)
            }
            if let confidence = file.ocrConfidence {
                sqlite3_bind_double(statement, 14, confidence)
            } else {
                sqlite3_bind_null(statement, 14)
            }
            sqlite3_bind_int(statement, 15, Int32(file.indexVersion))
            if let embeddingModel = file.embeddingModel {
                sqlite3_bind_text(statement, 16, embeddingModel, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 16)
            }
            if let embeddingDim = file.embeddingDim {
                sqlite3_bind_int(statement, 17, Int32(embeddingDim))
            } else {
                sqlite3_bind_null(statement, 17)
            }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func replaceChunksV2(fileID: UUID, chunks: [IndexedChunkRecord]) {
        queue.sync {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM indexed_chunks_v2 WHERE fileID = ?", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, fileID.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)

            sqlite3_prepare_v2(db, "DELETE FROM indexed_chunks_fts_v2 WHERE fileID = ?", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, fileID.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)

            let sql = """
            INSERT INTO indexed_chunks_v2 (id, fileID, ordinal, page, chunkHash, text, normalizedText, embedding, embeddingModel, embeddingDim)
            VALUES (?,?,?,?,?,?,?,?,?,?)
            """
            let ftsSQL = "INSERT INTO indexed_chunks_fts_v2 (chunkID, fileID, title, path, text, normalizedText) VALUES (?,?,?,?,?,?)"
            var title = ""
            var path = ""
            sqlite3_prepare_v2(db, "SELECT title, path FROM indexed_files_v2 WHERE id = ?", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, fileID.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                title = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                path = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            }
            sqlite3_finalize(statement)

            for chunk in chunks {
                sqlite3_prepare_v2(db, sql, -1, &statement, nil)
                sqlite3_bind_text(statement, 1, chunk.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, chunk.fileID.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(statement, 3, Int32(chunk.ordinal))
                if let page = chunk.page {
                    sqlite3_bind_int(statement, 4, Int32(page))
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                sqlite3_bind_text(statement, 5, chunk.chunkHash, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, chunk.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 7, chunk.normalizedText, -1, SQLITE_TRANSIENT)
                if let embedding = chunk.embedding, let data = try? JSONEncoder().encode(embedding) {
                    sqlite3_bind_blob(statement, 8, (data as NSData).bytes, Int32(data.count), SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 8)
                }
                if let model = chunk.embeddingModel {
                    sqlite3_bind_text(statement, 9, model, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 9)
                }
                if let dim = chunk.embeddingDim {
                    sqlite3_bind_int(statement, 10, Int32(dim))
                } else {
                    sqlite3_bind_null(statement, 10)
                }
                sqlite3_step(statement)
                sqlite3_finalize(statement)

                sqlite3_prepare_v2(db, ftsSQL, -1, &statement, nil)
                sqlite3_bind_text(statement, 1, chunk.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, chunk.fileID.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, path, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, chunk.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, chunk.normalizedText, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    func searchChunkCandidatesV2(matchQuery: String, rootFolders: [String]?, limit: Int) -> [SearchChunkCandidate] {
        queue.sync {
            guard !matchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            var results: [SearchChunkCandidate] = []
            let sql = """
            SELECT
                c.id, c.fileID, c.ordinal, c.page, c.chunkHash, c.text, c.normalizedText, c.embedding, c.embeddingModel, c.embeddingDim,
                f.id, f.title, f.path, f.filename, f.fileExtension, f.sourceType, f.category, f.contentHash, f.fileSize, f.createdAt, f.modifiedAt, f.lastIndexed, f.pageCount, f.ocrConfidence, f.indexVersion, f.embeddingModel, f.embeddingDim,
                bm25(indexed_chunks_fts_v2)
            FROM indexed_chunks_fts_v2
            JOIN indexed_chunks_v2 c ON c.id = indexed_chunks_fts_v2.chunkID
            JOIN indexed_files_v2 f ON f.id = c.fileID
            WHERE indexed_chunks_fts_v2 MATCH ?
            ORDER BY bm25(indexed_chunks_fts_v2)
            LIMIT ?
            """
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, matchQuery, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let chunk = decodeIndexedChunkV2(from: statement, offset: 0),
                      let file = decodeIndexedFileV2(from: statement, offset: 10) else {
                    continue
                }
                let bm25Score = sqlite3_column_double(statement, 27)
                let lexical = 1.0 / (1.0 + max(0.0, bm25Score))
                if !isPathAllowed(file.path, roots: rootFolders) {
                    continue
                }
                results.append(SearchChunkCandidate(file: file, chunk: chunk, lexicalScore: lexical))
            }
            sqlite3_finalize(statement)
            return results
        }
    }

    func loadAllChunkCandidatesV2(rootFolders: [String]?, limit: Int) -> [SearchChunkCandidate] {
        queue.sync {
            var results: [SearchChunkCandidate] = []
            let sql = """
            SELECT
                c.id, c.fileID, c.ordinal, c.page, c.chunkHash, c.text, c.normalizedText, c.embedding, c.embeddingModel, c.embeddingDim,
                f.id, f.title, f.path, f.filename, f.fileExtension, f.sourceType, f.category, f.contentHash, f.fileSize, f.createdAt, f.modifiedAt, f.lastIndexed, f.pageCount, f.ocrConfidence, f.indexVersion, f.embeddingModel, f.embeddingDim
            FROM indexed_chunks_v2 c
            JOIN indexed_files_v2 f ON f.id = c.fileID
            ORDER BY f.lastIndexed DESC, c.ordinal ASC
            LIMIT ?
            """
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let chunk = decodeIndexedChunkV2(from: statement, offset: 0),
                      let file = decodeIndexedFileV2(from: statement, offset: 10) else {
                    continue
                }
                if !isPathAllowed(file.path, roots: rootFolders) {
                    continue
                }
                results.append(SearchChunkCandidate(file: file, chunk: chunk, lexicalScore: 0))
            }
            sqlite3_finalize(statement)
            return results
        }
    }

    func saveSearchRunV2(_ run: SearchRunRecord) {
        queue.sync {
            let sql = "REPLACE INTO search_runs_v2 (id, query, intent, strategy, resultCount, latencyMs, debugSummary, createdAt) VALUES (?,?,?,?,?,?,?,?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, UUID().uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, JarvisSecurityRedactor.redact(run.query), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, run.intent.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, run.strategy, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 5, Int32(run.resultCount))
            sqlite3_bind_int(statement, 6, Int32(run.latencyMs))
            sqlite3_bind_text(statement, 7, JarvisSecurityRedactor.redact(run.debugSummary), -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 8, run.createdAt.timeIntervalSince1970)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    private func isPathAllowed(_ path: String, roots: [String]?) -> Bool {
        guard let roots, !roots.isEmpty else { return true }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return roots.contains { root in
            let standardizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
            return standardizedPath.hasPrefix(standardizedRoot + "/") || standardizedPath == standardizedRoot
        }
    }

    private func decodeIndexedChunkV2(from statement: OpaquePointer?, offset: Int) -> IndexedChunkRecord? {
        guard let idText = sqlite3_column_text(statement, Int32(offset)),
              let fileIDText = sqlite3_column_text(statement, Int32(offset + 1)),
              let chunkHashText = sqlite3_column_text(statement, Int32(offset + 4)),
              let text = sqlite3_column_text(statement, Int32(offset + 5)),
              let normalized = sqlite3_column_text(statement, Int32(offset + 6)) else {
            return nil
        }
        let id = UUID(uuidString: String(cString: idText)) ?? UUID()
        let fileID = UUID(uuidString: String(cString: fileIDText)) ?? UUID()
        let ordinal = Int(sqlite3_column_int(statement, Int32(offset + 2)))
        let page: Int?
        if sqlite3_column_type(statement, Int32(offset + 3)) == SQLITE_NULL {
            page = nil
        } else {
            page = Int(sqlite3_column_int(statement, Int32(offset + 3)))
        }
        var embedding: [Double]? = nil
        if let blob = sqlite3_column_blob(statement, Int32(offset + 7)) {
            let length = Int(sqlite3_column_bytes(statement, Int32(offset + 7)))
            let data = Data(bytes: blob, count: length)
            embedding = try? JSONDecoder().decode([Double].self, from: data)
        }
        let embeddingModel = sqlite3_column_text(statement, Int32(offset + 8)).map { String(cString: $0) }
        let embeddingDim: Int?
        if sqlite3_column_type(statement, Int32(offset + 9)) == SQLITE_NULL {
            embeddingDim = nil
        } else {
            embeddingDim = Int(sqlite3_column_int(statement, Int32(offset + 9)))
        }
        return IndexedChunkRecord(
            id: id,
            fileID: fileID,
            ordinal: ordinal,
            page: page,
            chunkHash: String(cString: chunkHashText),
            text: String(cString: text),
            normalizedText: String(cString: normalized),
            embedding: embedding,
            embeddingModel: embeddingModel,
            embeddingDim: embeddingDim
        )
    }

    private func decodeIndexedFileV2(from statement: OpaquePointer?, offset: Int = 0) -> IndexedFileRecord? {
        guard let idText = sqlite3_column_text(statement, Int32(offset)),
              let titleText = sqlite3_column_text(statement, Int32(offset + 1)),
              let pathText = sqlite3_column_text(statement, Int32(offset + 2)),
              let filenameText = sqlite3_column_text(statement, Int32(offset + 3)),
              let extensionText = sqlite3_column_text(statement, Int32(offset + 4)),
              let sourceTypeText = sqlite3_column_text(statement, Int32(offset + 5)),
              let contentHashText = sqlite3_column_text(statement, Int32(offset + 7)) else {
            return nil
        }
        let id = UUID(uuidString: String(cString: idText)) ?? UUID()
        let category = sqlite3_column_text(statement, Int32(offset + 6)).map { String(cString: $0) }
        let fileSize = Int64(sqlite3_column_int64(statement, Int32(offset + 8)))
        let createdAt: Date?
        if sqlite3_column_type(statement, Int32(offset + 9)) == SQLITE_NULL {
            createdAt = nil
        } else {
            createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, Int32(offset + 9)))
        }
        let modifiedAt: Date?
        if sqlite3_column_type(statement, Int32(offset + 10)) == SQLITE_NULL {
            modifiedAt = nil
        } else {
            modifiedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, Int32(offset + 10)))
        }
        let lastIndexed = Date(timeIntervalSince1970: sqlite3_column_double(statement, Int32(offset + 11)))
        let pageCount: Int?
        if sqlite3_column_type(statement, Int32(offset + 12)) == SQLITE_NULL {
            pageCount = nil
        } else {
            pageCount = Int(sqlite3_column_int(statement, Int32(offset + 12)))
        }
        let ocrConfidence: Double?
        if sqlite3_column_type(statement, Int32(offset + 13)) == SQLITE_NULL {
            ocrConfidence = nil
        } else {
            ocrConfidence = sqlite3_column_double(statement, Int32(offset + 13))
        }
        let indexVersion = Int(sqlite3_column_int(statement, Int32(offset + 14)))
        let embeddingModel = sqlite3_column_text(statement, Int32(offset + 15)).map { String(cString: $0) }
        let embeddingDim: Int?
        if sqlite3_column_type(statement, Int32(offset + 16)) == SQLITE_NULL {
            embeddingDim = nil
        } else {
            embeddingDim = Int(sqlite3_column_int(statement, Int32(offset + 16)))
        }
        return IndexedFileRecord(
            id: id,
            title: String(cString: titleText),
            path: String(cString: pathText),
            filename: String(cString: filenameText),
            fileExtension: String(cString: extensionText),
            sourceType: String(cString: sourceTypeText),
            category: category,
            contentHash: String(cString: contentHashText),
            fileSize: fileSize,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            lastIndexed: lastIndexed,
            pageCount: pageCount,
            ocrConfidence: ocrConfidence,
            indexVersion: indexVersion,
            embeddingModel: embeddingModel,
            embeddingDim: embeddingDim
        )
    }

    func logFeatureEvent(_ event: FeatureEvent) {
        queue.sync {
            let sql = "REPLACE INTO feature_events (id, feature, type, summary, metadata, createdAt) VALUES (?,?,?,?,?,?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            let redactedSummary = JarvisSecurityRedactor.redact(event.summary)
            let redactedMetadata = JarvisSecurityRedactor.redact(metadata: event.metadata)
            sqlite3_bind_text(statement, 1, event.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, event.feature, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, event.type, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, redactedSummary, -1, SQLITE_TRANSIENT)
            if let metadata = try? JSONEncoder().encode(redactedMetadata) {
                bindEncryptedBlob(metadata, to: statement, index: 5, purpose: "feature.metadata")
            } else {
                sqlite3_bind_null(statement, 5)
            }
            sqlite3_bind_double(statement, 6, event.createdAt.timeIntervalSince1970)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func loadFeatureEvents(limit: Int = 50, feature: String? = nil, since: Date? = nil) -> [FeatureEvent] {
        queue.sync {
            var events: [FeatureEvent] = []
            var predicates: [String] = []
            if feature != nil { predicates.append("feature = ?") }
            if since != nil { predicates.append("createdAt >= ?") }
            let whereClause = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
            let sql = "SELECT id, feature, type, summary, metadata, createdAt FROM feature_events\(whereClause) ORDER BY createdAt DESC LIMIT ?"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            var bindIndex: Int32 = 1
            if let feature {
                sqlite3_bind_text(statement, bindIndex, feature, -1, SQLITE_TRANSIENT)
                bindIndex += 1
            }
            if let since {
                sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970)
                bindIndex += 1
            }
            sqlite3_bind_int(statement, bindIndex, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(statement, 0),
                      let featureText = sqlite3_column_text(statement, 1),
                      let typeText = sqlite3_column_text(statement, 2),
                      let summaryText = sqlite3_column_text(statement, 3) else { continue }
                let id = UUID(uuidString: String(cString: idText)) ?? UUID()
                var metadata: [String: String] = [:]
                if let blobPointer = sqlite3_column_blob(statement, 4) {
                    let length = Int(sqlite3_column_bytes(statement, 4))
                    let data = Data(bytes: blobPointer, count: length)
                    let payload = openEncryptedBlob(data, purpose: "feature.metadata") ?? data
                    metadata = (try? JSONDecoder().decode([String: String].self, from: payload)) ?? [:]
                }
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                events.append(
                    FeatureEvent(
                        id: id,
                        feature: String(cString: featureText),
                        type: String(cString: typeText),
                        summary: String(cString: summaryText),
                        metadata: metadata,
                        createdAt: createdAt
                    )
                )
            }
            sqlite3_finalize(statement)
            return events
        }
    }

    func lastFeatureRunDate(feature: String) -> Date? {
        queue.sync {
            let sql = "SELECT MAX(createdAt) FROM feature_events WHERE feature = ?"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, feature, -1, SQLITE_TRANSIENT)
            let step = sqlite3_step(statement)
            defer { sqlite3_finalize(statement) }
            guard step == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
            return Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
        }
    }

    @discardableResult
    func saveChecklist(title: String, items: [String]) -> UUID {
        let id = UUID()
        queue.sync {
            let sql = "REPLACE INTO checklists (id, title, items, createdAt) VALUES (?,?,?,?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, JarvisSecurityRedactor.redact(title), -1, SQLITE_TRANSIENT)
            if let payload = try? JSONEncoder().encode(items) {
                bindEncryptedBlob(payload, to: statement, index: 3, purpose: "checklist.items")
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        return id
    }

    func saveThinkingSession(_ session: ThinkingSessionRecord) {
        queue.sync {
            let sql = "REPLACE INTO thinking_sessions (id, title, payload, summary, createdAt, updatedAt) VALUES (?,?,?,?,?,?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, session.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, JarvisSecurityRedactor.redact(session.title), -1, SQLITE_TRANSIENT)
            if let payload = try? JSONEncoder().encode(session) {
                bindEncryptedBlob(payload, to: statement, index: 3, purpose: "thinking.payload")
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_text(statement, 4, JarvisSecurityRedactor.redact(session.summary), -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 5, session.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 6, session.updatedAt.timeIntervalSince1970)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func loadThinkingSessions(limit: Int = 20) -> [ThinkingSessionRecord] {
        queue.sync {
            var sessions: [ThinkingSessionRecord] = []
            let sql = "SELECT payload FROM thinking_sessions ORDER BY updatedAt DESC LIMIT ?"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let payload = sqlite3_column_blob(statement, 0) else { continue }
                let length = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: payload, count: length)
                let decrypted = openEncryptedBlob(data, purpose: "thinking.payload") ?? data
                if let decoded = try? JSONDecoder().decode(ThinkingSessionRecord.self, from: decrypted) {
                    sessions.append(decoded)
                }
            }
            sqlite3_finalize(statement)
            return sessions
        }
    }

    private func bindEncryptedBlob(_ data: Data, to statement: OpaquePointer?, index: Int32, purpose: String) {
        let payload = (try? securityEnvelope.seal(data, purpose: purpose)) ?? data
        sqlite3_bind_blob(statement, index, (payload as NSData).bytes, Int32(payload.count), SQLITE_TRANSIENT)
    }

    private func openEncryptedBlob(_ data: Data, purpose: String) -> Data? {
        try? securityEnvelope.open(data, purpose: purpose)
    }

    private func bindEncryptedText(_ text: String, to statement: OpaquePointer?, index: Int32, purpose: String) {
        guard let data = text.data(using: .utf8) else {
            sqlite3_bind_null(statement, index)
            return
        }
        let payload = (try? securityEnvelope.seal(data, purpose: purpose)) ?? data
        let encoded = "enc:" + payload.base64EncodedString()
        sqlite3_bind_text(statement, index, encoded, -1, SQLITE_TRANSIENT)
    }

    private func loadEncryptedText(from statement: OpaquePointer?, index: Int32, purpose: String) -> String? {
        guard let raw = sqlite3_column_text(statement, index).map({ String(cString: $0) }) else {
            return nil
        }
        if raw.hasPrefix("enc:"),
           let decoded = Data(base64Encoded: String(raw.dropFirst(4))),
           let opened = try? securityEnvelope.open(decoded, purpose: purpose),
           let string = String(data: opened, encoding: .utf8) {
            return string
        }
        return raw
    }
}
