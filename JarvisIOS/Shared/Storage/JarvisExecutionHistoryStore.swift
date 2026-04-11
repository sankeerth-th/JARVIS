import Foundation

public struct JarvisExecutionHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let conversationID: UUID
    public let intent: String
    public let mode: String
    public let modelLane: String?
    public let skillID: String?
    public let status: String
    public let summary: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        conversationID: UUID,
        intent: String,
        mode: String,
        modelLane: String? = nil,
        skillID: String? = nil,
        status: String,
        summary: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.conversationID = conversationID
        self.intent = intent
        self.mode = mode
        self.modelLane = modelLane
        self.skillID = skillID
        self.status = status
        self.summary = summary
    }
}

public final class JarvisExecutionHistoryStore {
    private struct StorePayload: Codable {
        var records: [JarvisExecutionHistoryRecord]
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "jarvis.phone.execution.history.store", qos: .utility)
    private let securityEnvelope: JarvisIOSSecurityEnvelope

    public init(filename: String = "JarvisExecutionHistory.json", securityEnvelope: JarvisIOSSecurityEnvelope = .shared) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = appSupport.appendingPathComponent("JarvisPhone", isDirectory: true)
        JarvisIOSStorageProtection.prepareSensitiveDirectory(directory)
        self.fileURL = directory.appendingPathComponent(filename)
        self.securityEnvelope = securityEnvelope
    }

    public func recent(limit: Int = 50) -> [JarvisExecutionHistoryRecord] {
        queue.sync {
            Array(loadPayload().records.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
        }
    }

    public func append(_ record: JarvisExecutionHistoryRecord, maxRecords: Int = 300) {
        queue.sync {
            var payload = loadPayload()
            payload.records.removeAll { $0.id == record.id }
            payload.records.insert(record, at: 0)
            payload.records = Array(payload.records.prefix(maxRecords))
            persist(payload)
        }
    }

    public func clear() {
        queue.sync {
            persist(StorePayload(records: []))
        }
    }

    private func loadPayload() -> StorePayload {
        guard let data = try? Data(contentsOf: fileURL) else {
            return StorePayload(records: [])
        }
        if let opened = try? securityEnvelope.open(data, purpose: fileURL.lastPathComponent),
           let decoded = try? JSONDecoder().decode(StorePayload.self, from: opened) {
            return decoded
        }
        if let decoded = try? JSONDecoder().decode(StorePayload.self, from: data) {
            return decoded
        }
        return StorePayload(records: [])
    }

    private func persist(_ payload: StorePayload) {
        guard let encoded = try? JSONEncoder().encode(payload),
              let sealed = try? securityEnvelope.seal(encoded, purpose: fileURL.lastPathComponent) else { return }
        try? sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
        JarvisIOSStorageProtection.protectSensitiveFile(at: fileURL)
    }
}
