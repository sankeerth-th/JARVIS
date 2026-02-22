import Foundation
import AppKit
import UserNotifications

struct DiagnosticStatus: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let isHealthy: Bool
}

final class DiagnosticsService: ObservableObject {
    private let ollama: OllamaClient

    init(ollama: OllamaClient) {
        self.ollama = ollama
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
        let notificationGranted = await notificationPermission()
        results.append(DiagnosticStatus(name: "Notifications", detail: notificationGranted ? "Granted" : "Missing", isHealthy: notificationGranted))
        return results
    }

    private func notificationPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .authorized)
            }
        }
    }
}
