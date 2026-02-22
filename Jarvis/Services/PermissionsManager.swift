import Foundation
import AppKit
import UserNotifications

final class PermissionsManager {
    static let shared = PermissionsManager()
    private init() {}

    func prepare() {
        _ = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let option = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(option)
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func openAccessibilitySettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func openNotificationSettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.notifications")
    }

    private func openSettings(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
