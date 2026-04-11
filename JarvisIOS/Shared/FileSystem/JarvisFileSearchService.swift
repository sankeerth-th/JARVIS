import Foundation

struct JarvisFileSearchMatch: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let path: String
    let fileExtension: String
    let size: Int64
    let lastModified: Date

    init(url: URL, size: Int64, lastModified: Date) {
        self.id = url.path
        self.name = url.lastPathComponent
        self.path = url.path
        self.fileExtension = url.pathExtension.lowercased()
        self.size = size
        self.lastModified = lastModified
    }
}

struct JarvisFileSearchResponse: Codable, Equatable, Sendable {
    let query: String
    let results: [JarvisFileSearchMatch]
}

struct JarvisFileSearchService {
    private let accessManager: JarvisFileAccessManager
    private let fileManager: FileManager
    private let maxDepth: Int

    init(
        accessManager: JarvisFileAccessManager,
        fileManager: FileManager = .default,
        maxDepth: Int = 8
    ) {
        self.accessManager = accessManager
        self.fileManager = fileManager
        self.maxDepth = maxDepth
    }

    func searchFiles(query: String, limit: Int = 20) -> [JarvisFileSearchMatch] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty, limit > 0 else { return [] }

        let extQuery = normalizedQuery.hasPrefix(".") ? String(normalizedQuery.dropFirst()) : normalizedQuery
        var matches: [JarvisFileSearchMatch] = []

        for directory in accessManager.getAllowedDirectories() {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                if depth(of: url, relativeTo: directory) > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                if values?.isDirectory == true { continue }

                let name = url.lastPathComponent.lowercased()
                let fileExtension = url.pathExtension.lowercased()
                guard name.contains(normalizedQuery) || fileExtension == extQuery else { continue }

                let size = Int64(values?.fileSize ?? 0)
                let modified = values?.contentModificationDate ?? .distantPast
                matches.append(JarvisFileSearchMatch(url: url, size: size, lastModified: modified))
                if matches.count >= limit { return matches }
            }
        }

        return matches
    }

    private func depth(of url: URL, relativeTo root: URL) -> Int {
        let pathComponents = url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        return max(0, pathComponents.count - rootComponents.count)
    }
}
