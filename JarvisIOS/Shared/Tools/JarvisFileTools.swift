import Foundation

private enum JarvisFileToolEnvironment {
    static let accessManager = JarvisFileAccessManager()
    static let searchService = JarvisFileSearchService(accessManager: accessManager)
    static let readService = JarvisFileReadService(accessManager: accessManager)
    static let patchService = JarvisFilePatchService(accessManager: accessManager)
    static let createService = JarvisFileCreateService(accessManager: accessManager)
}

struct JarvisAllowedRootsListTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "file.allowed_roots.list",
        displayName: "Allowed Roots List",
        capability: "file.allowed_roots.list",
        riskLevel: .low,
        auditCategory: "filesystem"
    )

    private let accessManager: JarvisFileAccessManager

    init(accessManager: JarvisFileAccessManager = JarvisFileToolEnvironment.accessManager) {
        self.accessManager = accessManager
    }

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        _ = invocation
        let response = JarvisAllowedRootsListResponse(roots: accessManager.allowedDirectoryRecords())
        return JarvisToolResult(
            status: .success,
            userMessage: "Loaded \(response.roots.count) approved root\(response.roots.count == 1 ? "" : "s").",
            rawResult: encode(response),
            retryable: false,
            verificationState: .verified
        )
    }
}

struct JarvisAllowedRootAddTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "file.allowed_roots.add",
        displayName: "Allowed Root Add",
        capability: "file.allowed_roots.add",
        riskLevel: .medium,
        auditCategory: "filesystem"
    )

    private let accessManager: JarvisFileAccessManager

    init(accessManager: JarvisFileAccessManager = JarvisFileToolEnvironment.accessManager) {
        self.accessManager = accessManager
    }

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        guard let path = invocation.arguments.requiredString("path") else {
            return failureResult(message: "Unable to add approved root.", detail: "missing path")
        }
        let alreadyAllowed = accessManager.isPathAllowed(path)
        guard let url = accessManager.addAllowedDirectory(URL(fileURLWithPath: path)) else {
            return failureResult(message: "Unable to add approved root.", detail: "invalid directory")
        }
        let response = JarvisAllowedRootAddResponse(
            root: JarvisAllowedDirectoryRecord(url: url),
            added: !alreadyAllowed,
            validationState: "allowed"
        )
        return JarvisToolResult(
            status: .success,
            userMessage: response.added ? "Approved root added." : "Approved root already present.",
            rawResult: encode(response),
            retryable: false,
            verificationState: .verified
        )
    }
}

struct JarvisFilePathValidateTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "file.path.validate",
        displayName: "File Path Validate",
        capability: "file.path.validate",
        riskLevel: .low,
        auditCategory: "filesystem"
    )

    private let accessManager: JarvisFileAccessManager

    init(accessManager: JarvisFileAccessManager = JarvisFileToolEnvironment.accessManager) {
        self.accessManager = accessManager
    }

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        guard let path = invocation.arguments.requiredString("path") else {
            return failureResult(message: "Unable to validate path.", detail: "missing path")
        }
        let response = accessManager.validatePath(path)
        return JarvisToolResult(
            status: .success,
            userMessage: response.allowed ? "Path is allowed." : "Path is not allowed.",
            rawResult: encode(response),
            retryable: false,
            verificationState: .verified
        )
    }
}

struct JarvisFileSearchTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "file.search",
        displayName: "File Search",
        capability: "file.search",
        riskLevel: .low,
        auditCategory: "filesystem"
    )

    private let service: JarvisFileSearchService

    init(service: JarvisFileSearchService = JarvisFileToolEnvironment.searchService) {
        self.service = service
    }

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        guard let query = invocation.arguments.requiredString("query") else {
            return failureResult(message: "Unable to search files.", detail: "missing query")
        }
        let limit = max(1, min(invocation.arguments.intValue("limit") ?? 20, 50))
        let results = service.searchFiles(query: query, limit: limit)
            let response = JarvisFileSearchResponse(query: query, results: results)
            return JarvisToolResult(
                status: .success,
                userMessage: results.isEmpty
                    ? "No files matched \"\(query)\"."
                    : "Found \(results.count) file\(results.count == 1 ? "" : "s") for \"\(query)\".",
                rawResult: encode(response),
                retryable: false,
                verificationState: .verified
            )
    }
}

struct JarvisFileReadTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "file.read",
        displayName: "File Read",
        capability: "file.read",
        riskLevel: .low,
        auditCategory: "filesystem"
    )

    private let service: JarvisFileReadService

    init(service: JarvisFileReadService = JarvisFileToolEnvironment.readService) {
        self.service = service
    }

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        do {
            guard let path = invocation.arguments.requiredString("path") else {
                return failureResult(message: "Unable to read file.", detail: "missing path")
            }
            let response = try service.readFile(path: path)
            return JarvisToolResult(
                status: .success,
                userMessage: response.truncated ? "File loaded with truncation." : "File loaded.",
                rawResult: encode(response),
                retryable: false,
                verificationState: .verified
            )
        } catch {
            return failureResult(message: "Unable to read file.", error: error)
        }
    }
}

