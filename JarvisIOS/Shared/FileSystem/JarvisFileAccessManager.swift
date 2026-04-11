import Foundation

struct JarvisAllowedDirectoryRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let path: String
    let name: String

    init(url: URL) {
        self.id = url.path
        self.path = url.path
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}

struct JarvisAllowedRootsListResponse: Codable, Equatable, Sendable {
    let roots: [JarvisAllowedDirectoryRecord]
}

struct JarvisAllowedRootAddResponse: Codable, Equatable, Sendable {
    let root: JarvisAllowedDirectoryRecord
    let added: Bool
    let validationState: String
}

struct JarvisFilePathValidationResponse: Codable, Equatable, Sendable {
    let path: String
    let normalizedPath: String
    let allowed: Bool
    let validationState: String
    let matchedRoot: JarvisAllowedDirectoryRecord?
}

final class JarvisFileAccessManager {
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "jarvis.allowedDirectories"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    @discardableResult
    func addAllowedDirectory(_ url: URL) -> URL? {
        let normalized = normalizeDirectoryURL(url)
        guard FileManager.default.fileExists(atPath: normalized.path) else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var paths = defaults.stringArray(forKey: storageKey) ?? []
        if !paths.contains(normalized.path) {
            paths.append(normalized.path)
            paths.sort()
            defaults.set(paths, forKey: storageKey)
        }
        return normalized
    }

    func getAllowedDirectories() -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        return (defaults.stringArray(forKey: storageKey) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func isPathAllowed(_ path: String) -> Bool {
        validatePath(path).allowed
    }

    func validatePath(_ path: String) -> JarvisFilePathValidationResponse {
        let normalizedPath = normalizePath(path)

        lock.lock()
        let allowedPaths = defaults.stringArray(forKey: storageKey) ?? []
        lock.unlock()

        let matchedRoot = allowedPaths.first { allowed in
            normalizedPath == allowed || normalizedPath.hasPrefix(allowed + "/")
        }

        return JarvisFilePathValidationResponse(
            path: path,
            normalizedPath: normalizedPath,
            allowed: matchedRoot != nil,
            validationState: matchedRoot != nil ? "allowed" : "denied",
            matchedRoot: matchedRoot.map {
                JarvisAllowedDirectoryRecord(url: URL(fileURLWithPath: $0, isDirectory: true))
            }
        )
    }

    func allowedDirectoryRecords() -> [JarvisAllowedDirectoryRecord] {
        getAllowedDirectories().map(JarvisAllowedDirectoryRecord.init(url:))
    }

    private func normalizeDirectoryURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        return standardized.hasDirectoryPath
            ? standardized
            : standardized.deletingLastPathComponent()
    }

    private func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
