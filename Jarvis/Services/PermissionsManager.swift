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
}