struct JarvisFilePreviewTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "file.preview",
        displayName: "File Preview",
        capability: "file.preview",
        riskLevel: .low,
        auditCategory: "filesystem"
    )

    private let service: JarvisFileReadService

    init(service: JarvisFileReadService = JarvisFileToolEnvironment.readService) {
        self.service = service
    }

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        do {
            guard let path = invocation.arguments.requiredString("path") else {
                return failureResult(message: "Unable to preview file.", detail: "missing path")
            }
            let maxLength = max(1, min(invocation.arguments.intValue("max_length") ?? 2_000, 20_000))
            let response = try service.previewFile(path: path, maxLength: maxLength)
            return JarvisToolResult(
                status: .success,
                userMessage: response.truncated ? "File preview loaded with truncation." : "File preview loaded.",
                rawResult: encode(response),
                retryable: false,
                verificationState: .verified
            )
        } catch {
            return failureResult(message: "Unable to preview file.", error: error)
        }
    }
}

struct JarvisFilePatchTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "file.patch",
        displayName: "File Patch",
        capability: "file.patch",
        riskLevel: .medium,
        auditCategory: "filesystem"
    )

    private let patchService: JarvisFilePatchService
    private let accessManager: JarvisFileAccessManager

    init(
        patchService: JarvisFilePatchService = JarvisFileToolEnvironment.patchService,
        accessManager: JarvisFileAccessManager = JarvisFileToolEnvironment.accessManager
    ) {
        self.patchService = patchService
        self.accessManager = accessManager
    }

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        do {
            guard let path = invocation.arguments.requiredString("path") else {
                return failureResult(message: "Unable to apply patch.", detail: "missing path")
            }
            guard accessManager.isPathAllowed(path) else {
                return failureResult(message: "Unable to apply patch.", detail: "accessDenied")
            }
            let current = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            let original = invocation.arguments.stringValue("original_content") ?? current
            guard let updated = invocation.arguments.requiredString("updated_content") else {
                return failureResult(message: "Unable to apply patch.", detail: "missing updated_content")
            }
            let patch = patchService.generatePatch(original: original, updated: updated)
            let approved = invocation.arguments.boolValue("approved") ?? false
            let response = approved
                ? try patchService.applyPatch(path: path, patch: patch)
                : try patchService.previewPatch(path: path, patch: patch)
            return JarvisToolResult(
                status: .success,
                userMessage: response.applied
                    ? "Patch applied."
                    : (response.canApply ? "Patch preview ready. Approval required." : "Patch preview ready, but the file changed and cannot be applied."),
                rawResult: encode(response),
                retryable: false,
                verificationState: response.applied ? .verified : .unverified
            )
        } catch {
            return failureResult(message: "Unable to apply patch.", error: error)
        }
    }
}

struct JarvisFileCreateTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "file.create",
        displayName: "File Create",
        capability: "file.create",
        riskLevel: .medium,
        auditCategory: "filesystem"
    )

    private let service: JarvisFileCreateService

    init(service: JarvisFileCreateService = JarvisFileToolEnvironment.createService) {
        self.service = service
    }

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        do {
            guard let path = invocation.arguments.requiredString("path") else {
                return failureResult(message: "Unable to create file.", detail: "missing path")
            }
            guard let content = invocation.arguments.requiredString("content") else {
                return failureResult(message: "Unable to create file.", detail: "missing content")
            }
            let overwrite = invocation.arguments.boolValue("overwrite") ?? false
            let approved = invocation.arguments.boolValue("approved") ?? false
            let response = approved
                ? try service.createFile(path: path, content: content, overwrite: overwrite)
                : try service.previewCreate(path: path, overwrite: overwrite)
            return JarvisToolResult(
                status: .success,
                userMessage: response.created
                    ? (response.overwritten ? "File overwritten." : "File created.")
                    : "File creation preview ready. Approval required.",
                rawResult: encode(response),
                retryable: false,
                verificationState: response.created ? .verified : .unverified
            )
        } catch {
            return failureResult(message: "Unable to create file.", error: error)
        }
    }
}

private func failureResult(message: String, error: Error) -> JarvisToolResult {
    failureResult(message: message, detail: String(describing: error))
}

private func failureResult(message: String, detail: String) -> JarvisToolResult {
    JarvisToolResult(
        status: .failed,
        userMessage: [message, detail].joined(separator: " "),
        retryable: false,
        verificationState: .unverified
    )
}

private func encode<T: Encodable>(_ value: T) -> Data? {
    try? JSONEncoder().encode(value)
}

private extension Dictionary where Key == String, Value == JarvisIntentValue {
    func requiredString(_ key: String) -> String? {
        guard let value = stringValue(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    func stringValue(_ key: String) -> String? {
        guard case .string(let value)? = self[key] else { return nil }
        return value
    }

    func intValue(_ key: String) -> Int? {
        guard case .number(let value)? = self[key] else { return nil }
        return Int(value)
    }

    func boolValue(_ key: String) -> Bool? {
        guard case .bool(let value)? = self[key] else { return nil }
        return value
    }
}
