import Foundation
import AppKit
import UserNotifications
import Darwin

struct DiagnosticStatus: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let isHealthy: Bool
}

final class DiagnosticsService: ObservableObject {
    private let ollama: OllamaClient
    private let database: JarvisDatabase
    private var appSwitchHistory: [(bundleID: String, date: Date)] = []

    init(ollama: OllamaClient, database: JarvisDatabase) {
        self.ollama = ollama
        self.database = database
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier ?? app.localizedName ?? "unknown.app"
            self?.recordFrontmostApp(bundleID)
        }
    }

    func fetchStatuses(selectedModel: String) async -> [DiagnosticStatus] {
        var results: [DiagnosticStatus] = []
        let reachable = await ollama.isReachable()
        results.append(DiagnosticStatus(name: "Ollama", detail: reachable ? "Connected" : "Not reachable", isHealthy: reachable))
        if reachable {
            results.append(DiagnosticStatus(name: "Model", detail: selectedModel, isHealthy: true))
        } else {
            results.append(DiagnosticStatus(name: "Model", detail: "Unavailable", isHealthy: false))
        }
        let accessibility = AXIsProcessTrusted()
        results.append(DiagnosticStatus(name: "Accessibility", detail: accessibility ? "Granted" : "Missing", isHealthy: accessibility))
        let screenGranted = CGPreflightScreenCaptureAccess()
        results.append(DiagnosticStatus(name: "Screen Recording", detail: screenGranted ? "Granted" : "Missing", isHealthy: screenGranted))
        let notificationStatus = await notificationPermissionStatus()
        results.append(DiagnosticStatus(name: "Notifications", detail: notificationStatus.detail, isHealthy: notificationStatus.isHealthy))
        return results
    }

    func logEvent(feature: String, type: String, summary: String, metadata: [String: String] = [:]) {
        database.logFeatureEvent(FeatureEvent(feature: feature, type: type, summary: summary, metadata: metadata))
    }

    func recentEvents(limit: Int = 20, feature: String? = nil, since: Date? = nil) -> [FeatureEvent] {
        database.loadFeatureEvents(limit: limit, feature: feature, since: since)
    }

    func recentErrors(limit: Int = 5) -> [FeatureEvent] {
        database.loadFeatureEvents(limit: 100)
            .filter { $0.type.localizedCaseInsensitiveContains("error") || $0.summary.localizedCaseInsensitiveContains("failed") }
            .prefix(limit)
            .map { $0 }
    }

    func recentFrontmostApps(limit: Int = 12) -> [String] {
        let sorted = appSwitchHistory.sorted { $0.date > $1.date }
        return sorted.prefix(limit).map { "\($0.bundleID) @ \($0.date.formatted(date: .omitted, time: .shortened))" }
    }

    func moduleHealth(settings: AppSettings) async -> [ModuleHealthStatus] {
        let notificationPermission = await notificationPermissionStatus().isHealthy
        let modules: [(name: String, enabled: Bool, permissionsOK: Bool)] = [
            ("Why happened mode", true, true),
            ("Semantic search", !settings.indexedFolders.isEmpty, true),
            ("Focus mode", settings.focusModeEnabled, notificationPermission),
            ("Privacy guardian", settings.privacyGuardianEnabled, true),
            ("Thinking companion", true, true)
        ]
        return modules.map { module in
            ModuleHealthStatus(
                module: module.name,
                enabled: module.enabled,
                permissionsOK: module.permissionsOK,
                lastRun: database.lastFeatureRunDate(feature: module.name)
            )
        }
    }

    @discardableResult
    func createChecklist(title: String, items: [String]) -> UUID {
        database.saveChecklist(title: title, items: items)
    }

    func saveThinkingSession(_ session: ThinkingSessionRecord) {
        database.saveThinkingSession(session)
    }

    func loadThinkingSessions(limit: Int = 20) -> [ThinkingSessionRecord] {
        database.loadThinkingSessions(limit: limit)
    }

    func snapshotSignals() -> [String: String] {
        var loadAvg = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loadAvg, 3)
        let loadString: String
        if count > 0 {
            loadString = String(format: "1m %.2f, 5m %.2f, 15m %.2f", loadAvg[0], loadAvg[1], loadAvg[2])
        } else {
            loadString = "Unavailable"
        }
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        let freeDisk = freeDiskString()
        return [
            "cpu_load": loadString,
            "memory_total_gb": String(format: "%.1f", memoryGB),
            "disk_free": freeDisk,
            "frontmost_app": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        ]
    }

    private func recordFrontmostApp(_ bundleID: String) {
        appSwitchHistory.insert((bundleID, Date()), at: 0)
        if appSwitchHistory.count > 100 {
            appSwitchHistory.removeLast(appSwitchHistory.count - 100)
        }
    }

    private func freeDiskString() -> String {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        guard let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else {
            return "Unknown"
        }
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.1f GB", gb)
    }

    private func notificationPermissionStatus() async -> (isHealthy: Bool, detail: String) {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    continuation.resume(returning: (true, "Granted"))
                case .denied:
                    continuation.resume(returning: (false, "Denied"))
                case .notDetermined:
                    continuation.resume(returning: (false, "Not requested"))
                @unknown default:
                    continuation.resume(returning: (false, "Unknown"))
                }
            }
        }
    }

    func isNotificationPermissionGranted() async -> Bool {
        await notificationPermissionStatus().isHealthy
    }
}
