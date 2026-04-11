import Foundation

struct JarvisFileCreateResponse: Codable, Equatable, Sendable {
    let path: String
    let fileName: String
    let created: Bool
    let overwritten: Bool
    let canCreate: Bool
    let requiresApproval: Bool
}

enum JarvisFileCreateError: Error, Equatable {
    case accessDenied
    case alreadyExists
}

struct JarvisFileCreateService {
    private let accessManager: JarvisFileAccessManager
    private let fileManager: FileManager

    init(
        accessManager: JarvisFileAccessManager,
        fileManager: FileManager = .default
    ) {
        self.accessManager = accessManager
        self.fileManager = fileManager
    }

    func previewCreate(path: String, overwrite: Bool = false) throws -> JarvisFileCreateResponse {
        let url = URL(fileURLWithPath: path)
        guard accessManager.isPathAllowed(url.path) else { throw JarvisFileCreateError.accessDenied }

        let exists = fileManager.fileExists(atPath: url.path)
        if exists && !overwrite {
            throw JarvisFileCreateError.alreadyExists
        }

        return JarvisFileCreateResponse(
            path: url.path,
            fileName: url.lastPathComponent,
            created: false,
            overwritten: exists,
            canCreate: true,
            requiresApproval: true
        )
    }

    func createFile(path: String, content: String, overwrite: Bool = false) throws -> JarvisFileCreateResponse {
        let url = URL(fileURLWithPath: path)
        guard accessManager.isPathAllowed(url.path) else { throw JarvisFileCreateError.accessDenied }

        let exists = fileManager.fileExists(atPath: url.path)
        if exists && !overwrite {
            throw JarvisFileCreateError.alreadyExists
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return JarvisFileCreateResponse(
            path: url.path,
            fileName: url.lastPathComponent,
            created: true,
            overwritten: exists,
            canCreate: true,
            requiresApproval: true
        )
    }
}
