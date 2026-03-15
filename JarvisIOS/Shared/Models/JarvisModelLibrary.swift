import Foundation

public enum JarvisModelFormat: String, Codable, CaseIterable {
    case gguf

    public var displayName: String {
        switch self {
        case .gguf:
            return "GGUF"
        }
    }
}

public enum JarvisModelRecordStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case invalid
    case unsupported
    case missing
    case failed

    public var displayName: String {
        switch self {
        case .ready:
            return "Ready"
        case .invalid:
            return "Invalid"
        case .unsupported:
            return "Unsupported"
        case .missing:
            return "Missing"
        case .failed:
            return "Failed"
        }
    }
}

public enum JarvisModelImportState: String, Codable, CaseIterable, Sendable {
    case imported
    case invalid
    case missing
    case failed

    public var displayName: String {
        switch self {
        case .imported:
            return "Imported"
        case .invalid:
            return "Invalid"
        case .missing:
            return "Missing"
        case .failed:
            return "Failed"
        }
    }
}

public enum JarvisModelActivationEligibility: String, Codable, CaseIterable, Sendable {
    case eligible
    case unsupportedProfile
    case accessLost
    case validationFailed

    public var displayName: String {
        switch self {
        case .eligible:
            return "Eligible"
        case .unsupportedProfile:
            return "Unverified"
        case .accessLost:
            return "Access Lost"
        case .validationFailed:
            return "Validation Failed"
        }
    }
}

public enum JarvisModelFamily: String, Codable, CaseIterable, Sendable {
    case gemma
    case llama
    case mistral
    case qwen
    case unknown

    public var displayName: String {
        switch self {
        case .gemma:
            return "Gemma"
        case .llama:
            return "Llama"
        case .mistral:
            return "Mistral"
        case .qwen:
            return "Qwen"
        case .unknown:
            return "Unknown"
        }
    }
}

public enum JarvisModelModality: String, Codable, CaseIterable, Sendable {
    case textOnly
    case multimodalCapable

    public var displayName: String {
        switch self {
        case .textOnly:
            return "Text"
        case .multimodalCapable:
            return "Multimodal"
        }
    }
}

public struct JarvisModelCapabilities: Codable, Equatable {
    public var supportsTextGeneration: Bool
    public var supportsVisionInputs: Bool
    public var requiresProjectorForVision: Bool

    public init(
        supportsTextGeneration: Bool = true,
        supportsVisionInputs: Bool = false,
        requiresProjectorForVision: Bool = false
    ) {
        self.supportsTextGeneration = supportsTextGeneration
        self.supportsVisionInputs = supportsVisionInputs
        self.requiresProjectorForVision = requiresProjectorForVision
    }
}

public enum JarvisImportedModelAssetRole: String, Codable {
    case primaryModel
    case projector
}

public enum JarvisModelAssetStorageKind: String, Codable {
    case securityScopedBookmark
    case sandboxCopy
}

public enum JarvisPersistedModelFileAccessStatus: String, Codable {
    case bookmarkCreated
    case accessPending
    case accessGranted
    case accessLost
    case bookmarkResolutionFailed
    case legacySandboxCopy

    public var displayName: String {
        switch self {
        case .bookmarkCreated:
            return "Bookmark Stored"
        case .accessPending:
            return "Access Pending"
        case .accessGranted:
            return "Access Granted"
        case .accessLost:
            return "Access Lost"
        case .bookmarkResolutionFailed:
            return "Bookmark Failed"
        case .legacySandboxCopy:
            return "Sandbox Copy"
        }
    }
}

public struct JarvisImportedModelAsset: Codable, Equatable {
    public var role: JarvisImportedModelAssetRole
    public var originalFilename: String
    public var resolvedFilename: String
    public var fileSizeBytes: Int64
    public var importedAt: Date
    public var storageKind: JarvisModelAssetStorageKind
    public var bookmarkData: Data?
    public var sandboxStoredFilename: String?
    public var lastResolvedPath: String?
    public var lastFileAccessStatus: JarvisPersistedModelFileAccessStatus
    public var lastFileAccessMessage: String?
    public var lastBookmarkRefreshAt: Date?

    public init(
        role: JarvisImportedModelAssetRole,
        originalFilename: String,
        resolvedFilename: String,
        fileSizeBytes: Int64,
        importedAt: Date = Date(),
        storageKind: JarvisModelAssetStorageKind,
        bookmarkData: Data? = nil,
        sandboxStoredFilename: String? = nil,
        lastResolvedPath: String? = nil,
        lastFileAccessStatus: JarvisPersistedModelFileAccessStatus = .bookmarkCreated,
        lastFileAccessMessage: String? = nil,
        lastBookmarkRefreshAt: Date? = nil
    ) {
        self.role = role
        self.originalFilename = originalFilename
        self.resolvedFilename = resolvedFilename
        self.fileSizeBytes = fileSizeBytes
        self.importedAt = importedAt
        self.storageKind = storageKind
        self.bookmarkData = bookmarkData
        self.sandboxStoredFilename = sandboxStoredFilename
        self.lastResolvedPath = lastResolvedPath
        self.lastFileAccessStatus = lastFileAccessStatus
        self.lastFileAccessMessage = lastFileAccessMessage
        self.lastBookmarkRefreshAt = lastBookmarkRefreshAt
    }
}

