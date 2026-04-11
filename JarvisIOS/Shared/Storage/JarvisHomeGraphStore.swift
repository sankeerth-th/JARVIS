import Foundation

public struct JarvisHomeNode: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case home
        case room
        case accessory
        case service
        case scene
    }

    public let id: UUID
    public let kind: Kind
    public let name: String
    public let vendorID: String?
    public let parentID: UUID?
    public let capabilities: [String]
    public let aliases: [String]
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        name: String,
        vendorID: String? = nil,
        parentID: UUID? = nil,
        capabilities: [String] = [],
        aliases: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.vendorID = vendorID
        self.parentID = parentID
        self.capabilities = capabilities
        self.aliases = aliases
        self.updatedAt = updatedAt
    }
}

public final class JarvisHomeGraphStore {
    private struct StorePayload: Codable {
        var nodes: [JarvisHomeNode]
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "jarvis.phone.home.graph.store", qos: .utility)
    private let securityEnvelope: JarvisIOSSecurityEnvelope

    public init(filename: String = "JarvisHomeGraph.json", securityEnvelope: JarvisIOSSecurityEnvelope = .shared) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = appSupport.appendingPathComponent("JarvisPhone", isDirectory: true)
        JarvisIOSStorageProtection.prepareSensitiveDirectory(directory)
        self.fileURL = directory.appendingPathComponent(filename)
        self.securityEnvelope = securityEnvelope
    }

    public func loadNodes() -> [JarvisHomeNode] {
        queue.sync {
            loadPayload().nodes.sorted { lhs, rhs in
                if lhs.kind == rhs.kind {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
        }
    }

    public func replaceAll(with nodes: [JarvisHomeNode]) {
        queue.sync {
            persist(StorePayload(nodes: nodes))
        }
    }

    public func clear() {
        queue.sync {
            persist(StorePayload(nodes: []))
        }
    }

    public func search(query: String, limit: Int = 20) -> [JarvisHomeNode] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        return loadNodes()
            .filter { node in
                node.name.lowercased().contains(normalized) ||
                node.aliases.contains(where: { $0.lowercased().contains(normalized) }) ||
                node.capabilities.contains(where: { $0.lowercased().contains(normalized) })
            }
            .prefix(limit)
            .map { $0 }
    }

    private func loadPayload() -> StorePayload {
        guard let data = try? Data(contentsOf: fileURL) else {
            return StorePayload(nodes: [])
        }
        if let opened = try? securityEnvelope.open(data, purpose: fileURL.lastPathComponent),
           let decoded = try? JSONDecoder().decode(StorePayload.self, from: opened) {
            return decoded
        }
        if let decoded = try? JSONDecoder().decode(StorePayload.self, from: data) {
            return decoded
        }
        return StorePayload(nodes: [])
    }

    private func persist(_ payload: StorePayload) {
        guard let encoded = try? JSONEncoder().encode(payload),
              let sealed = try? securityEnvelope.seal(encoded, purpose: fileURL.lastPathComponent) else { return }
        try? sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
        JarvisIOSStorageProtection.protectSensitiveFile(at: fileURL)
    }
}
