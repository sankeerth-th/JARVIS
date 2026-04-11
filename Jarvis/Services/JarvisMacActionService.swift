import Foundation
import AppKit

enum JarvisMacActionStatus: String, Codable, Equatable {
    case success
    case failure
}

struct JarvisMacActionResult: Codable, Equatable {
    let status: JarvisMacActionStatus
    let message: String
    let target: String
    let metadata: [String: String]

    var succeeded: Bool {
        status == .success
    }

    static func success(_ message: String, target: String, metadata: [String: String] = [:]) -> Self {
        .init(status: .success, message: message, target: target, metadata: metadata)
    }

    static func failure(_ message: String, target: String, metadata: [String: String] = [:]) -> Self {
        .init(status: .failure, message: message, target: target, metadata: metadata)
    }
}

protocol JarvisWorkspaceProviding {
    var runningApplications: [NSRunningApplication] { get }
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func fullPath(forApplication appName: String) -> String?
    func open(_ url: URL) -> Bool
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws
    func activateFileViewerSelecting(_ urls: [URL])
}

struct JarvisLiveWorkspaceProvider: JarvisWorkspaceProviding {
    var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func fullPath(forApplication appName: String) -> String? {
        NSWorkspace.shared.fullPath(forApplication: appName)
    }

    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func activateFileViewerSelecting(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

final class JarvisMacActionService {
    private let workspace: JarvisWorkspaceProviding
    private let fileManager: FileManager

    init(
        workspace: JarvisWorkspaceProviding = JarvisLiveWorkspaceProvider(),
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func openApp(nameOrBundleID: String) async -> JarvisMacActionResult {
        let target = nameOrBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return .failure("Missing application name or bundle identifier.", target: target)
        }

        if let running = matchingRunningApplication(target) {
            let activated = running.activate()
            return activated
                ? .success("Opened \(displayName(for: running)).", target: target, metadata: ["bundleID": running.bundleIdentifier ?? ""])
                : .failure("Could not bring \(displayName(for: running)) to the front.", target: target)
        }

        guard let appURL = applicationURL(for: target) else {
            return .failure("Could not find an application named \(target).", target: target)
        }

        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await workspace.openApplication(at: appURL, configuration: configuration)
            return .success("Opened \(appURL.deletingPathExtension().lastPathComponent).", target: target, metadata: ["path": appURL.path])
        } catch {
            return .failure("Failed to open \(target): \(error.localizedDescription)", target: target)
        }
    }

    func focusApp(nameOrBundleID: String) -> JarvisMacActionResult {
        let target = nameOrBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return .failure("Missing application name or bundle identifier.", target: target)
        }

        guard let running = matchingRunningApplication(target) else {
            return .failure("No running application matched \(target).", target: target)
        }

        return running.activate()
            ? .success("Focused \(displayName(for: running)).", target: target, metadata: ["bundleID": running.bundleIdentifier ?? ""])
            : .failure("Could not focus \(displayName(for: running)).", target: target)
    }

    func openPath(_ path: String) -> JarvisMacActionResult {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL
        guard fileManager.fileExists(atPath: normalized.path) else {
            return .failure("Path does not exist.", target: normalized.path)
        }

        return workspace.open(normalized)
            ? .success("Opened \(normalized.lastPathComponent).", target: normalized.path)
            : .failure("Could not open \(normalized.lastPathComponent).", target: normalized.path)
    }

    func revealInFinder(_ path: String) -> JarvisMacActionResult {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL
        guard fileManager.fileExists(atPath: normalized.path) else {
            return .failure("Path does not exist.", target: normalized.path)
        }

        workspace.activateFileViewerSelecting([normalized])
        return .success("Revealed \(normalized.lastPathComponent) in Finder.", target: normalized.path)
    }

    func openURL(_ value: String) -> JarvisMacActionResult {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else {
            return .failure("Only http, https, and mailto URLs are allowed.", target: raw)
        }

        return workspace.open(url)
            ? .success("Opened \(raw).", target: raw, metadata: ["scheme": scheme])
            : .failure("Could not open \(raw).", target: raw)
    }

    private func applicationURL(for target: String) -> URL? {
        if target.contains("."),
           let bundleURL = workspace.urlForApplication(withBundleIdentifier: target) {
            return bundleURL
        }

        if let fullPath = workspace.fullPath(forApplication: target) {
            return URL(fileURLWithPath: fullPath)
        }

        if target.lowercased().hasSuffix(".app") {
            let url = URL(fileURLWithPath: target)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func matchingRunningApplication(_ target: String) -> NSRunningApplication? {
        let normalized = target.lowercased()
        return workspace.runningApplications.first { app in
            app.bundleIdentifier?.lowercased() == normalized
                || app.localizedName?.lowercased() == normalized
        }
    }

    private func displayName(for app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? "application"
    }
}
