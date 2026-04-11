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

struct JarvisActionBrokerOutcome {
    var records: [JarvisActionExecutionRecord]
    var assistantMessage: String
    var pendingApproval: PendingApprovalRequest?
    var finalStatus: JarvisActionExecutionStatus
}

final class JarvisExecutionApprovalService {
    enum Decision {
        case allowed
        case requiresApproval(PendingApprovalRequest)
        case denied(String)
    }

    private let database: JarvisDatabase
    private let diagnostics: DiagnosticsService
    private let settingsStore: SettingsStore
    private var sessionRules: [ApprovalGrantRule]

    init(database: JarvisDatabase, diagnostics: DiagnosticsService, settingsStore: SettingsStore) {
        self.database = database
        self.diagnostics = diagnostics
        self.settingsStore = settingsStore
        self.sessionRules = database.loadApprovalRules().filter { $0.expiresAt.map { $0 > Date() } ?? true }
    }

    func evaluate(step: JarvisActionStep, planID: UUID) -> Decision {
        if hasMatchingGrant(for: step) {
            return .allowed
        }

        if step.kind == .screenCapture, step.metadata["explicitScreenRequest"] != "true" {
            return .requiresApproval(makePendingRequest(step: step, planID: planID, message: "Approval required before capturing the screen outside an explicit screen-inspection request."))
        }

        if step.kind == .shellCommand, step.metadata["terminalRisk"] == "catastrophic", step.metadata["elevatedConfirmed"] != "true" {
            return .requiresApproval(makePendingRequest(step: step, planID: planID, message: "This command is hard-blocked by default. It can only run after explicit elevated in-session approval."))
        }

        switch step.risk {
        case .readOnly:
            if settingsStore.current.approvalStrictnessMode == .strict {
                return .requiresApproval(makePendingRequest(step: step, planID: planID, message: "Strict mode requires approval for this action."))
            }
            return .allowed
        case .write, .destructive:
            return .requiresApproval(makePendingRequest(step: step, planID: planID, message: "Approval required before \(step.title.lowercased())."))
        }
    }

    func allow(_ request: PendingApprovalRequest, scope: JarvisApprovalScope) {
        let rule = ApprovalGrantRule(
            actionKind: request.step.kind,
            scope: scope,
            matcher: matcher(for: request.step),
            expiresAt: scope == .session ? Calendar.current.date(byAdding: .hour, value: 12, to: Date()) : nil
        )
        sessionRules.insert(rule, at: 0)
        if scope != .once {
            database.saveApprovalRule(rule)
        }
        diagnostics.logEvent(
            feature: "Approval runtime",
            type: "approval.allowed",
            summary: "Approved host action",
            metadata: ["actionKind": request.step.kind.rawValue, "scope": scope.rawValue]
        )
    }

    func deny(_ request: PendingApprovalRequest) {
        diagnostics.logEvent(
            feature: "Approval runtime",
            type: "approval.denied",
            summary: "Denied host action",
            metadata: ["actionKind": request.step.kind.rawValue]
        )
    }

    private func makePendingRequest(step: JarvisActionStep, planID: UUID, message: String) -> PendingApprovalRequest {
        diagnostics.logEvent(
            feature: "Approval runtime",
            type: "approval.requested",
            summary: message,
            metadata: ["actionKind": step.kind.rawValue, "planID": planID.uuidString]
        )
        return PendingApprovalRequest(planID: planID, step: step, message: message)
    }

    private func hasMatchingGrant(for step: JarvisActionStep) -> Bool {
        let target = matcher(for: step)
        return sessionRules.contains { rule in
            guard rule.actionKind == step.kind else { return false }
            if let expiresAt = rule.expiresAt, expiresAt < Date() { return false }
            return target.hasPrefix(rule.matcher) || rule.matcher == target
        }
    }

    private func matcher(for step: JarvisActionStep) -> String {
        if let target = step.metadata["target"], !target.isEmpty { return target }
        if let command = step.command, !command.isEmpty { return command }
        return step.targetSummary
    }
}

final class JarvisHostFileService {
    private let localIndexService: LocalIndexService
    private let macActionService: JarvisMacActionService
    private let fileManager: FileManager

    init(localIndexService: LocalIndexService,
         macActionService: JarvisMacActionService,
         fileManager: FileManager = .default) {
        self.localIndexService = localIndexService
        self.macActionService = macActionService
        self.fileManager = fileManager
    }

