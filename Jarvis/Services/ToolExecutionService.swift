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

    init(calculator: Calculator,
         screenshotService: ScreenshotService,
         ocrService: OCRService,
         notificationService: NotificationService,
         localIndexService: LocalIndexService) {
        self.calculator = calculator
        self.screenshotService = screenshotService
        self.ocrService = ocrService
        self.notificationService = notificationService
        self.localIndexService = localIndexService
    }

    func requiresConfirmation(for tool: ToolInvocation.ToolName) -> Bool {
        switch tool {
        case .ocrCurrentWindow, .listNotifications, .searchLocalDocs:
            return true
        case .calculate, .summarize:
            return false
        }
    }

    func execute(_ invocation: ToolInvocation, context: ToolExecutionContext) async throws -> ToolResult {
        switch invocation.name {
        case .calculate:
            let expression = invocation.arguments["expression"] ?? ""
            let result = try calculator.evaluate(expression)
            let content = "Result: \(result.result.rounded(scale: 4))\nSteps:\n\(result.steps.joined(separator: "\n"))"
            return ToolResult(content: content, metadata: ["expression": result.expression])
        case .ocrCurrentWindow:
            let reason = invocation.arguments["reason"] ?? ""
            let image = try screenshotService.captureActiveWindow()
            let text = try ocrService.recognizeText(from: image)
            return ToolResult(content: text, metadata: ["reason": reason])
        case .listNotifications:
            let apps = invocation.arguments["apps"]?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let limit = Int(invocation.arguments["limit"] ?? "5") ?? 5
            let notifications = notificationService.recentNotifications(for: apps, limit: limit)
            let content = notifications.map { item in
                "[\(item.priority.rawValue.uppercased())] \(item.title) — \(item.body)"
            }.joined(separator: "\n")
            return ToolResult(content: content, metadata: ["count": "\(notifications.count)"])
        case .searchLocalDocs:
            let query = invocation.arguments["query"] ?? ""
            let topK = Int(invocation.arguments["topK"] ?? "3") ?? 3
            let matches = try await localIndexService.search(query: query, limit: topK)
            let content = matches.map { match in
                "\(match.title)\nPath: \(match.path)"
            }.joined(separator: "\n---\n")
            return ToolResult(content: content, metadata: ["query": query, "count": "\(matches.count)"])
        case .summarize:
            let text = invocation.arguments["text"] ?? ""
            let style = invocation.arguments["style"] ?? "concise"
            let summary = Self.rulesBasedSummarize(text: text, style: style)
            return ToolResult(content: summary, metadata: ["style": style])
        }
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
