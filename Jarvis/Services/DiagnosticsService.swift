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
        let notificationStatus = await notificationPermissionStatus()
        results.append(DiagnosticStatus(name: "Notifications", detail: notificationStatus.detail, isHealthy: notificationStatus.isHealthy))
        return results
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
}