    func searchFiles(query: String, settings: AppSettings, limit: Int = 12) async -> (message: String, metadata: [String: String]) {
        let semanticMatches = (try? await localIndexService.searchFiles(query: query, limit: min(limit, 6), queryExpansionModel: settings.selectedModel, rootFolders: nil)) ?? []
        let lexicalMatches = lexicalSearch(query: query, settings: settings, limit: limit)

        var seen: Set<String> = []
        var lines: [String] = []
        for match in semanticMatches {
            guard seen.insert(match.document.path).inserted else { continue }
            lines.append("[semantic] \(match.document.title)\n\(match.document.path)\n\(match.snippet)")
        }
        for path in lexicalMatches where seen.insert(path).inserted {
            lines.append("[file] \(URL(fileURLWithPath: path).lastPathComponent)\n\(path)")
            if lines.count >= limit { break }
        }

        let summary = lines.isEmpty ? "No files matched '\(query)'." : lines.prefix(limit).joined(separator: "\n\n")
        return (summary, ["resultCount": String(lines.count), "query": query])
    }

    func readFile(path: String, settings: AppSettings) throws -> (message: String, metadata: [String: String]) {
        let policy = JarvisPathSafetyPolicy(settings: settings)
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard policy.canRead(path: standardized) else {
            throw ToolExecutionService.ToolExecutionError.validationFailed("Reading this path is not allowed.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: standardized))
        let prefix = data.prefix(24_000)
        guard let text = String(data: prefix, encoding: .utf8) ?? String(data: prefix, encoding: .ascii) else {
            throw ToolExecutionService.ToolExecutionError.validationFailed("Jarvis can only read text-like files directly.")
        }
        let truncated = data.count > prefix.count
        return (
            truncated ? "\(text)\n\n[Truncated]" : text,
            ["path": standardized, "truncated": String(truncated)]
        )
    }

    func createFile(path: String, contents: String, settings: AppSettings) throws -> (message: String, metadata: [String: String]) {
        let policy = JarvisPathSafetyPolicy(settings: settings)
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard policy.canWrite(path: standardized) else {
            throw ToolExecutionService.ToolExecutionError.validationFailed("Writing this path is not allowed.")
        }
        let parent = URL(fileURLWithPath: standardized).deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try contents.write(to: URL(fileURLWithPath: standardized), atomically: true, encoding: .utf8)
        return ("Created \(standardized).", ["path": standardized])
    }

    func editFile(path: String, contents: String, settings: AppSettings) throws -> (message: String, metadata: [String: String]) {
        let policy = JarvisPathSafetyPolicy(settings: settings)
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard policy.canWrite(path: standardized) else {
            throw ToolExecutionService.ToolExecutionError.validationFailed("Editing this path is not allowed.")
        }
        try contents.write(to: URL(fileURLWithPath: standardized), atomically: true, encoding: .utf8)
        return ("Updated \(standardized).", ["path": standardized])
    }

    func reveal(path: String) -> JarvisMacActionResult {
        macActionService.revealInFinder(path)
    }

    private func lexicalSearch(query: String, settings: AppSettings, limit: Int) -> [String] {
        let normalizedQuery = query.lowercased()
        let tokens = normalizedQuery.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let policy = JarvisPathSafetyPolicy(settings: settings)
        let enumerator = fileManager.enumerator(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        )

        var matches: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            let path = url.path
            if !policy.canRead(path: path) { continue }
            if tokens.isEmpty || tokens.allSatisfy({ path.lowercased().contains($0) }) {
                matches.append(path)
                if matches.count >= limit { break }
            }
        }
        return matches
    }
}

final class JarvisHostActionBroker {
    private let fileService: JarvisHostFileService
    private let terminalService: JarvisTerminalExecutionService
    private let screenshotService: ScreenshotService
    private let ocrService: OCRService
    private let macActionService: JarvisMacActionService
    private let projectActionService: JarvisProjectActionService
    private let approvalService: JarvisExecutionApprovalService
    private let diagnostics: DiagnosticsService
    private let database: JarvisDatabase

    init(fileService: JarvisHostFileService,
         terminalService: JarvisTerminalExecutionService,
         screenshotService: ScreenshotService,
         ocrService: OCRService,
         macActionService: JarvisMacActionService,
         projectActionService: JarvisProjectActionService,
         approvalService: JarvisExecutionApprovalService,
         diagnostics: DiagnosticsService,
         database: JarvisDatabase) {
        self.fileService = fileService
        self.terminalService = terminalService
        self.screenshotService = screenshotService
        self.ocrService = ocrService
        self.macActionService = macActionService
        self.projectActionService = projectActionService
        self.approvalService = approvalService
        self.diagnostics = diagnostics
        self.database = database
    }

