import Foundation
import Combine

struct ToolExecutionContext {
    var settings: AppSettings
    var requestedByUser: Bool
}

final class ToolExecutionService {
    private let calculator: Calculator
    private let screenshotService: ScreenshotService
    private let ocrService: OCRService
    private let notificationService: NotificationService
    private let localIndexService: LocalIndexService
    private let macActionService: JarvisMacActionService
    private let projectActionService: JarvisProjectActionService
    private let safeShellService: JarvisSafeShellService
    private let speechInputService: JarvisSpeechInputService
    private let speechOutputService: JarvisSpeechOutputService

    init(calculator: Calculator,
         screenshotService: ScreenshotService,
         ocrService: OCRService,
         notificationService: NotificationService,
         localIndexService: LocalIndexService,
         macActionService: JarvisMacActionService,
         projectActionService: JarvisProjectActionService,
         safeShellService: JarvisSafeShellService,
         speechInputService: JarvisSpeechInputService,
         speechOutputService: JarvisSpeechOutputService) {
        self.calculator = calculator
        self.screenshotService = screenshotService
        self.ocrService = ocrService
        self.notificationService = notificationService
        self.localIndexService = localIndexService
        self.macActionService = macActionService
        self.projectActionService = projectActionService
        self.safeShellService = safeShellService
        self.speechInputService = speechInputService
        self.speechOutputService = speechOutputService
    }

    func requiresConfirmation(for tool: ToolInvocation.ToolName) -> Bool {
        switch tool {
        case .ocrCurrentWindow, .listNotifications, .projectScaffold, .shellRunSafe:
            return true
        case .searchLocalDocs, .calculate, .summarize, .appOpen, .appFocus, .finderReveal, .projectOpen, .voiceListen, .voiceSpeak, .voiceStop:
            return false
        case .systemOpenURL:
            return true
        }
    }

    func approvalPreview(for invocation: ToolInvocation) -> ToolResult {
        ToolResult(
            content: approvalMessage(for: invocation),
            state: .requiresApproval,
            metadata: [
                "tool": invocation.name.rawValue,
                "approvalRequired": "true"
            ]
        )
    }