public struct JarvisImportedModel: Identifiable, Equatable {
    public var id: UUID
    public var displayName: String
    public var format: JarvisModelFormat
    public var supportedProfileID: JarvisSupportedModelProfileID?
    public var family: JarvisModelFamily
    public var modality: JarvisModelModality
    public var capabilities: JarvisModelCapabilities
    public var primaryAsset: JarvisImportedModelAsset
    public var projectorAsset: JarvisImportedModelAsset?
    public var importState: JarvisModelImportState
    public var activationEligibility: JarvisModelActivationEligibility
    public var status: JarvisModelRecordStatus
    public var statusMessage: String?
    public var lastValidationResult: String?
    public var lastActivationFailureReason: String?
    public var lastValidatedAt: Date
    public var lastFailureReason: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        format: JarvisModelFormat,
        supportedProfileID: JarvisSupportedModelProfileID? = nil,
        family: JarvisModelFamily,
        modality: JarvisModelModality,
        capabilities: JarvisModelCapabilities,
        primaryAsset: JarvisImportedModelAsset,
        projectorAsset: JarvisImportedModelAsset? = nil,
        importState: JarvisModelImportState,
        activationEligibility: JarvisModelActivationEligibility,
        status: JarvisModelRecordStatus,
        statusMessage: String?,
        lastValidationResult: String? = nil,
        lastActivationFailureReason: String? = nil,
        lastValidatedAt: Date = Date(),
        lastFailureReason: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.format = format
        self.supportedProfileID = supportedProfileID
        self.family = family
        self.modality = modality
        self.capabilities = capabilities
        self.primaryAsset = primaryAsset
        self.projectorAsset = projectorAsset
        self.importState = importState
        self.activationEligibility = activationEligibility
        self.status = status
        self.statusMessage = statusMessage
        self.lastValidationResult = lastValidationResult
        self.lastActivationFailureReason = lastActivationFailureReason
        self.lastValidatedAt = lastValidatedAt
        self.lastFailureReason = lastFailureReason
    }

    public var originalFilename: String { primaryAsset.originalFilename }
    public var resolvedFilename: String { primaryAsset.resolvedFilename }
    public var fileSizeBytes: Int64 { primaryAsset.fileSizeBytes }
    public var importedAt: Date { primaryAsset.importedAt }
    public var inferredFamily: String? { family == .unknown ? nil : family.displayName }
    public var hasProjectorAttached: Bool { projectorAsset != nil }
    public var canActivate: Bool { importState == .imported && activationEligibility == .eligible }

    public var visualReadinessDescription: String {
        guard capabilities.supportsVisionInputs else {
            return "Text-only model."
        }
        if capabilities.requiresProjectorForVision && projectorAsset == nil {
            if let expectedProjectorFilename {
                return "Attach \(expectedProjectorFilename) to enable future vision support."
            }
            return "Attach a projector GGUF to enable future vision support."
        }
        return "Projector attached. Visual runtime support can be added later."
    }

    public var expectedProjectorFilename: String? {
        guard family == .gemma, displayName.lowercased().contains("gemma-3") else { return nil }
        if displayName.lowercased().contains("4b") {
            return "mmproj-model-f16-4B.gguf"
        }
        return "mmproj-model-f16.gguf"
    }
}

