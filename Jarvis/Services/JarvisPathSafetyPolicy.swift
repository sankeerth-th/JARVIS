import Foundation

struct JarvisPathSafetyPolicy {
    let readableRoots: [URL]
    let writableRoots: [URL]
    let excludedRoots: [URL]

    init(
        readableRoots: [URL],
        writableRoots: [URL],
        excludedRoots: [URL] = []
    ) {
        self.readableRoots = Self.normalizedRoots(readableRoots)
        self.writableRoots = Self.normalizedRoots(writableRoots)
        self.excludedRoots = Self.normalizedRoots(excludedRoots)
    }

    init(settings: AppSettings, fileManager: FileManager = .default) {
        let home = fileManager.homeDirectoryForCurrentUser
        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let indexed = settings.indexedFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let trustedWriteRoots = settings.trustedWriteRoots.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let explicitExclusions = settings.excludedReadRoots.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let defaultExclusions = [
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/private", isDirectory: true),
            URL(fileURLWithPath: "/Volumes", isDirectory: true),
            home.appendingPathComponent("Library/Caches", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Group Containers", isDirectory: true),
            home.appendingPathComponent(".Trash", isDirectory: true)
        ]

        self.init(
            readableRoots: settings.broadFileAccessEnabled ? [home, current] + indexed : [current, desktop, documents, downloads] + indexed,
            writableRoots: trustedWriteRoots.isEmpty ? [current, desktop, documents] : trustedWriteRoots,
            excludedRoots: explicitExclusions + defaultExclusions
        )
    }

    func canRead(path: String) -> Bool {
        isPath(path, within: readableRoots) && !isPath(path, within: excludedRoots)
    }

    func canWrite(path: String) -> Bool {
        isPath(path, within: writableRoots) && !isPath(path, within: excludedRoots)
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