    func execute(_ invocation: ToolInvocation, context: ToolExecutionContext) async throws -> ToolResult {
        switch invocation.name {
        case .calculate:
            let expression = invocation.arguments["expression"] ?? ""
            let result = try calculator.evaluate(expression)
            let content = "Result: \(result.result.rounded(scale: 4))\nSteps:\n\(result.steps.joined(separator: "\n"))"
            return ToolResult(content: content, state: .success, metadata: ["expression": result.expression])
        case .ocrCurrentWindow:
            let reason = invocation.arguments["reason"] ?? ""
            let image = try await screenshotService.captureActiveWindow()
            let text = try ocrService.recognizeText(from: image)
            return ToolResult(content: text, state: .success, metadata: ["reason": reason])
        case .listNotifications:
            let apps = invocation.arguments["apps"]?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let limit = Int(invocation.arguments["limit"] ?? "5") ?? 5
            let notifications = notificationService.recentNotifications(for: apps, limit: limit)
            let content = notifications.map { item in
                "[\(item.priority.rawValue.uppercased())] \(item.title) — \(item.body)"
            }.joined(separator: "\n")
            return ToolResult(content: content, state: .success, metadata: ["count": "\(notifications.count)"])
        case .searchLocalDocs:
            let query = invocation.arguments["query"] ?? ""
            let topK = Int(invocation.arguments["topK"] ?? "5") ?? 5
            let matches = try await localIndexService.searchFiles(query: query, limit: topK, queryExpansionModel: nil, rootFolders: nil)
            let content = matches.enumerated().map { index, match in
                """
                [Result \(index + 1)] \(match.document.title)
                Path: \(match.document.path)
                Relevance: \(String(format: "%.2f", match.score))
                Excerpt: \(match.snippet)
                """
            }.joined(separator: "\n\n")
            return ToolResult(content: content, state: .success, metadata: ["query": query, "count": "\(matches.count)"])
        case .summarize:
            let text = invocation.arguments["text"] ?? ""
            let style = invocation.arguments["style"] ?? "concise"
            let summary = Self.rulesBasedSummarize(text: text, style: style)
            return ToolResult(content: summary, state: .success, metadata: ["style": style])
        case .appOpen:
            let target = invocation.arguments["target"] ?? invocation.arguments["name"] ?? invocation.arguments["bundleID"] ?? ""
            let result = await macActionService.openApp(nameOrBundleID: target)
            return toolResult(from: result, tool: invocation.name)
        case .appFocus:
            let target = invocation.arguments["target"] ?? invocation.arguments["name"] ?? invocation.arguments["bundleID"] ?? ""
            let result = macActionService.focusApp(nameOrBundleID: target)
            return toolResult(from: result, tool: invocation.name)
        case .finderReveal:
            let path = invocation.arguments["path"] ?? ""
            let policy = JarvisPathSafetyPolicy(settings: context.settings)
            guard policy.canRead(path: path) else {
                throw ToolExecutionError.validationFailed("Jarvis can only reveal files inside approved workspace paths.")
            }
            let result = macActionService.revealInFinder(path)
            return toolResult(from: result, tool: invocation.name)
        case .systemOpenURL:
            let target = invocation.arguments["url"] ?? ""
            let result = macActionService.openURL(target)
            return toolResult(from: result, tool: invocation.name)
        case .projectOpen:
            let path = invocation.arguments["path"] ?? ""
            let policy = JarvisPathSafetyPolicy(settings: context.settings)
            guard policy.canRead(path: path) else {
                throw ToolExecutionError.validationFailed("Jarvis can only open projects inside approved workspace paths.")
            }
            let result = projectActionService.openProject(at: path)
            return ToolResult(
                content: result.message,
                state: result.success ? .success : .failed,
                metadata: [
                    "tool": invocation.name.rawValue,
                    "success": String(result.success),
                    "rootPath": result.rootPath
                ]
            )
        case .projectScaffold:
            let path = invocation.arguments["path"] ?? ""
            let template = JarvisProjectTemplate(rawTemplate: invocation.arguments["template"] ?? "")
            let result = projectActionService.scaffoldProject(
                at: path,
                template: template,
                policy: JarvisPathSafetyPolicy(settings: context.settings)
            )
            return ToolResult(
                content: result.message,
                state: result.success ? .success : .failed,
                metadata: [
                    "tool": invocation.name.rawValue,
                    "success": String(result.success),
                    "rootPath": result.rootPath,
                    "createdCount": String(result.createdPaths.count),
                    "template": template.rawValue
                ]
            )
        case .shellRunSafe:
            let request = SafeShellCommandRequest(
                command: invocation.arguments["command"] ?? "",
                arguments: Self.parseList(invocation.arguments["arguments"]),
                workingDirectory: invocation.arguments["workingDirectory"],
                timeout: Double(invocation.arguments["timeout"] ?? "") ?? 5
            )
            let result = await safeShellService.runAllowedCommand(
                request,
                policy: JarvisPathSafetyPolicy(settings: context.settings)
            )
            let content = [result.userMessage, result.stdout, result.stderr.isEmpty ? nil : "stderr:\n\(result.stderr)"]
                .compactMap { $0 }
                .joined(separator: "\n\n")
            return ToolResult(
                content: content,
                state: result.success ? .success : .failed,
                metadata: [
                    "tool": invocation.name.rawValue,
                    "success": String(result.success),
                    "exitCode": String(result.exitCode),
                    "command": result.commandDescription
                ]
            )
        case .voiceListen:
            let permissions = await speechInputService.requestPermissions()
            guard permissions.isGranted else {
                throw ToolExecutionError.validationFailed("Microphone and speech recognition access are required before listening.")
            }
            try await speechInputService.startListening(localeIdentifier: invocation.arguments["locale"])
            return ToolResult(
                content: "Listening started. Call voice.stop when you want to finish the utterance.",
                state: .executing,
                metadata: [
                    "tool": invocation.name.rawValue,
                    "voiceState": VoiceInteractionState.listening.rawValue
                ]
            )
        case .voiceSpeak:
            let text = invocation.arguments["text"] ?? ""
            let started = await speechOutputService.speak(text)
            guard started else {
                throw ToolExecutionError.validationFailed("Jarvis could not start speaking an empty response.")
            }
            return ToolResult(
                content: "Speaking the requested response.",
                state: .executing,
                metadata: [
                    "tool": invocation.name.rawValue,
                    "voiceState": VoiceInteractionState.speaking.rawValue
                ]
            )
        case .voiceStop:
            await speechOutputService.stopSpeaking()
            let transcript = await speechInputService.stopListening()
            var metadata: [String: String] = [:]
            if let transcript {
                metadata["transcript"] = transcript.transcript
                if let confidence = transcript.confidence {
                    metadata["confidence"] = String(confidence)
                }
            }
            return ToolResult(
                content: transcript?.transcript ?? "Stopped active voice output.",
                state: .success,
                metadata: metadata.merging([
                    "tool": invocation.name.rawValue,
                    "voiceState": VoiceInteractionState.stopped.rawValue,
                    "state": transcript == nil ? "speech_stopped" : "transcript_ready"
                ], uniquingKeysWith: { _, new in new })
            )
        }
    }

