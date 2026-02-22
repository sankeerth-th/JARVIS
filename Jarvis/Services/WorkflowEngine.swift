import Foundation
import EventKit

struct MacroExecutionLog: Identifiable {
    let id = UUID()
    let message: String
}

final class WorkflowEngine {
    private let notificationService: NotificationService
    private let localIndexService: LocalIndexService
    private let documentService: DocumentImportService
    private let ollama: OllamaClient
    private let eventStore = EKEventStore()
    private var calendarAuthorized = false

    init(notificationService: NotificationService,
         localIndexService: LocalIndexService,
         documentService: DocumentImportService,
         ollama: OllamaClient) {
        self.notificationService = notificationService
        self.localIndexService = localIndexService
        self.documentService = documentService
        self.ollama = ollama
    }

    func run(_ macro: Macro, settings: AppSettings) async -> [MacroExecutionLog] {
        var logs: [MacroExecutionLog] = []
        for step in macro.steps {
            switch step.kind {
            case .summarizeNotifications:
                let summary = notificationService.summarize(limit: Int(step.payload["limit"] ?? "5") ?? 5)
                logs.append(MacroExecutionLog(message: "Notifications:\n" + summary))
            case .summarizeDocuments:
                if let query = step.payload["query"], let match = try? await localIndexService.search(query: query, limit: 1).first {
                    logs.append(MacroExecutionLog(message: "Doc match: \(match.title)\n\(match.path)"))
                } else if let path = step.payload["path"], let url = URL(string: path), let document = try? documentService.importDocument(at: url) {
                    let snippet = document.content.prefix(1200)
                    logs.append(MacroExecutionLog(message: "Doc (\(document.title)) snippet:\n\(snippet)"))
                }
            case .summarizeCalendar:
                let days = Int(step.payload["days"] ?? "1") ?? 1
                let calendarSummary = summarizeCalendar(upcomingDays: days)
                logs.append(MacroExecutionLog(message: calendarSummary))
            case .runPrompt:
                let text = step.payload["prompt"] ?? ""
                let request = GenerateRequest(model: settings.selectedModel, prompt: text, system: settings.systemPrompt, stream: false)
                if let response = try? await ollama.generate(request: request) {
                    logs.append(MacroExecutionLog(message: response))
                }
            case .runTool:
                logs.append(MacroExecutionLog(message: "Tool step needs manual confirmation inside the main UI."))
            }
        }
        return logs
    }

    private func summarizeCalendar(upcomingDays: Int) -> String {
        guard ensureCalendarAccess() else {
            return "Calendar access not granted. Enable it in System Settings → Privacy & Security → Calendars."
        }
        let calendars = eventStore.calendars(for: .event).filter { $0.isSubscribed || !$0.isImmutable }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: upcomingDays, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate).sorted(by: { $0.startDate < $1.startDate })
        guard !events.isEmpty else { return \"No calendar events in the next \\(upcomingDays) day(s).\" }\n        let formatter = DateFormatter()\n        formatter.dateStyle = .none\n        formatter.timeStyle = .short\n        let lines = events.prefix(10).map { event -> String in\n            let time = formatter.string(from: event.startDate)\n            return \"\\(time) • \\(event.title ?? \"(No Title)\")\"\n        }\n        return \"Calendar (next \\(upcomingDays) day(s)):\\n\" + lines.joined(separator: \"\\n\")\n    }\n\n    private func ensureCalendarAccess() -> Bool {\n        if calendarAuthorized { return true }\n        let semaphore = DispatchSemaphore(value: 0)\n        var granted = false\n        eventStore.requestAccess(to: .event) { success, _ in\n            granted = success\n            semaphore.signal()\n        }\n        semaphore.wait()\n        calendarAuthorized = granted\n        return granted\n    }\n*** End Patch
}