extension JarvisImportedModel: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case format
        case supportedProfileID
        case family
        case modality
        case capabilities
        case primaryAsset
        case projectorAsset
        case importState
        case activationEligibility
        case status
        case statusMessage
        case lastValidationResult
        case lastActivationFailureReason
        case lastValidatedAt
        case lastFailureReason

        case originalFilename
        case storedFilename
        case fileSizeBytes
        case importedAt
        case inferredFamily
        case bookmarkData
        case lastResolvedPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        format = try container.decodeIfPresent(JarvisModelFormat.self, forKey: .format) ?? .gguf
        supportedProfileID = try container.decodeIfPresent(JarvisSupportedModelProfileID.self, forKey: .supportedProfileID)
        status = try container.decodeIfPresent(JarvisModelRecordStatus.self, forKey: .status) ?? .ready
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
        lastValidationResult = try container.decodeIfPresent(String.self, forKey: .lastValidationResult)
        lastActivationFailureReason = try container.decodeIfPresent(String.self, forKey: .lastActivationFailureReason)
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt) ?? Date()
        lastFailureReason = try container.decodeIfPresent(String.self, forKey: .lastFailureReason)

        if let primaryAsset = try container.decodeIfPresent(JarvisImportedModelAsset.self, forKey: .primaryAsset) {
            self.primaryAsset = primaryAsset
        } else {
            let originalFilename = try container.decode(String.self, forKey: .originalFilename)
            let storedFilename = try container.decodeIfPresent(String.self, forKey: .storedFilename)
            let bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
            let fileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes) ?? 0
            let importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
            let lastResolvedPath = try container.decodeIfPresent(String.self, forKey: .lastResolvedPath)

            let storageKind: JarvisModelAssetStorageKind = bookmarkData != nil ? .securityScopedBookmark : .sandboxCopy
            let accessStatus: JarvisPersistedModelFileAccessStatus = storageKind == .sandboxCopy ? .legacySandboxCopy : .bookmarkCreated

            self.primaryAsset = JarvisImportedModelAsset(
                role: .primaryModel,
                originalFilename: originalFilename,
                resolvedFilename: URL(fileURLWithPath: lastResolvedPath ?? originalFilename).lastPathComponent,
                fileSizeBytes: fileSizeBytes,
                importedAt: importedAt,
                storageKind: storageKind,
                bookmarkData: bookmarkData,
                sandboxStoredFilename: storedFilename,
                lastResolvedPath: lastResolvedPath,
                lastFileAccessStatus: accessStatus,
                lastFileAccessMessage: storageKind == .sandboxCopy ? "Sandbox copy stored in Jarvis app storage." : "Bookmark stored."
            )
        }

        projectorAsset = try container.decodeIfPresent(JarvisImportedModelAsset.self, forKey: .projectorAsset)

        if let family = try container.decodeIfPresent(JarvisModelFamily.self, forKey: .family) {
            self.family = family
        } else {
            let legacyFamily = try container.decodeIfPresent(String.self, forKey: .inferredFamily)
            self.family = Self.inferFamily(from: legacyFamily ?? displayName)
        }

        if let modality = try container.decodeIfPresent(JarvisModelModality.self, forKey: .modality) {
            self.modality = modality
        } else {
            self.modality = Self.inferModality(for: family, filename: displayName)
        }

        if let capabilities = try container.decodeIfPresent(JarvisModelCapabilities.self, forKey: .capabilities) {
            self.capabilities = capabilities
        } else {
            self.capabilities = Self.inferCapabilities(for: family, filename: displayName)
        }

        importState = try container.decodeIfPresent(JarvisModelImportState.self, forKey: .importState)
            ?? Self.importState(from: status)
        activationEligibility = try container.decodeIfPresent(
            JarvisModelActivationEligibility.self,
            forKey: .activationEligibility
        ) ?? Self.activationEligibility(
            from: status,
            supportedProfileID: supportedProfileID
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(format, forKey: .format)
        try container.encodeIfPresent(supportedProfileID, forKey: .supportedProfileID)
        try container.encode(family, forKey: .family)
        try container.encode(modality, forKey: .modality)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(primaryAsset, forKey: .primaryAsset)
        try container.encodeIfPresent(projectorAsset, forKey: .projectorAsset)
        try container.encode(importState, forKey: .importState)
        try container.encode(activationEligibility, forKey: .activationEligibility)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(statusMessage, forKey: .statusMessage)
        try container.encodeIfPresent(lastValidationResult, forKey: .lastValidationResult)
        try container.encodeIfPresent(lastActivationFailureReason, forKey: .lastActivationFailureReason)
        try container.encode(lastValidatedAt, forKey: .lastValidatedAt)
        try container.encodeIfPresent(lastFailureReason, forKey: .lastFailureReason)
    }

    fileprivate static func inferFamily(from filename: String) -> JarvisModelFamily {
        let lower = filename.lowercased()
        if lower.contains("gemma") { return .gemma }
        if lower.contains("llama") { return .llama }
        if lower.contains("mistral") { return .mistral }
        if lower.contains("qwen") { return .qwen }
        return .unknown
    }

    fileprivate static func inferModality(for family: JarvisModelFamily, filename: String) -> JarvisModelModality {
        let lower = filename.lowercased()
        if family == .gemma, lower.contains("gemma-3") {
            return .multimodalCapable
        }
        return .textOnly
    }

    fileprivate static func inferCapabilities(for family: JarvisModelFamily, filename: String) -> JarvisModelCapabilities {
        let lower = filename.lowercased()
        if family == .gemma, lower.contains("gemma-3") {
            return JarvisModelCapabilities(
                supportsTextGeneration: true,
                supportsVisionInputs: true,
                requiresProjectorForVision: true
            )
        }
        return JarvisModelCapabilities(supportsTextGeneration: true)
    }

    fileprivate static func importState(from status: JarvisModelRecordStatus) -> JarvisModelImportState {
        switch status {
        case .ready, .unsupported:
            return .imported
        case .invalid:
            return .invalid
        case .missing:
            return .missing
        case .failed:
            return .failed
        }
    }

    fileprivate static func activationEligibility(
        from status: JarvisModelRecordStatus,
        supportedProfileID: JarvisSupportedModelProfileID?
    ) -> JarvisModelActivationEligibility {
        switch status {
        case .ready, .unsupported:
            _ = supportedProfileID
            return .eligible
        case .invalid:
            return .validationFailed
        case .missing, .failed:
            return .accessLost
        }
    }
}

public enum JarvisModelLibraryError: LocalizedError {
    case unsupportedFormat(String)
    case unreadableFile
    case invalidGGUFHeader
    case selectedFileLooksLikeProjector
    case failedToCreateBookmark
    case modelNotFound
    case modelNotActivatable(String)
    case projectorNotSupported
    case projectorAlreadyAttached

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported model format '.\(ext)'. Jarvis currently supports GGUF files only."
        case .unreadableFile:
            return "The selected file could not be read."
        case .invalidGGUFHeader:
            return "The selected file is not a valid GGUF model."
        case .selectedFileLooksLikeProjector:
            return "This file looks like a projector GGUF. Import a text model first, then attach the projector from Model Library."
        case .failedToCreateBookmark:
            return "Jarvis could not create a persistent bookmark for this file."
        case .modelNotFound:
            return "That model record no longer exists."
        case .modelNotActivatable(let reason):
            return reason
        case .projectorNotSupported:
            return "This model does not currently need a projector companion."
        case .projectorAlreadyAttached:
            return "A projector file is already attached to this model."
        }
    }
}

public enum JarvisModelFileAccessError: LocalizedError {
    case missingBookmark(fileName: String)
    case bookmarkResolutionFailed(fileName: String, reason: String)
    case accessDenied(fileName: String)
    case fileMissing(fileName: String)
    case invalidResolvedFile(fileName: String)

