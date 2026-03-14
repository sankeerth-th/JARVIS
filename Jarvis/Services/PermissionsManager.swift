import Foundation
import AppKit
import UserNotifications

final class PermissionsManager {
    static let shared = PermissionsManager()
    static let screenCapturePermissionDidChangeNotification = Notification.Name("PermissionsManager.screenCapturePermissionDidChange")

    private enum Keys {
        static let screenCaptureGranted = "permissions.screenCapture.granted"
        static let screenCaptureCheckedAt = "permissions.screenCapture.checkedAt"
        static let screenCaptureUserGuided = "permissions.screenCapture.userGuided"
    }

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var workspaceObservers: [Any] = []
    private var permissionChangeObservers: [Any] = []
    
    // In-memory cache only - avoid disk staleness issues
    private var lastPermissionCheck: (granted: Bool, timestamp: Date)?
    private let permissionCheckTTL: TimeInterval = 30 // 30 seconds in-memory cache

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
        // Pre-check permission without prompting
        _ = checkScreenCapturePermission(forceRefresh: true)
    }

    func requestAccessibility() {
        let option = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(option)
    }

    /// Request screen recording permission only if not already granted.
    /// Uses CGPreflightScreenCaptureAccess to check first, avoiding unnecessary prompts.
    func requestScreenRecording() {
        // First check if already granted - use system API directly
        let isGranted = CGPreflightScreenCaptureAccess()
        
        if isGranted {
            // Permission already granted - update cache and return
            updatePermissionState(granted: true)
            return
        }
        
        // Check if user was already guided to Settings
        let wasGuided = userDefaults.bool(forKey: Keys.screenCaptureUserGuided)
        
        if wasGuided {
            // User was already guided once - just open Settings, don't request again
            openScreenRecordingSettings()
            return
        }
        
        // First time requesting - mark as guided and request access
        userDefaults.set(true, forKey: Keys.screenCaptureUserGuided)
        let granted = CGRequestScreenCaptureAccess()
        updatePermissionState(granted: granted)
        
        if !granted {
            openScreenRecordingSettings()
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Check screen capture permission status.
    /// Uses in-memory cache with short TTL to avoid repeated system calls.
    func checkScreenCapturePermission(forceRefresh: Bool = false) -> Bool {
        if !forceRefresh, let cached = lastPermissionCheck {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < permissionCheckTTL {
                return cached.granted
            }
        }

        let granted = CGPreflightScreenCaptureAccess()
        updatePermissionState(granted: granted)
        return granted
    }

    func invalidatePermissionCache() {
        lastPermissionCheck = nil
        userDefaults.removeObject(forKey: Keys.screenCaptureGranted)
        userDefaults.removeObject(forKey: Keys.screenCaptureCheckedAt)
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

    private func updatePermissionState(granted: Bool) {
        let previous = lastPermissionCheck?.granted
        lastPermissionCheck = (granted: granted, timestamp: Date())
        
        // Persist to UserDefaults for cross-session awareness
        userDefaults.set(granted, forKey: Keys.screenCaptureGranted)
        userDefaults.set(Date(), forKey: Keys.screenCaptureCheckedAt)

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
                // Refresh permission in background without triggering UI
                self?.refreshPermissionInBackground()
            }
            workspaceObservers.append(observer)
        }
    }

    private func refreshPermissionInBackground() {
        // Use longer TTL for background refreshes to avoid system call overhead
        if let cached = lastPermissionCheck {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < 60 { // 1 minute for background
                return
            }
        }
        _ = checkScreenCapturePermission(forceRefresh: true)
    }

    private func observePermissionChanges() {
        let observer = notificationCenter.addObserver(
            forName: Self.screenCapturePermissionDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Permission changed - no action needed, next check will pick it up
        }
        permissionChangeObservers.append(observer)
    }
}
