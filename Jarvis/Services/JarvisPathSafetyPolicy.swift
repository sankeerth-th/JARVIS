import Foundation

struct JarvisPathSafetyPolicy {
    let readableRoots: [URL]
    let writableRoots: [URL]

    init(
        readableRoots: [URL],
        writableRoots: [URL]
    ) {
        self.readableRoots = Self.normalizedRoots(readableRoots)
        self.writableRoots = Self.normalizedRoots(writableRoots)
    }

    init(settings: AppSettings, fileManager: FileManager = .default) {
        let home = fileManager.homeDirectoryForCurrentUser
        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let indexed = settings.indexedFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }

        self.init(
            readableRoots: [current, desktop, documents, downloads] + indexed,
            writableRoots: [current, desktop, documents]
        )
    }

    func canRead(path: String) -> Bool {
        isPath(path, within: readableRoots)
    }

    func canWrite(path: String) -> Bool {
        isPath(path, within: writableRoots)
    }

    func normalize(path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }

    private func isPath(_ path: String, within roots: [URL]) -> Bool {
        let normalized = normalize(path: path).path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            return normalized == rootPath || normalized.hasPrefix(rootPath + "/")
        }
    }

    private static func normalizedRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.compactMap { candidate in
            let normalized = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard seen.insert(normalized.path).inserted else { return nil }
            return normalized
        }
    }
}
