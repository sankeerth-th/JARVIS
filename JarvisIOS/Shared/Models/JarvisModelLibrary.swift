import Foundation

public enum JarvisModelFormat: String, Codable, CaseIterable {
    case gguf

    public var displayName: String {
        switch self {
        case .gguf: return "GGUF"
        }
    }
}

public enum JarvisModelRecordStatus: String, Codable, CaseIterable {
    case ready
    case invalid
    case unsupported
    case missing
    case failed

    public var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .invalid: return "Invalid"
        case .unsupported: return "Unsupported"
        case .missing: return "Missing"
        case .failed: return "Failed"
        }
    }
}

public struct JarvisImportedModel: Identifiable, Codable, Equatable {
    public var id: UUID
    public var displayName: String
    public var originalFilename: String
    public var storedFilename: String
    public var fileSizeBytes: Int64
    public var importedAt: Date
    public var format: JarvisModelFormat
    public var inferredFamily: String?
    public var status: JarvisModelRecordStatus
    public var statusMessage: String?
    public var lastValidatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        originalFilename: String,
        storedFilename: String,
        fileSizeBytes: Int64,
        importedAt: Date = Date(),
        format: JarvisModelFormat,
        inferredFamily: String?,
        status: JarvisModelRecordStatus,
        statusMessage: String?,
        lastValidatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.fileSizeBytes = fileSizeBytes
        self.importedAt = importedAt
        self.format = format
        self.inferredFamily = inferredFamily
        self.status = status
        self.statusMessage = statusMessage
        self.lastValidatedAt = lastValidatedAt
    }
}

public enum JarvisModelLibraryError: LocalizedError {
    case unsupportedFormat(String)
    case unreadableFile
    case failedToCopy
    case modelNotFound
    case modelNotReady

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported model format '.\(ext)'. Jarvis currently supports GGUF files only."
        case .unreadableFile:
            return "The selected file could not be read."
        case .failedToCopy:
            return "Jarvis could not import this model file."
        case .modelNotFound:
            return "That model record no longer exists."
        case .modelNotReady:
            return "Only models with Ready status can be set active."
        }
    }
}

public final class JarvisModelLibrary {
    private struct Payload: Codable {
        var models: [JarvisImportedModel]
        var activeModelID: UUID?
    }

    public static let supportedExtensions: Set<String> = ["gguf"]

    private let queue = DispatchQueue(label: "jarvis.ios.model.library", qos: .utility)
    private let payloadURL: URL
    private let modelsDirectoryURL: URL