    func plan(for prompt: String) -> JarvisActionPlan? {
        let lower = prompt.lowercased()
        if lower.contains("search my files") || lower.contains("find file") || lower.contains("search files") {
            return JarvisActionPlan(requestText: prompt, summary: "Search local files", steps: [
                JarvisActionStep(kind: .fileSearch, risk: .readOnly, title: "Search local files", targetSummary: prompt, metadata: ["query": prompt])
            ])
        }
        if let path = extractAbsolutePath(from: prompt), lower.contains("read") || lower.contains("show file") {
            return JarvisActionPlan(requestText: prompt, summary: "Read file", steps: [
                JarvisActionStep(kind: .fileRead, risk: .readOnly, title: "Read file", targetSummary: path, metadata: ["target": path])
            ])
        }
        if let path = extractAbsolutePath(from: prompt), lower.contains("create file") {
            return JarvisActionPlan(requestText: prompt, summary: "Create file", steps: [
                JarvisActionStep(kind: .fileCreate, risk: .write, title: "Create file", targetSummary: path, metadata: ["target": path, "content": extractContentPayload(from: prompt)])
            ])
        }
        if let path = extractAbsolutePath(from: prompt), lower.contains("edit file") || lower.contains("update file") || lower.contains("overwrite file") {
            return JarvisActionPlan(requestText: prompt, summary: "Edit file", steps: [
                JarvisActionStep(kind: .fileEdit, risk: .write, title: "Edit file", targetSummary: path, metadata: ["target": path, "content": extractContentPayload(from: prompt)])
            ])
        }
        if lower.contains("inspect screen") || lower.contains("look at my screen") || lower.contains("current window") || lower.contains("what's on my screen") {
            return JarvisActionPlan(requestText: prompt, summary: "Inspect current screen", steps: [
                JarvisActionStep(kind: .screenCapture, risk: .readOnly, title: "Capture current screen", targetSummary: "Screen", metadata: ["explicitScreenRequest": "true"])
            ])
        }
        if lower.hasPrefix("run ") || lower.hasPrefix("execute ") || lower.hasPrefix("shell ") {
            let command = prompt.components(separatedBy: " ").dropFirst().joined(separator: " ")
            return JarvisActionPlan(requestText: prompt, summary: "Run terminal command", steps: [
                JarvisActionStep(kind: .shellCommand, risk: .destructive, title: "Run terminal command", targetSummary: command, command: command, metadata: [:])
            ])
        }
        if let url = extractURL(from: prompt) {
            return JarvisActionPlan(requestText: prompt, summary: "Open URL", steps: [
                JarvisActionStep(kind: .openURL, risk: .write, title: "Open URL", targetSummary: url, metadata: ["target": url])
            ])
        }
        if lower.hasPrefix("open app ") || lower.hasPrefix("launch ") {
            let target = lower.hasPrefix("open app ") ? String(prompt.dropFirst("open app ".count)) : String(prompt.dropFirst("launch ".count))
            return JarvisActionPlan(requestText: prompt, summary: "Open app", steps: [
                JarvisActionStep(kind: .appOpen, risk: .write, title: "Open app", targetSummary: target, metadata: ["target": target])
            ])
        }
        if let path = extractAbsolutePath(from: prompt), lower.contains("reveal") {
            return JarvisActionPlan(requestText: prompt, summary: "Reveal in Finder", steps: [
                JarvisActionStep(kind: .revealInFinder, risk: .write, title: "Reveal in Finder", targetSummary: path, metadata: ["target": path])
            ])
        }
        if let path = extractAbsolutePath(from: prompt), lower.contains("open project") {
            return JarvisActionPlan(requestText: prompt, summary: "Open project", steps: [
                JarvisActionStep(kind: .projectOpen, risk: .write, title: "Open project", targetSummary: path, metadata: ["target": path])
            ])
        }
        return nil
    }

    func execute(plan: JarvisActionPlan, settings: AppSettings, approvalRequest: PendingApprovalRequest? = nil, elevatedConfirmation: Bool = false) async -> JarvisActionBrokerOutcome {
        guard let step = plan.steps.first else {
            return JarvisActionBrokerOutcome(records: [], assistantMessage: "No executable action was planned.", pendingApproval: nil, finalStatus: .failed)
        }

        var executableStep = step
        if elevatedConfirmation {
            executableStep.metadata["elevatedConfirmed"] = "true"
        }
        if approvalRequest == nil {
            switch approvalService.evaluate(step: executableStep, planID: plan.id) {
            case .allowed:
                break
            case .requiresApproval(let pending):
                return JarvisActionBrokerOutcome(
                    records: [JarvisActionExecutionRecord(stepID: executableStep.id, status: .requiresApproval, title: executableStep.title, detail: pending.message, metadata: executableStep.metadata)],
                    assistantMessage: pending.message,
                    pendingApproval: pending,
                    finalStatus: .requiresApproval
                )
            case .denied(let message):
                return JarvisActionBrokerOutcome(
                    records: [JarvisActionExecutionRecord(stepID: executableStep.id, status: .denied, title: executableStep.title, detail: message, metadata: executableStep.metadata)],
                    assistantMessage: message,
                    pendingApproval: nil,
                    finalStatus: .denied
                )
            }
        }

        let started = Date()
        do {
            let result = try await executeStep(executableStep, settings: settings)
            let record = JarvisActionExecutionRecord(
                stepID: executableStep.id,
                status: .success,
                title: executableStep.title,
                detail: result.message,
                metadata: result.metadata,
                startedAt: started,
                finishedAt: Date()
            )
            database.saveActionExecutionLog(record)
            diagnostics.logEvent(feature: "Host actions", type: "action.success", summary: executableStep.title, metadata: result.metadata)
            return JarvisActionBrokerOutcome(records: [record], assistantMessage: result.message, pendingApproval: nil, finalStatus: .success)
        } catch {
            let record = JarvisActionExecutionRecord(
                stepID: executableStep.id,
                status: .failed,
                title: executableStep.title,
                detail: error.localizedDescription,
                metadata: executableStep.metadata,
                startedAt: started,
                finishedAt: Date()
            )
            database.saveActionExecutionLog(record)
            diagnostics.logEvent(feature: "Host actions", type: "action.failed", summary: executableStep.title, metadata: ["error": error.localizedDescription])
            return JarvisActionBrokerOutcome(records: [record], assistantMessage: error.localizedDescription, pendingApproval: nil, finalStatus: .failed)
        }
    }

