import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationViewModel: ObservableObject {
    @Published private(set) var notifications: [NotificationItem] = []
    @Published var priorityApps: [String] = []
    @Published var keywordRules: [String: NotificationItem.Priority] = ["invoice": .urgent, "verification": .urgent, "meeting": .needsReply]
    @Published var quietHours: QuietHours? = nil
    @Published var focusModeEnabled: Bool = false
    @Published var allowUrgentInQuietHours: Bool = true
    @Published var digestOutput: String = ""
    @Published var lowPriorityCount: Int = 0
    @Published var notificationsPermissionGranted: Bool = false

    private var cancellables: Set<AnyCancellable> = []
    private let service: NotificationService
    private let settingsStore: SettingsStore
    private let ollama: OllamaClient

    init(service: NotificationService, settingsStore: SettingsStore, ollama: OllamaClient) {
        self.service = service
        self.settingsStore = settingsStore
        self.ollama = ollama
        self.priorityApps = settingsStore.current.focusPriorityApps
        self.focusModeEnabled = settingsStore.current.focusModeEnabled
        self.allowUrgentInQuietHours = settingsStore.current.focusAllowUrgent
        self.quietHours = QuietHours(
            start: DateComponents(hour: settingsStore.current.quietHoursStartHour),
            end: DateComponents(hour: settingsStore.current.quietHoursEndHour)
        )
        bind()
        Task {
            await refreshPermissionStatus()
        }
    }

    private func bind() {
        service.$prioritizedNotifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self else { return }
                self.notifications = self.focusModeEnabled ? self.service.topNotificationsForFocus(limit: 25) : items
            }
            .store(in: &cancellables)
        service.$lowPriorityCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.lowPriorityCount = count }
            .store(in: &cancellables)
        $priorityApps
            .sink { [weak self] apps in
                self?.service.setPriorityApps(apps)
                self?.settingsStore.setFocusPriorityApps(apps)
            }
            .store(in: &cancellables)
        $keywordRules
            .sink { [weak self] rules in self?.service.setKeywordRules(rules) }
            .store(in: &cancellables)
        $quietHours
            .sink { [weak self] quiet in
                self?.service.setQuietHours(quiet)
                self?.settingsStore.setQuietHours(
                    startHour: quiet?.start.hour ?? 22,
                    endHour: quiet?.end.hour ?? 7
                )
            }
            .store(in: &cancellables)
        $focusModeEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                self.service.setFocusMode(active: enabled)
                self.settingsStore.setFocusModeEnabled(enabled)
                let source = self.service.prioritizedNotifications
                self.notifications = enabled ? self.service.topNotificationsForFocus(limit: 25) : source
                if enabled {
                    self.service.requestPermission()
                }
            }
            .store(in: &cancellables)
        $allowUrgentInQuietHours
            .sink { [weak self] allow in
                self?.service.setAllowUrgentInQuietHours(allow)
                self?.settingsStore.setFocusAllowUrgent(allow)
            }
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

    func addPriorityApp(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        if !priorityApps.contains(bundleID) {
            priorityApps.append(bundleID)
        }
    }

    func toggleFocusMode() {
        focusModeEnabled.toggle()
    }

    func batchDigestNow(model: String) {
        let digestInput = summary(limit: 20)
        guard !digestInput.isEmpty else {
            digestOutput = "No notifications to summarize."
            return
        }
        Task {
            let prompt = """
            Summarize these notifications in <=8 bullets.
            Group into Urgent, Needs reply, FYI.
            Include one line: 'Low-priority batched: \(lowPriorityCount)'.
            Notifications:
            \(digestInput)
            """
            let request = GenerateRequest(
                model: model,
                prompt: prompt,
                system: "You are Jarvis Focus Digest. Be concise and actionable.",
                stream: false,
                options: ["temperature": 0.2, "num_predict": 260]
            )
            do {
                let response = try await ollama.generate(request: request)
                await MainActor.run {
                    self.digestOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                await MainActor.run {
                    self.digestOutput = "Digest failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func refreshPermissionStatus() async {
        let status = await service.notificationsPermissionStatus()
        notificationsPermissionGranted = status == .authorized || status == .provisional
    }
}
