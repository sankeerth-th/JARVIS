import Foundation

struct JarvisFileReadResponse: Codable, Equatable, Sendable {
    let path: String
    let name: String
    let fileExtension: String
    let content: String
    let truncated: Bool
    let byteCount: Int
}

struct JarvisFilePreviewResponse: Codable, Equatable, Sendable {
    let path: String
    let name: String
    let fileExtension: String
    let preview: String
    let truncated: Bool
    let byteCount: Int
}

enum JarvisFileReadError: Error, Equatable {
    case accessDenied
    case unsupportedFileType
    case fileNotFound
    case decodeFailed
}

struct JarvisFileReadService {
    private static let supportedExtensions: Set<String> = ["txt", "md", "swift", "json", "py", "js", "docx"]

    private let accessManager: JarvisFileAccessManager
    private let fileManager: FileManager
    private let maxReadBytes: Int

    init(
        accessManager: JarvisFileAccessManager,
        fileManager: FileManager = .default,
        maxReadBytes: Int = 256 * 1024
    ) {
        self.accessManager = accessManager
        self.fileManager = fileManager
        self.maxReadBytes = maxReadBytes
    }

    func readFile(path: String) throws -> JarvisFileReadResponse {
        let url = URL(fileURLWithPath: path)
        guard accessManager.isPathAllowed(url.path) else { throw JarvisFileReadError.accessDenied }
        guard fileManager.fileExists(atPath: url.path) else { throw JarvisFileReadError.fileNotFound }

        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else { throw JarvisFileReadError.unsupportedFileType }
        guard ext != "docx" else {
            return JarvisFileReadResponse(
                path: url.path,
                name: url.lastPathComponent,
                fileExtension: ext,
                content: "DOCX preview is not available in this build.",
                truncated: true,
                byteCount: 0
            )
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maxReadBytes + 1) ?? Data()
        let truncated = data.count > maxReadBytes
        let safeData = truncated ? data.prefix(maxReadBytes) : data[...]

        guard let content = String(data: Data(safeData), encoding: .utf8) else {
            throw JarvisFileReadError.decodeFailed
        }

        return JarvisFileReadResponse(
            path: url.path,
            name: url.lastPathComponent,
            fileExtension: ext,
            content: content,
            truncated: truncated,
            byteCount: Int(safeData.count)
        )
    }

    func previewFile(path: String, maxLength: Int = 2_000) throws -> JarvisFilePreviewResponse {
        let read = try readFile(path: path)
        let preview = String(read.content.prefix(maxLength))
        return JarvisFilePreviewResponse(
            path: read.path,
            name: read.name,
            fileExtension: read.fileExtension,
            preview: preview,
            truncated: read.truncated || preview.count < read.content.count,
            byteCount: read.byteCount
        )
    }
}