    func failureResult(for invocation: ToolInvocation, message: String) -> ToolResult {
        ToolResult(
            content: message,
            state: .failed,
            metadata: [
                "tool": invocation.name.rawValue
            ]
        )
    }

    private func toolResult(from result: JarvisMacActionResult, tool: ToolInvocation.ToolName) -> ToolResult {
        ToolResult(
            content: result.message,
            state: result.succeeded ? .success : .failed,
            metadata: result.metadata.merging([
                "tool": tool.rawValue,
                "success": String(result.succeeded),
                "target": result.target
            ], uniquingKeysWith: { _, newValue in newValue })
        )
    }

    private func approvalMessage(for invocation: ToolInvocation) -> String {
        switch invocation.name {
        case .projectScaffold:
            return "Approval required before creating a new project scaffold."
        case .shellRunSafe:
            return "Approval required before running a shell command."
        case .systemOpenURL:
            return "Approval required before opening an external URL."
        default:
            return "Approval required before running this action."
        }
    }

    private static func parseList(_ rawValue: String?) -> [String] {
        guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func rulesBasedSummarize(text: String, style: String) -> String {
        let sentences = text.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
        let top = sentences.prefix(5)
        let prefix: String
        switch style.lowercased() {
        case "bullet": prefix = "• "
        case "actions": prefix = "Action: "
        default: prefix = ""
        }
        return top.map { prefix + $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
    }
}

extension ToolExecutionService {
    enum ToolExecutionError: LocalizedError {
        case validationFailed(String)

        var errorDescription: String? {
            switch self {
            case .validationFailed(let message):
                return message
            }
        }
    }
}

final class Calculator {
    enum CalculatorError: Error, LocalizedError {
        case invalidExpression

        var errorDescription: String? { "Unable to parse expression" }
    }

    func evaluate(_ input: String) throws -> CalculationResult {
        var working = input.lowercased()
        working = working.replacingOccurrences(of: "$", with: "")
        var steps: [String] = []

        if let (total, count) = detectSplit(input: working) {
            let value = total / count
            steps.append("Split \(total) by \(count) = \(value.rounded(scale: 4))")
            working = working.replacingOccurrences(of: "split", with: value.description)
            working = working.replacingOccurrences(of: "among", with: "")
        }

        if let percent = detectTax(input: working) {
            let numeric = working.filter { $0.isNumber || $0 == "." }
            if let base = Decimal(string: numeric) {
                let multiplier = 1 + (percent / 100)
                let taxed = base * multiplier
                steps.append("Apply tax \(percent)% (x\(multiplier.rounded(scale: 4)))")
                working = taxed.description
            }
        }

        let replacements: [String: String] = [
            "plus": "+",
            "add": "+",
            "minus": "-",
            "subtract": "-",
            "times": "*",
            "multiplied by": "*",
            "x": "*",
            "÷": "/",
            "divided by": "/",
            "over": "/",
            "per": "/"
        ]
        for (word, symbol) in replacements {
            working = working.replacingOccurrences(of: word, with: " \(symbol) ")
        }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()% ")
        let sanitized = working.components(separatedBy: allowed.inverted).joined().replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty else { throw CalculatorError.invalidExpression }
        let expression = sanitized
        let nsExpression = NSExpression(format: expression)
        guard let value = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
            throw CalculatorError.invalidExpression
        }
        let decimal = Decimal(value.doubleValue)
        return CalculationResult(expression: expression, result: decimal, steps: steps)
    }

    private func detectSplit(input: String) -> (Decimal, Decimal)? {
        guard let splitRange = input.range(of: "split"), let amongRange = input.range(of: "among", range: splitRange.upperBound..<input.endIndex) else { return nil }
        let totalString = input[splitRange.upperBound..<amongRange.lowerBound].filter { $0.isNumber || $0 == "." }
        let remainder = input[amongRange.upperBound...]
        let countString = remainder.split { !($0.isNumber || $0 == ".") }.first ?? ""
        guard let total = Decimal(string: String(totalString)), let count = Decimal(string: String(countString)) else { return nil }
        return (total, count)
    }

    private func detectTax(input: String) -> Decimal? {
        guard let taxRange = input.range(of: "tax") else { return nil }
        let substring = input[taxRange.upperBound...]
        guard let percentRange = substring.range(of: "%") else { return nil }
        let percentString = substring[..<percentRange.lowerBound].filter { $0.isNumber || $0 == "." }
        return Decimal(string: String(percentString))
    }
}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var mutable = self
        var result = Decimal()
        NSDecimalRound(&result, &mutable, scale, .bankers)
        return result
    }
}
