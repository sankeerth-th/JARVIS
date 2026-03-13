import Foundation
import AppKit
import UserNotifications

final class PermissionsManager {
    static let shared = PermissionsManager()
    static let screenCapturePermissionDidChangeNotification = Notification.Name("PermissionsManager.screenCapturePermissionDidChange")

    private enum ScreenCaptureCacheKey {
        static let granted = "permissions.screenCapture.granted"
        static let checkedAt = "permissions.screenCapture.checkedAt"
    }

    private let userDefaults: UserDefaults
    private let screenCaptureCacheTTL: TimeInterval = 5 * 60
    private let notificationCenter: NotificationCenter
    private var workspaceObservers: [Any] = []
    private var permissionChangeObservers: [Any] = []
    private(set) var hasPromptedForScreenRecordingThisSession = false

    private init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        observeWorkspace()
        observePermissionChanges()
    }

    func prepare() {
        _ = AXIsProcessTrusted()
        _ = checkScreenCapturePermission(forceRefresh: true)
    }

    func requestAccessibility() {
        let option = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(option)
    }

    func requestScreenRecording() {
        if checkScreenCapturePermission() {
            hasPromptedForScreenRecordingThisSession = true
            return
        }

        if hasPromptedForScreenRecordingThisSession {
            openScreenRecordingSettings()
            return
        }
        hasPromptedForScreenRecordingThisSession = true
        let granted = CGRequestScreenCaptureAccess()
        updateScreenCaptureCache(granted: granted, checkedAt: Date())
        if !granted {
            openScreenRecordingSettings()
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func checkScreenCapturePermission(forceRefresh: Bool = false) -> Bool {
        if !forceRefresh, let cached = cachedScreenCapturePermission, !isScreenCaptureCacheStale {
            return cached
        }

        let granted = CGPreflightScreenCaptureAccess()
        updateScreenCaptureCache(granted: granted, checkedAt: Date())
        return granted
    }

    func invalidatePermissionCache() {
        userDefaults.removeObject(forKey: ScreenCaptureCacheKey.granted)
        userDefaults.removeObject(forKey: ScreenCaptureCacheKey.checkedAt)
        notificationCenter.post(name: Self.screenCapturePermissionDidChangeNotification, object: nil)
    }

    func openAccessibilitySettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.offline.Jarvis"
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.notifications?\(bundleID)")
    }

    private func openSettings(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var cachedScreenCapturePermission: Bool? {
        guard userDefaults.object(forKey: ScreenCaptureCacheKey.granted) != nil else {
            return nil
        }
        return userDefaults.bool(forKey: ScreenCaptureCacheKey.granted)
    }

    private var isScreenCaptureCacheStale: Bool {
        guard let checkedAt = userDefaults.object(forKey: ScreenCaptureCacheKey.checkedAt) as? Date else {
            return true
        }
        return Date().timeIntervalSince(checkedAt) > screenCaptureCacheTTL
    }

    private func updateScreenCaptureCache(granted: Bool, checkedAt: Date) {
        let previous = cachedScreenCapturePermission
        userDefaults.set(granted, forKey: ScreenCaptureCacheKey.granted)
        userDefaults.set(checkedAt, forKey: ScreenCaptureCacheKey.checkedAt)

        if previous != granted {
            notificationCenter.post(name: Self.screenCapturePermissionDidChangeNotification, object: nil)
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification
        ]

        for name in names {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshScreenCapturePermissionIfNeeded()
            }
            workspaceObservers.append(observer)
        }
    }

    private func refreshScreenCapturePermissionIfNeeded() {
        guard isScreenCaptureCacheStale else { return }
        _ = checkScreenCapturePermission(forceRefresh: true)
    }

    private func observePermissionChanges() {
        let observer = notificationCenter.addObserver(
            forName: Self.screenCapturePermissionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hasPromptedForScreenRecordingThisSession = self?.cachedScreenCapturePermission == true
        }
        permissionChangeObservers.append(observer)
    }
}
