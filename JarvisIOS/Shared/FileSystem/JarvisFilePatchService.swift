import Foundation

struct JarvisFilePatch: Codable, Equatable, Sendable {
    let originalContent: String
    let updatedContent: String
    let diffPreview: String
}

struct JarvisFilePatchResponse: Codable, Equatable, Sendable {
    let path: String
    let fileName: String
    let diffPreview: String
    let lineChangeCount: Int
    let applied: Bool
    let canApply: Bool
    let requiresApproval: Bool
}

enum JarvisFilePatchError: Error, Equatable {
    case accessDenied
    case fileNotFound
    case decodeFailed
    case contentMismatch
}

struct JarvisFilePatchService {
    private let accessManager: JarvisFileAccessManager
    private let fileManager: FileManager

    init(
        accessManager: JarvisFileAccessManager,
        fileManager: FileManager = .default
    ) {
        self.accessManager = accessManager
        self.fileManager = fileManager
    }

    func generatePatch(original: String, updated: String) -> JarvisFilePatch {
        JarvisFilePatch(
            originalContent: original,
            updatedContent: updated,
            diffPreview: makeDiffPreview(original: original, updated: updated)
        )
    }

    func previewPatch(path: String, patch: JarvisFilePatch) throws -> JarvisFilePatchResponse {
        let url = URL(fileURLWithPath: path)
        guard accessManager.isPathAllowed(url.path) else { throw JarvisFilePatchError.accessDenied }
        guard fileManager.fileExists(atPath: url.path) else { throw JarvisFilePatchError.fileNotFound }

        let currentData = try Data(contentsOf: url)
        guard let current = String(data: currentData, encoding: .utf8) else {
            throw JarvisFilePatchError.decodeFailed
        }

        return JarvisFilePatchResponse(
            path: url.path,
            fileName: url.lastPathComponent,
            diffPreview: patch.diffPreview,
            lineChangeCount: lineChangeCount(for: patch.diffPreview),
            applied: false,
            canApply: current == patch.originalContent,
            requiresApproval: true
        )
    }

    func applyPatch(path: String, patch: JarvisFilePatch) throws -> JarvisFilePatchResponse {
        let url = URL(fileURLWithPath: path)
        guard accessManager.isPathAllowed(url.path) else { throw JarvisFilePatchError.accessDenied }
        guard fileManager.fileExists(atPath: url.path) else { throw JarvisFilePatchError.fileNotFound }

        let currentData = try Data(contentsOf: url)
        guard let current = String(data: currentData, encoding: .utf8) else {
            throw JarvisFilePatchError.decodeFailed
        }
        guard current == patch.originalContent else { throw JarvisFilePatchError.contentMismatch }

        try patch.updatedContent.write(to: url, atomically: true, encoding: .utf8)
        return JarvisFilePatchResponse(
            path: url.path,
            fileName: url.lastPathComponent,
            diffPreview: patch.diffPreview,
            lineChangeCount: lineChangeCount(for: patch.diffPreview),
            applied: true,
            canApply: true,
            requiresApproval: true
        )
    }

    private func makeDiffPreview(original: String, updated: String) -> String {
        let originalLines = original.components(separatedBy: .newlines)
        let updatedLines = updated.components(separatedBy: .newlines)
        let difference = updatedLines.difference(from: originalLines)

        guard !difference.isEmpty else { return "No changes." }

        var lines: [String] = []
        for change in difference {
            switch change {
            case .remove(_, let element, _):
                lines.append("- \(element)")
            case .insert(_, let element, _):
                lines.append("+ \(element)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func lineChangeCount(for diffPreview: String) -> Int {
        diffPreview == "No changes." ? 0 : diffPreview.components(separatedBy: .newlines).count
    }
}