    public var errorDescription: String? {
        switch self {
        case .missingBookmark(let fileName):
            return "Jarvis lost the persistent bookmark for \(fileName). Re-import the model."
        case .bookmarkResolutionFailed(let fileName, let reason):
            return "Jarvis could not resolve the bookmark for \(fileName): \(reason)"
        case .accessDenied(let fileName):
            return "Jarvis could not open \(fileName). Re-select the file from Files."
        case .fileMissing(let fileName):
            return "The model file \(fileName) is no longer available at its bookmarked location."
        case .invalidResolvedFile(let fileName):
            return "The resolved file for \(fileName) is not a valid GGUF model."
        }
    }
}

public final class JarvisModelLibrary {
    private struct Payload: Codable {
        var models: [JarvisImportedModel]
        var activeModelID: UUID?
    }

    private final class ResolvedAssetAccess {
        let url: URL
        private let stopAccess: () -> Void
        private var didRelease = false

        init(url: URL, stopAccess: @escaping () -> Void) {
            self.url = url
            self.stopAccess = stopAccess
        }

        func release() {
            guard !didRelease else { return }
            didRelease = true
            stopAccess()
        }

        deinit {
            release()
        }
    }

    public static let supportedExtensions: Set<String> = ["gguf"]

    private let queue = DispatchQueue(label: "jarvis.ios.model.library", qos: .utility)
    private let payloadURL: URL
    private let modelsDirectoryURL: URL
    private let legacyModelsDirectoryURL: URL

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        // The iOS SDK marks `.withSecurityScope` unavailable even though document-picker
        // bookmarks are still the persistence mechanism for security-scoped URLs.
        return []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope, .withoutUI]
        #else
        return []
        #endif
    }

    public init(payloadFilename: String = "JarvisModelLibrary.json") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = appSupport.appendingPathComponent("JarvisIOS", isDirectory: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let models = documents.appendingPathComponent("Models", isDirectory: true)
        let legacyModels = root.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        self.modelsDirectoryURL = models
        self.legacyModelsDirectoryURL = legacyModels
        self.payloadURL = root.appendingPathComponent(payloadFilename)
        migrateLegacySandboxDirectoryIfNeeded()
    }

    public func loadModels() -> [JarvisImportedModel] {
        queue.sync {
            var payload = loadPayload()
            migratePayloadToSandboxCopiesIfNeeded(&payload)
            return payload.models.sorted { $0.importedAt > $1.importedAt }
        }
    }

    public func activeModelID() -> UUID? {
        queue.sync {
            loadPayload().activeModelID
        }
    }

    public func activeModel() -> JarvisImportedModel? {
        queue.sync {
            var payload = loadPayload()
            migratePayloadToSandboxCopiesIfNeeded(&payload)
            guard let activeID = payload.activeModelID else { return nil }
            return payload.models.first(where: { $0.id == activeID })
        }
    }

    public func importModel(
        from sourceURL: URL,
        progress: ((Double, String) -> Void)? = nil
    ) throws -> JarvisImportedModel {
        try queue.sync {
            progress?(0.06, "Inspecting selected file")

            let inspected = try inspectImportFile(at: sourceURL, role: .primaryModel)
            if inspected.originalFilename.lowercased().contains("mmproj") {
                throw JarvisModelLibraryError.selectedFileLooksLikeProjector
            }

            progress?(0.42, "Copying model into app storage")
            let sourceFileSizeBytes = inspected.fileSizeBytes
            let sandboxStoredFilename = try copyImportedFileToSandbox(
                from: sourceURL,
                preferredFilename: inspected.originalFilename,
                expectedFileSizeBytes: sourceFileSizeBytes
            )
            let sandboxURL = modelsDirectoryURL.appendingPathComponent(sandboxStoredFilename, isDirectory: false)
            let copiedFileSize = fileSize(at: sandboxURL)
            guard copiedFileSize > 0 else {
                try? FileManager.default.removeItem(at: sandboxURL)
                throw JarvisModelLibraryError.unreadableFile
            }
            guard isValidGGUF(at: sandboxURL) else {
                try? FileManager.default.removeItem(at: sandboxURL)
                throw JarvisModelLibraryError.invalidGGUFHeader
            }

            let family = JarvisImportedModel.inferFamily(from: inspected.originalFilename)
            let modality = JarvisImportedModel.inferModality(for: family, filename: inspected.originalFilename)
            let capabilities = JarvisImportedModel.inferCapabilities(for: family, filename: inspected.originalFilename)
            let matchedProfile = JarvisSupportedModelCatalog.matchedProfile(
                filename: inspected.originalFilename,
                fileSizeBytes: inspected.fileSizeBytes,
                format: .gguf
            )
            let assessment = JarvisSupportedModelCatalog.assess(
                filename: inspected.originalFilename,
                fileSizeBytes: inspected.fileSizeBytes,
                format: .gguf
            )
            let activationEligibility: JarvisModelActivationEligibility = .eligible

            let accessMessage = activationMessage(
                displayName: inspected.displayName,
                capabilities: capabilities,
                projectorAttached: false,
                activationEligibility: activationEligibility
            )

            let asset = JarvisImportedModelAsset(
                role: .primaryModel,
                originalFilename: inspected.originalFilename,
                resolvedFilename: sandboxStoredFilename,
                fileSizeBytes: copiedFileSize,
                storageKind: .sandboxCopy,
                sandboxStoredFilename: sandboxStoredFilename,
                lastResolvedPath: modelsDirectoryURL
                    .appendingPathComponent(sandboxStoredFilename, isDirectory: false)
                    .path,
                lastFileAccessStatus: .legacySandboxCopy,
                lastFileAccessMessage: "Sandbox copy stored. Jarvis will load the model from local app storage."
            )

            let model = JarvisImportedModel(
                displayName: inspected.displayName,
                format: .gguf,
                supportedProfileID: matchedProfile?.id,
                family: family,
                modality: modality,
                capabilities: capabilities,
                primaryAsset: asset,
                importState: .imported,
                activationEligibility: activationEligibility,
                status: assessment.status,
                statusMessage: accessMessage,
                lastValidationResult: assessment.displayMessage
            )

            var payload = loadPayload()
            payload.models.insert(model, at: 0)
            persist(payload)

            progress?(1.0, "Model copied into app storage")
            return model
        }
    }

    public func attachProjector(
        from sourceURL: URL,
        to modelID: UUID,
        progress: ((Double, String) -> Void)? = nil
    ) throws -> JarvisImportedModel {
        try queue.sync {
            var payload = loadPayload()
            guard let index = payload.models.firstIndex(where: { $0.id == modelID }) else {
                throw JarvisModelLibraryError.modelNotFound
            }

            var model = payload.models[index]
            guard model.capabilities.supportsVisionInputs else {
                throw JarvisModelLibraryError.projectorNotSupported
            }
            guard model.projectorAsset == nil else {
                throw JarvisModelLibraryError.projectorAlreadyAttached
            }

            progress?(0.08, "Inspecting projector file")
            let inspected = try inspectImportFile(at: sourceURL, role: .projector)
            let sandboxStoredFilename = try copyImportedFileToSandbox(
                from: sourceURL,
                preferredFilename: inspected.originalFilename,
                expectedFileSizeBytes: inspected.fileSizeBytes
            )
            let sandboxURL = modelsDirectoryURL.appendingPathComponent(sandboxStoredFilename, isDirectory: false)
            let copiedFileSize = fileSize(at: sandboxURL)
            guard copiedFileSize > 0 else {
                try? FileManager.default.removeItem(at: sandboxURL)
                throw JarvisModelLibraryError.unreadableFile
            }
            guard isValidGGUF(at: sandboxURL) else {
                try? FileManager.default.removeItem(at: sandboxURL)
                throw JarvisModelLibraryError.invalidGGUFHeader
            }

            progress?(0.62, "Copying projector into app storage")
            model.projectorAsset = JarvisImportedModelAsset(
                role: .projector,
                originalFilename: inspected.originalFilename,
                resolvedFilename: sandboxStoredFilename,
                fileSizeBytes: copiedFileSize,
                storageKind: .sandboxCopy,
                sandboxStoredFilename: sandboxStoredFilename,
                lastResolvedPath: modelsDirectoryURL
                    .appendingPathComponent(sandboxStoredFilename, isDirectory: false)
                    .path,
                lastFileAccessStatus: .legacySandboxCopy,
                lastFileAccessMessage: "Projector copied into local app storage."
            )
            model.statusMessage = activationMessage(
                displayName: model.displayName,
                capabilities: model.capabilities,
                projectorAttached: true,
                activationEligibility: model.activationEligibility
            )
            model.lastValidatedAt = Date()
            payload.models[index] = model
            persist(payload)

            progress?(1.0, "Projector copied")
            return model
        }
    }

    public func activateModel(id: UUID) throws -> JarvisImportedModel {
        try queue.sync {
            var payload = loadPayload()
            guard let index = payload.models.firstIndex(where: { $0.id == id }) else {
                throw JarvisModelLibraryError.modelNotFound
            }

            var model = payload.models[index]
            revalidateModelRecord(&model)

            guard model.canActivate else {
                model.lastActivationFailureReason = model.statusMessage ?? activationBlockedMessage(for: model)
                payload.models[index] = model
                if payload.activeModelID == id {
                    payload.activeModelID = nil
                }
                persist(payload)
                throw JarvisModelLibraryError.modelNotActivatable(model.lastActivationFailureReason ?? "This model cannot be activated.")
            }

            model.lastActivationFailureReason = nil
            payload.models[index] = model
            payload.activeModelID = id
            persist(payload)
            return model
        }
    }

    public func setActiveModel(id: UUID) throws {
        _ = try activateModel(id: id)
    }

    public func clearActiveModel() {
        queue.sync {
            var payload = loadPayload()
            payload.activeModelID = nil
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
            removeSandboxCopyIfNeeded(for: model.primaryAsset)
            if let projectorAsset = model.projectorAsset {
                removeSandboxCopyIfNeeded(for: projectorAsset)
            }

            if payload.activeModelID == id {
                payload.activeModelID = nil
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
            revalidateModelRecord(&model)
            payload.models[index] = model

            if payload.activeModelID == model.id, !model.canActivate {
                payload.activeModelID = nil
            }

            persist(payload)
            return model
        }
    }

    public func runtimeSelection(for model: JarvisImportedModel) -> JarvisRuntimeModelSelection {
        JarvisRuntimeModelSelection(
            id: model.id,
            displayName: model.displayName,
            family: model.family,
            modality: model.modality,
            capabilities: model.capabilities,
            projectorAttached: model.projectorAsset != nil,
            inactiveAccessDetail: activationMessage(
                displayName: model.displayName,
                capabilities: model.capabilities,
                projectorAttached: model.projectorAsset != nil,
                activationEligibility: model.activationEligibility
            ),
            acquireResources: { [weak self] in
                guard let self else {
                    throw JarvisModelFileAccessError.bookmarkResolutionFailed(
                        fileName: model.originalFilename,
                        reason: "Model library was released."
                    )
                }
                return try self.acquireRuntimeResources(for: model.id)
            }
        )
    }

    public func supportedFormatText() -> String {
        "GGUF (.gguf)"
    }

    private func acquireRuntimeResources(for modelID: UUID) throws -> JarvisRuntimeResolvedModelResources {
        try queue.sync {
            var payload = loadPayload()
            migratePayloadToSandboxCopiesIfNeeded(&payload)
            guard let index = payload.models.firstIndex(where: { $0.id == modelID }) else {
                throw JarvisModelLibraryError.modelNotFound
            }

            var model = payload.models[index]
            var primaryAsset = model.primaryAsset
            let primaryAccess: ResolvedAssetAccess

            do {
                primaryAccess = try resolveAsset(&primaryAsset, modelName: model.displayName)
            } catch let accessError as JarvisModelFileAccessError {
                apply(accessError: accessError, to: &model)
                payload.models[index] = model
                persist(payload)
                throw accessError
            }

            var projectorAccess: ResolvedAssetAccess?
            if var projectorAsset = model.projectorAsset {
                do {
                    projectorAccess = try resolveAsset(&projectorAsset, modelName: model.displayName)
                    model.projectorAsset = projectorAsset
                } catch let accessError as JarvisModelFileAccessError {
                    apply(accessError: accessError, to: &projectorAsset)
                    model.projectorAsset = projectorAsset
                    model.statusMessage = "\(activationMessage(displayName: model.displayName, capabilities: model.capabilities, projectorAttached: false, activationEligibility: model.activationEligibility)) Projector issue: \(accessError.localizedDescription)"
                }
            }

            model.primaryAsset = primaryAsset
            model.statusMessage = activationMessage(
                displayName: model.displayName,
                capabilities: model.capabilities,
                projectorAttached: model.projectorAsset != nil,
                activationEligibility: model.activationEligibility
            )
            model.lastFailureReason = nil
            model.lastActivationFailureReason = nil
            model.lastValidatedAt = Date()
            payload.models[index] = model
            persist(payload)

            return JarvisRuntimeResolvedModelResources(
                modelURL: primaryAccess.url,
                projectorURL: projectorAccess?.url
            ) {
                primaryAccess.release()
                projectorAccess?.release()
            }
        }
    }

    private func inspectImportFile(at url: URL, role: JarvisImportedModelAssetRole) throws -> (
        displayName: String,
        originalFilename: String,
        fileSizeBytes: Int64
    ) {
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw JarvisModelLibraryError.unsupportedFormat(ext.isEmpty ? "unknown" : ext)
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .nameKey, .fileSizeKey])
        guard values.isRegularFile != false else {
            throw JarvisModelLibraryError.unreadableFile
        }

        let originalFilename = values.name ?? url.lastPathComponent
        if role == .primaryModel, originalFilename.lowercased().contains("mmproj") {
            throw JarvisModelLibraryError.selectedFileLooksLikeProjector
        }

        return (
            displayName: url.deletingPathExtension().lastPathComponent,
            originalFilename: originalFilename,
            fileSizeBytes: max(0, Int64(values.fileSize ?? 0))
        )
    }

    private func copyImportedFileToSandbox(
        from url: URL,
        preferredFilename: String,
        expectedFileSizeBytes: Int64? = nil
    ) throws -> String {
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let trimmedFilename = preferredFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationFilename = trimmedFilename.isEmpty ? url.lastPathComponent : trimmedFilename
        let destinationURL = modelsDirectoryURL.appendingPathComponent(destinationFilename, isDirectory: false)
        try? FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                throw JarvisModelLibraryError.unreadableFile
            }
            let copiedFileSize = fileSize(at: destinationURL)
            guard copiedFileSize > 0 else {
                throw JarvisModelLibraryError.unreadableFile
            }
            if let expectedFileSizeBytes, expectedFileSizeBytes > 0, copiedFileSize != expectedFileSizeBytes {
                throw JarvisModelLibraryError.unreadableFile
            }
            return destinationFilename
        } catch {
            throw JarvisModelLibraryError.unreadableFile
        }
    }

    private func resolveAsset(
        _ asset: inout JarvisImportedModelAsset,
        modelName: String
    ) throws -> ResolvedAssetAccess {
        switch asset.storageKind {
        case .sandboxCopy:
            guard let sandboxStoredFilename = asset.sandboxStoredFilename else {
                throw JarvisModelFileAccessError.fileMissing(fileName: asset.originalFilename)
            }

            let url = modelsDirectoryURL.appendingPathComponent(sandboxStoredFilename, isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw JarvisModelFileAccessError.fileMissing(fileName: asset.originalFilename)
            }

            asset.resolvedFilename = url.lastPathComponent
            asset.lastResolvedPath = url.path
            asset.lastFileAccessStatus = .accessGranted
            asset.lastFileAccessMessage = "Sandbox copy is accessible."
            return ResolvedAssetAccess(url: url, stopAccess: {})

        case .securityScopedBookmark:
            guard let bookmarkData = asset.bookmarkData else {
                throw JarvisModelFileAccessError.missingBookmark(fileName: asset.originalFilename)
            }

            var isStale = false
            let url: URL
            do {
                url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: Self.bookmarkResolutionOptions,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } catch {
                throw JarvisModelFileAccessError.bookmarkResolutionFailed(
                    fileName: asset.originalFilename,
                    reason: error.localizedDescription
                )
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw JarvisModelFileAccessError.fileMissing(fileName: asset.originalFilename)
            }

            guard url.startAccessingSecurityScopedResource() else {
                throw JarvisModelFileAccessError.accessDenied(fileName: asset.originalFilename)
            }

            if isStale {
                do {
                    asset.bookmarkData = try url.bookmarkData(
                        options: Self.bookmarkCreationOptions,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    asset.lastBookmarkRefreshAt = Date()
                } catch {
                    url.stopAccessingSecurityScopedResource()
                    throw JarvisModelFileAccessError.bookmarkResolutionFailed(
                        fileName: asset.originalFilename,
                        reason: "Bookmark is stale and could not be refreshed."
                    )
                }
            }

            guard isValidGGUF(at: url) else {
                url.stopAccessingSecurityScopedResource()
                throw JarvisModelFileAccessError.invalidResolvedFile(fileName: asset.originalFilename)
            }

            asset.resolvedFilename = url.lastPathComponent
            asset.lastResolvedPath = url.path
            asset.lastFileAccessStatus = .accessGranted
            asset.lastFileAccessMessage = "\(modelName) file access granted."

            return ResolvedAssetAccess(url: url) {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func apply(accessError: JarvisModelFileAccessError, to model: inout JarvisImportedModel) {
        switch accessError {
        case .missingBookmark, .bookmarkResolutionFailed:
            model.primaryAsset.lastFileAccessStatus = .bookmarkResolutionFailed
        case .accessDenied, .fileMissing:
            model.primaryAsset.lastFileAccessStatus = .accessLost
        case .invalidResolvedFile:
            model.primaryAsset.lastFileAccessStatus = .accessLost
        }

        model.primaryAsset.lastFileAccessMessage = accessError.localizedDescription
        model.importState = importState(for: accessError)
        model.activationEligibility = activationEligibility(for: accessError)
        model.lastValidationResult = accessError.localizedDescription
        model.lastActivationFailureReason = accessError.localizedDescription
        model.lastFailureReason = accessError.localizedDescription

        switch accessError {
        case .fileMissing:
            model.status = .missing
        case .invalidResolvedFile:
            model.status = .invalid
        case .missingBookmark, .bookmarkResolutionFailed, .accessDenied:
            model.status = .failed
        }

        model.statusMessage = accessError.localizedDescription
    }

    private func apply(accessError: JarvisModelFileAccessError, to asset: inout JarvisImportedModelAsset) {
        switch accessError {
        case .missingBookmark, .bookmarkResolutionFailed:
            asset.lastFileAccessStatus = .bookmarkResolutionFailed
        case .accessDenied, .fileMissing, .invalidResolvedFile:
            asset.lastFileAccessStatus = .accessLost
        }
        asset.lastFileAccessMessage = accessError.localizedDescription
    }

    private func activationMessage(
        displayName: String,
        capabilities: JarvisModelCapabilities,
        projectorAttached: Bool,
        activationEligibility: JarvisModelActivationEligibility
    ) -> String {
        if activationEligibility == .unsupportedProfile {
            return "This GGUF import needs review before activation. Revalidate the file or try importing it again."
        }

        if capabilities.supportsVisionInputs && capabilities.requiresProjectorForVision && !projectorAttached {
            return "\(displayName) is text-ready. Attach the projector GGUF later to enable future visual input."
        }
        return "Imported and validated. Activate this model explicitly, then warm it before your first message."
    }

    private func removeSandboxCopyIfNeeded(for asset: JarvisImportedModelAsset) {
        guard asset.storageKind == .sandboxCopy,
              let sandboxStoredFilename = asset.sandboxStoredFilename else { return }

        let fileURL = modelsDirectoryURL.appendingPathComponent(sandboxStoredFilename, isDirectory: false)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return max(0, Int64(values?.fileSize ?? 0))
    }

    private func isValidGGUF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4) else { return false }
        return header == Data("GGUF".utf8)
    }

    private func revalidateModelRecord(_ model: inout JarvisImportedModel) {
        do {
            var primaryAsset = model.primaryAsset
            let primaryAccess = try resolveAsset(&primaryAsset, modelName: model.displayName)
            defer { primaryAccess.release() }

            guard isValidGGUF(at: primaryAccess.url) else {
                throw JarvisModelFileAccessError.invalidResolvedFile(fileName: model.originalFilename)
            }

            let assessment = JarvisSupportedModelCatalog.assess(
                filename: primaryAsset.originalFilename,
                fileSizeBytes: fileSize(at: primaryAccess.url),
                format: model.format
            )

            model.primaryAsset = primaryAsset
            model.primaryAsset.fileSizeBytes = fileSize(at: primaryAccess.url)
            model.supportedProfileID = assessment.supportedProfileID
            model.importState = .imported
            model.activationEligibility = .eligible
            model.status = assessment.status
            model.statusMessage = activationMessage(
                displayName: model.displayName,
                capabilities: model.capabilities,
                projectorAttached: model.projectorAsset != nil,
                activationEligibility: model.activationEligibility
            )
            model.lastValidationResult = assessment.displayMessage
            model.lastFailureReason = nil
            model.lastActivationFailureReason = nil

            if var projectorAsset = model.projectorAsset {
                do {
                    let projectorAccess = try resolveAsset(&projectorAsset, modelName: model.displayName)
                    defer { projectorAccess.release() }
                    projectorAsset.fileSizeBytes = fileSize(at: projectorAccess.url)
                    model.projectorAsset = projectorAsset
                } catch let projectorError as JarvisModelFileAccessError {
                    apply(accessError: projectorError, to: &projectorAsset)
                    model.projectorAsset = projectorAsset
                    model.statusMessage = "\(model.statusMessage ?? assessment.displayMessage) Projector issue: \(projectorError.localizedDescription)"
                }
            }
        } catch let accessError as JarvisModelFileAccessError {
            apply(accessError: accessError, to: &model)
        } catch {
            model.importState = .failed
            model.activationEligibility = .validationFailed
            model.status = .failed
            model.statusMessage = error.localizedDescription
            model.lastValidationResult = error.localizedDescription
            model.lastActivationFailureReason = error.localizedDescription
            model.lastFailureReason = error.localizedDescription
        }

        model.lastValidatedAt = Date()
    }

    private func activationBlockedMessage(for model: JarvisImportedModel) -> String {
        switch model.activationEligibility {
        case .eligible:
            return model.statusMessage ?? "This model is not ready to activate."
        case .unsupportedProfile:
            return model.statusMessage ?? "This GGUF import needs review before activation."
        case .accessLost:
            return model.statusMessage ?? "Jarvis lost access to this imported file. Revalidate or re-import it."
        case .validationFailed:
            return model.statusMessage ?? "This model failed validation and cannot be activated."
        }
    }

    private func importState(for accessError: JarvisModelFileAccessError) -> JarvisModelImportState {
        switch accessError {
        case .invalidResolvedFile:
            return .invalid
        case .fileMissing:
            return .missing
        case .missingBookmark, .bookmarkResolutionFailed, .accessDenied:
            return .failed
        }
    }

    private func activationEligibility(for accessError: JarvisModelFileAccessError) -> JarvisModelActivationEligibility {
        switch accessError {
        case .invalidResolvedFile:
            return .validationFailed
        case .missingBookmark, .bookmarkResolutionFailed, .accessDenied, .fileMissing:
            return .accessLost
        }
    }

    private func loadPayload() -> Payload {
        guard let data = try? Data(contentsOf: payloadURL),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload(models: [], activeModelID: nil)
        }
        return decoded
    }

    private func migrateLegacySandboxDirectoryIfNeeded() {
        guard FileManager.default.fileExists(atPath: legacyModelsDirectoryURL.path) else { return }
        let legacyFiles = (try? FileManager.default.contentsOfDirectory(
            at: legacyModelsDirectoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        for legacyFile in legacyFiles where !FileManager.default.fileExists(atPath: modelsDirectoryURL.appendingPathComponent(legacyFile.lastPathComponent).path) {
            try? FileManager.default.copyItem(
                at: legacyFile,
                to: modelsDirectoryURL.appendingPathComponent(legacyFile.lastPathComponent, isDirectory: false)
            )
        }
    }

    private func migratePayloadToSandboxCopiesIfNeeded(_ payload: inout Payload) {
        var didChange = false
        for index in payload.models.indices {
            if migrateModelToSandboxIfNeeded(&payload.models[index]) {
                didChange = true
            }
        }
        if didChange {
            persist(payload)
        }
    }

    private func migrateModelToSandboxIfNeeded(_ model: inout JarvisImportedModel) -> Bool {
        var didChange = false
        if migrateAssetToSandboxIfNeeded(&model.primaryAsset, modelName: model.displayName) {
            didChange = true
        }
        if var projectorAsset = model.projectorAsset {
            if migrateAssetToSandboxIfNeeded(&projectorAsset, modelName: model.displayName) {
                model.projectorAsset = projectorAsset
                didChange = true
            }
        }
        if didChange {
            model.lastValidatedAt = Date()
            model.statusMessage = activationMessage(
                displayName: model.displayName,
                capabilities: model.capabilities,
                projectorAttached: model.projectorAsset != nil,
                activationEligibility: model.activationEligibility
            )
        }
        return didChange
    }

    private func migrateAssetToSandboxIfNeeded(
        _ asset: inout JarvisImportedModelAsset,
        modelName: String
    ) -> Bool {
        guard asset.storageKind != .sandboxCopy else {
            if let lastResolvedPath = asset.lastResolvedPath,
               lastResolvedPath.hasPrefix(legacyModelsDirectoryURL.path),
               let sandboxStoredFilename = asset.sandboxStoredFilename {
                let destinationURL = modelsDirectoryURL.appendingPathComponent(sandboxStoredFilename, isDirectory: false)
                if !FileManager.default.fileExists(atPath: destinationURL.path),
                   FileManager.default.fileExists(atPath: lastResolvedPath) {
                    try? FileManager.default.copyItem(at: URL(fileURLWithPath: lastResolvedPath), to: destinationURL)
                }
                asset.lastResolvedPath = destinationURL.path
                asset.resolvedFilename = destinationURL.lastPathComponent
                asset.lastFileAccessStatus = .legacySandboxCopy
                asset.lastFileAccessMessage = "\(modelName) is stored in local app sandbox."
                return true
            }
            return false
        }

        do {
            let access = try resolveAsset(&asset, modelName: modelName)
            defer { access.release() }
            let destinationFilename = try copyImportedFileToSandbox(
                from: access.url,
                preferredFilename: asset.originalFilename,
                expectedFileSizeBytes: fileSize(at: access.url)
            )
            let destinationURL = modelsDirectoryURL.appendingPathComponent(destinationFilename, isDirectory: false)
            asset.storageKind = .sandboxCopy
            asset.bookmarkData = nil
            asset.sandboxStoredFilename = destinationFilename
            asset.resolvedFilename = destinationFilename
            asset.lastResolvedPath = destinationURL.path
            asset.fileSizeBytes = fileSize(at: destinationURL)
            asset.lastFileAccessStatus = .legacySandboxCopy
            asset.lastFileAccessMessage = "Migrated into local app sandbox storage."
            asset.lastBookmarkRefreshAt = nil
            return true
        } catch {
            return false
        }
    }

    private func persist(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: payloadURL, options: [.atomic])
    }
}