    private func executeStep(_ step: JarvisActionStep, settings: AppSettings) async throws -> (message: String, metadata: [String: String]) {
        switch step.kind {
        case .fileSearch:
            return await fileService.searchFiles(query: step.metadata["query"] ?? step.targetSummary, settings: settings)
        case .fileRead:
            return try fileService.readFile(path: step.metadata["target"] ?? step.targetSummary, settings: settings)
        case .fileCreate:
            return try fileService.createFile(path: step.metadata["target"] ?? step.targetSummary, contents: step.metadata["content"] ?? "", settings: settings)
        case .fileEdit:
            return try fileService.editFile(path: step.metadata["target"] ?? step.targetSummary, contents: step.metadata["content"] ?? "", settings: settings)
        case .screenCapture:
            let image = try await screenshotService.captureActiveWindow()
            let text = try ocrService.recognizeText(from: image)
            return (text.isEmpty ? "Captured the current screen, but OCR found no readable text." : text, ["captured": "window"])
        case .shellCommand:
            let shellRequest = SafeShellCommandRequest(command: step.command ?? "", workingDirectory: step.metadata["cwd"], timeout: 30)
            let assessment = terminalService.assess(shellRequest, policy: JarvisPathSafetyPolicy(settings: settings))
            let result = await terminalService.runCommand(
                shellRequest,
                policy: JarvisPathSafetyPolicy(settings: settings)
            )
            return ([result.userMessage, result.stdout, result.stderr.isEmpty ? nil : "stderr:\n\(result.stderr)"].compactMap { $0 }.joined(separator: "\n\n"),
                    ["command": result.commandDescription, "terminalRisk": assessment.risk.rawValue, "exitCode": String(result.exitCode)])
        case .appOpen:
            let result = await macActionService.openApp(nameOrBundleID: step.metadata["target"] ?? step.targetSummary)
            return (result.message, result.metadata)
        case .appFocus:
            let result = macActionService.focusApp(nameOrBundleID: step.metadata["target"] ?? step.targetSummary)
            return (result.message, result.metadata)
        case .openURL:
            let result = macActionService.openURL(step.metadata["target"] ?? step.targetSummary)
            return (result.message, result.metadata)
        case .revealInFinder:
            let result = fileService.reveal(path: step.metadata["target"] ?? step.targetSummary)
            return (result.message, result.metadata)
        case .projectOpen:
            let result = projectActionService.openProject(at: step.metadata["target"] ?? step.targetSummary)
            return (result.message, ["rootPath": result.rootPath, "success": String(result.success)])
        case .projectScaffold:
            let template = JarvisProjectTemplate(rawTemplate: step.metadata["template"] ?? "")
            let result = projectActionService.scaffoldProject(at: step.metadata["target"] ?? step.targetSummary, template: template, policy: JarvisPathSafetyPolicy(settings: settings))
            return (result.message, ["rootPath": result.rootPath, "success": String(result.success), "createdCount": String(result.createdPaths.count)])
        case .modelResponse:
            return ("", [:])
        }
    }

    private func extractAbsolutePath(from prompt: String) -> String? {
        if let range = prompt.range(of: #"/[A-Za-z0-9._/\- ]+"#, options: .regularExpression) {
            return String(prompt[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func extractURL(from prompt: String) -> String? {
        if let range = prompt.range(of: #"https?://[^\s]+"#, options: .regularExpression) {
            return String(prompt[range])
        }
        return nil
    }

    private func extractContentPayload(from prompt: String) -> String {
        if let range = prompt.range(of: "with content:", options: [.caseInsensitive]) {
            return String(prompt[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}
