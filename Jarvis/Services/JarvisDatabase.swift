import Foundation
import SQLite3

final class JarvisDatabase {
    private let url: URL
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.jarvis.database")

    init(filename: String = "Jarvis.sqlite") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "~/Library/Application Support", isDirectory: true)
        let directory = appSupport.appendingPathComponent("Jarvis", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
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
    }

    private func migrate() {
        let statements = [
            "CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, title TEXT, model TEXT, createdAt REAL, updatedAt REAL, payload BLOB)",
            "CREATE TABLE IF NOT EXISTS macros (id TEXT PRIMARY KEY, name TEXT, payload BLOB)",
            "CREATE TABLE IF NOT EXISTS indexed_documents (id TEXT PRIMARY KEY, title TEXT, path TEXT UNIQUE, embedding BLOB, extractedText TEXT DEFAULT '', lastModified REAL, lastIndexed REAL)",
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
                sqlite3_bind_blob(statement, 6, (data as NSData).bytes, Int32(data.count), SQLITE_TRANSIENT)
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
                    messages = (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
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
                sqlite3_bind_blob(statement, 3, (data as NSData).bytes, Int32(data.count), SQLITE_TRANSIENT)
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
                    steps = (try? JSONDecoder().decode([MacroStep].self, from: data)) ?? []
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
            sqlite3_bind_text(statement, 5, doc.extractedText, -1, SQLITE_TRANSIENT)
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
                let extractedText = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
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

    func logFeatureEvent(_ event: FeatureEvent) {
        queue.sync {
            let sql = "REPLACE INTO feature_events (id, feature, type, summary, metadata, createdAt) VALUES (?,?,?,?,?,?)"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, event.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, event.feature, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, event.type, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, event.summary, -1, SQLITE_TRANSIENT)
            if let metadata = try? JSONEncoder().encode(event.metadata) {
                sqlite3_bind_blob(statement, 5, (metadata as NSData).bytes, Int32(metadata.count), SQLITE_TRANSIENT)
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
                    metadata = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
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
            sqlite3_bind_text(statement, 2, title, -1, SQLITE_TRANSIENT)
            if let payload = try? JSONEncoder().encode(items) {
                sqlite3_bind_blob(statement, 3, (payload as NSData).bytes, Int32(payload.count), SQLITE_TRANSIENT)
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
            sqlite3_bind_text(statement, 2, session.title, -1, SQLITE_TRANSIENT)
            if let payload = try? JSONEncoder().encode(session) {
                sqlite3_bind_blob(statement, 3, (payload as NSData).bytes, Int32(payload.count), SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_text(statement, 4, session.summary, -1, SQLITE_TRANSIENT)
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
                if let decoded = try? JSONDecoder().decode(ThinkingSessionRecord.self, from: data) {
                    sessions.append(decoded)
                }
            }
            sqlite3_finalize(statement)
            return sessions
        }
    }
}
