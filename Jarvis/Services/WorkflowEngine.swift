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
    private let screenshotService: ScreenshotService
    private let ocrService: OCRService
    private let ollama: OllamaClient
    private let eventStore = EKEventStore()
    private var calendarAuthorized = false

    init(notificationService: NotificationService,
         localIndexService: LocalIndexService,
         documentService: DocumentImportService,
         screenshotService: ScreenshotService,
         ocrService: OCRService,
         ollama: OllamaClient) {
        self.notificationService = notificationService
        self.localIndexService = localIndexService
        self.documentService = documentService
        self.screenshotService = screenshotService
        self.ocrService = ocrService
        self.ollama = ollama
    }

    func run(_ macro: Macro, settings: AppSettings) async -> [MacroExecutionLog] {
        var logs: [MacroExecutionLog] = []
        var lastOutput: String = ""
        for step in macro.steps {
            switch step.kind {
            case .summarizeNotifications:
                let summary = notificationService.summarize(limit: Int(step.payload["limit"] ?? "5") ?? 5)
                logs.append(MacroExecutionLog(message: "Notifications:\n" + summary))
                lastOutput = summary
            case .summarizeDocuments:
                if let query = step.payload["query"], let match = try? await localIndexService.search(query: query, limit: 1).first {
                    let message = "Doc match: \(match.title)\n\(match.path)"
                    logs.append(MacroExecutionLog(message: message))
                    lastOutput = message
                } else if let path = step.payload["path"] {
                    let url = URL(fileURLWithPath: path)
                    if let document = try? documentService.importDocument(at: url) {
                        let snippet = document.content.prefix(1200)
                        let message = "Doc (\(document.title)) snippet:\n\(snippet)"
                        logs.append(MacroExecutionLog(message: message))
                        lastOutput = String(snippet)
                    } else {
                        logs.append(MacroExecutionLog(message: "Unable to load document at path: \(path)"))
                    }
                }
            case .summarizeCalendar:
                let days = Int(step.payload["days"] ?? "1") ?? 1
                let calendarSummary = summarizeCalendar(upcomingDays: days)
                logs.append(MacroExecutionLog(message: calendarSummary))
                lastOutput = calendarSummary
            case .runPrompt:
                let template = step.payload["prompt"] ?? ""
                let text = template.replacingOccurrences(of: "{{last_output}}", with: lastOutput)
                let request = GenerateRequest(model: settings.selectedModel, prompt: text, system: settings.systemPrompt, stream: false)
                if let response = try? await ollama.generate(request: request) {
                    logs.append(MacroExecutionLog(message: response))
                    lastOutput = response
                } else {
                    logs.append(MacroExecutionLog(message: "Prompt step failed"))
                }
            case .runTool:
                let toolName = step.payload["tool"] ?? ""
                if toolName == "ocrCurrentWindow" {
                    do {
                        let image = try screenshotService.captureActiveWindow()
                        let text = try ocrService.recognizeText(from: image)
                        let extracted = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if extracted.isEmpty {
                            logs.append(MacroExecutionLog(message: "OCR step completed: no text detected"))
                            lastOutput = ""
                        } else {
                            logs.append(MacroExecutionLog(message: "OCR output:\n\(extracted.prefix(2000))"))
                            lastOutput = extracted
                        }
                    } catch {
                        logs.append(MacroExecutionLog(message: "OCR step failed: \(error.localizedDescription). Check Screen Recording permission."))
                    }
                } else {
                    logs.append(MacroExecutionLog(message: "Unknown tool step: \(toolName)"))
                }
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
        guard !events.isEmpty else {
            return "No calendar events in the next \(upcomingDays) day(s)."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let lines = events.prefix(10).map { event -> String in
            let time = formatter.string(from: event.startDate)
            return "\(time) • \(event.title ?? "(No Title)")"
        }

        return "Calendar (next \(upcomingDays) day(s)):\n" + lines.joined(separator: "\n")
    }

    private func ensureCalendarAccess() -> Bool {
        if calendarAuthorized { return true }

        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        eventStore.requestAccess(to: .event) { success, _ in
            granted = success
            semaphore.signal()
        }
        semaphore.wait()

        calendarAuthorized = granted
        return granted
    }
}
