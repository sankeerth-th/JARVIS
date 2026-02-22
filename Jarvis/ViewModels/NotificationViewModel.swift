import Foundation
import Combine

final class NotificationViewModel: ObservableObject {
    @Published private(set) var notifications: [NotificationItem] = []
    @Published var priorityApps: [String] = ["com.apple.mail", "com.apple.MobileSMS", "com.tinyspeck.slackmacgap"]
    @Published var keywordRules: [String: NotificationItem.Priority] = ["invoice": .urgent, "verification": .urgent, "meeting": .needsReply]
    @Published var quietHours: QuietHours? = nil
    @Published var focusModeEnabled: Bool = false

    private var cancellables: Set<AnyCancellable> = []
    private let service: NotificationService

    init(service: NotificationService) {
        self.service = service
        bind()
    }

    private func bind() {
        service.$prioritizedNotifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.notifications = items
            }
            .store(in: &cancellables)
        $priorityApps
            .sink { [weak self] apps in self?.service.setPriorityApps(apps) }
            .store(in: &cancellables)
        $keywordRules
            .sink { [weak self] rules in self?.service.setKeywordRules(rules) }
            .store(in: &cancellables)
        $quietHours
            .sink { [weak self] quiet in self?.service.setQuietHours(quiet) }
            .store(in: &cancellables)
        $focusModeEnabled
            .sink { [weak self] enabled in self?.service.setFocusMode(active: enabled) }
            .store(in: &cancellables)
    }

    func summary(limit: Int = 5) -> String {
        service.summarize(limit: limit)
    }

    func proposeResponses(limit: Int = 3) -> [NotificationItem] {
        notifications.prefix(limit).map { item in
            var copy = item
            if item.priority == .needsReply || item.priority == .urgent {
                copy.suggestedResponse = "Hi, thanks for the update — I'll get back to you shortly."
            }
            return copy
        }
    }

    func sendTestNotification() {
        service.sendTestNotification()
    }
}
