import Foundation
import UserNotifications

final class NotificationService: NSObject, ObservableObject {
    @Published private(set) var prioritizedNotifications: [NotificationItem] = []
    @Published private(set) var lowPriorityCount: Int = 0
    private var keywordRules: [String: NotificationItem.Priority] = [:]
    private var priorityApps: Set<String> = []
    private var quietHours: QuietHours?
    private var focusModeActive = false
    private var allowUrgentInQuietHours = true
    private var repeatedFingerprintCount: [String: Int] = [:]
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.jarvis.forwardedNotification"), object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let app = userInfo["app"] as? String,
                  let title = userInfo["title"] as? String,
                  let body = userInfo["body"] as? String else { return }
            self?.ingest(appIdentifier: app, title: title, body: body, metadata: [:])
        }
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Jarvis Permission Check"
        content.body = "Notifications are enabled for Jarvis."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    func setPriorityApps(_ bundleIdentifiers: [String]) {
        priorityApps = Set(bundleIdentifiers)
    }

    func setKeywordRules(_ rules: [String: NotificationItem.Priority]) {
        keywordRules = rules
    }

    func setQuietHours(_ quiet: QuietHours?) {
        quietHours = quiet
    }

    func setFocusMode(active: Bool) {
        focusModeActive = active
        recomputeLowPriorityCount()
    }

    func setAllowUrgentInQuietHours(_ allow: Bool) {
        allowUrgentInQuietHours = allow
    }

    func ingest(appIdentifier: String, title: String, body: String, metadata: [String: String]) {
        var item = NotificationItem(appIdentifier: appIdentifier, title: title, body: body, metadata: metadata)
        item.priority = classify(item: item)
        prioritizedNotifications.insert(item, at: 0)
        if prioritizedNotifications.count > 100 { prioritizedNotifications.removeLast() }
        recomputeLowPriorityCount()
    }

    func summarize(limit: Int = 5) -> String {
        let slice = prioritizedNotifications.prefix(limit)
        return slice.enumerated().map { idx, item in
            "\(idx + 1). [\(item.priority.rawValue.uppercased())] \(item.title): \(item.body)"
        }.joined(separator: "\n")
    }

    func recentNotifications(for apps: [String]? = nil, limit: Int = 5) -> [NotificationItem] {
        let filtered = prioritizedNotifications.filter { item in
            guard let apps else { return true }
            return apps.contains(where: { app in item.appIdentifier.localizedCaseInsensitiveContains(app) })
        }
        return Array(filtered.prefix(limit))
    }

    func topNotificationsForFocus(limit: Int = 12) -> [NotificationItem] {
        let filtered = prioritizedNotifications.filter { $0.priority != .low || !focusModeActive }
        return Array(filtered.prefix(limit))
    }

    func notificationsPermissionStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func classify(item: NotificationItem) -> NotificationItem.Priority {
        let fingerprint = "\(item.appIdentifier)|\(item.title.lowercased())|\(item.body.lowercased())"
        let repeatCount = (repeatedFingerprintCount[fingerprint] ?? 0) + 1
        repeatedFingerprintCount[fingerprint] = repeatCount

        var score = 0
        if priorityApps.contains(item.appIdentifier) {
            score += 45
        }
        for (keyword, priority) in keywordRules where item.body.localizedCaseInsensitiveContains(keyword) || item.title.localizedCaseInsensitiveContains(keyword) {
            switch priority {
            case .urgent: score += 45
            case .needsReply: score += 30
            case .fyi: score += 12
            case .low: score -= 8
            }
        }
        if item.body.localizedCaseInsensitiveContains("urgent")
            || item.body.localizedCaseInsensitiveContains("asap")
            || item.body.localizedCaseInsensitiveContains("payment failed")
            || item.body.localizedCaseInsensitiveContains("verification code") {
            score += 40
        }
        if item.body.localizedCaseInsensitiveContains("reply") || item.body.localizedCaseInsensitiveContains("respond") {
            score += 20
        }
        if repeatCount > 2 {
            score -= min((repeatCount - 2) * 8, 24)
        }
        if let quietHours, quietHours.contains(date: item.date), !(allowUrgentInQuietHours && score >= 45) {
            score -= 35
        }
        if focusModeActive {
            score -= 18
        }
        if score >= 50 {
            return .urgent
        }
        if score >= 24 {
            return .needsReply
        }
        if score >= 8 {
            return .fyi
        }
        return .low
    }

    private func recomputeLowPriorityCount() {
        lowPriorityCount = prioritizedNotifications.filter { $0.priority == .low }.count
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        ingest(appIdentifier: content.categoryIdentifier.isEmpty ? "local" : content.categoryIdentifier,
               title: content.title,
               body: content.body,
               metadata: content.userInfo as? [String: String] ?? [:])
        return [.list, .banner]
    }
}

private extension QuietHours {
    func contains(date: Date) -> Bool {
        let calendar = Calendar.current
        guard let startHour = start.hour, let endHour = end.hour else { return false }
        let startDate = calendar.date(bySettingHour: startHour, minute: start.minute ?? 0, second: 0, of: date) ?? date
        let endDate = calendar.date(bySettingHour: endHour, minute: end.minute ?? 0, second: 0, of: date) ?? date
        let now = date
        if startDate <= endDate {
            return now >= startDate && now <= endDate
        }
        return now >= startDate || now <= endDate
    }
}