    public init(payloadFilename: String = "JarvisModelLibrary.json") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = appSupport.appendingPathComponent("JarvisIOS", isDirectory: true)
        let models = root.appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: models.path) {
            try? FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        }
        self.modelsDirectoryURL = models
        self.payloadURL = root.appendingPathComponent(payloadFilename)
    }

    public func loadModels() -> [JarvisImportedModel] {
        queue.sync {
            loadPayload().models.sorted { $0.importedAt > $1.importedAt }
        }
    }

    public func activeModelID() -> UUID? {
        queue.sync {
            loadPayload().activeModelID
        }
    }

    public func activeModel() -> JarvisImportedModel? {
        queue.sync {
            let payload = loadPayload()
            guard let activeID = payload.activeModelID else { return nil }
            return payload.models.first(where: { $0.id == activeID })
        }
    }

    public func modelFileURL(for model: JarvisImportedModel) -> URL {
        modelsDirectoryURL.appendingPathComponent(model.storedFilename, isDirectory: false)
    }

    public func importModel(
        from sourceURL: URL,
        progress: ((Double, String) -> Void)? = nil
    ) throws -> JarvisImportedModel {
        try queue.sync {
            let didStartSecurityScope = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartSecurityScope {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            progress?(0.08, "Inspecting file")
            let ext = sourceURL.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                throw JarvisModelLibraryError.unsupportedFormat(ext.isEmpty ? "unknown" : ext)
            }

            let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .nameKey, .fileSizeKey])
            guard values.isRegularFile != false else {
                throw JarvisModelLibraryError.unreadableFile
            }

            let originalFilename = values.name ?? sourceURL.lastPathComponent
            let inferredFamily = Self.inferFamily(from: originalFilename)
            let displayName = sourceURL.deletingPathExtension().lastPathComponent

            let id = UUID()
            let storedFilename = "\(id.uuidString).\(ext)"
            let destination = modelsDirectoryURL.appendingPathComponent(storedFilename, isDirectory: false)

            progress?(0.42, "Importing model")
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                throw JarvisModelLibraryError.failedToCopy
            }

            progress?(0.82, "Validating")
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? Int64(values.fileSize ?? 0)
            var status: JarvisModelRecordStatus = .ready
            var message: String?
            if size <= 0 {
                status = .invalid
                message = "Model file appears empty."
            }

            var payload = loadPayload()
            let model = JarvisImportedModel(
                id: id,
                displayName: displayName,
                originalFilename: originalFilename,
                storedFilename: storedFilename,
                fileSizeBytes: max(0, size),
                format: .gguf,
                inferredFamily: inferredFamily,
                status: status,
                statusMessage: message
            )
            payload.models.insert(model, at: 0)

            if payload.activeModelID == nil || payload.models.first(where: { $0.id == payload.activeModelID }) == nil {
                payload.activeModelID = model.status == .ready ? model.id : payload.models.first(where: { $0.status == .ready })?.id
            }

            persist(payload)
            progress?(1.0, "Import complete")
            return model
        }
    }

    public func setActiveModel(id: UUID) throws {
        try queue.sync {
            var payload = loadPayload()
            guard let model = payload.models.first(where: { $0.id == id }) else {
                throw JarvisModelLibraryError.modelNotFound
            }
            guard model.status == .ready else {
                throw JarvisModelLibraryError.modelNotReady
            }
            payload.activeModelID = id
            persist(payload)
        }
    }

    public func removeModel(id: UUID) throws {
        try queue.sync {
            var payload = loadPayload()
            guard let index = payload.models.firstIndex(where: { $0.id == id }) else {
                throw JarvisModelLibraryError.modelNotFound
            }
            let model = payload.models.remove(at: index)
            let fileURL = modelFileURL(for: model)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }

            if payload.activeModelID == id {
                payload.activeModelID = payload.models.first(where: { $0.status == .ready })?.id
            }
            persist(payload)
        }
    }

    public func revalidateModel(id: UUID) throws -> JarvisImportedModel {
        try queue.sync {
            var payload = loadPayload()
            guard let index = payload.models.firstIndex(where: { $0.id == id }) else {
                throw JarvisModelLibraryError.modelNotFound
            }

            var model = payload.models[index]
            let fileURL = modelFileURL(for: model)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                model.status = .missing
                model.statusMessage = "Model file is missing. Re-import required."
            } else if model.format != .gguf {
                model.status = .unsupported
                model.statusMessage = "Only GGUF is supported right now."
            } else {
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                model.fileSizeBytes = max(0, size)
                if size <= 0 {
                    model.status = .invalid
                    model.statusMessage = "Model file appears empty."
                } else {
                    model.status = .ready
                    model.statusMessage = nil
                }
            }
            model.lastValidatedAt = Date()
            payload.models[index] = model

            if payload.activeModelID == model.id, model.status != .ready {
                payload.activeModelID = payload.models.first(where: { $0.status == .ready })?.id
            }

            persist(payload)
            return model
        }
    }

    public func supportedFormatText() -> String {
        "GGUF (.gguf)"
    }

    private func loadPayload() -> Payload {
        guard let data = try? Data(contentsOf: payloadURL),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload(models: [], activeModelID: nil)
        }
        return decoded
    }

    private func persist(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: payloadURL, options: [.atomic])
    }

    private static func inferFamily(from filename: String) -> String? {
        let lower = filename.lowercased()
        if lower.contains("gemma") { return "Gemma" }
        if lower.contains("llama") { return "Llama" }
        if lower.contains("mistral") { return "Mistral" }
        if lower.contains("qwen") { return "Qwen" }
        return nil
    }
}
