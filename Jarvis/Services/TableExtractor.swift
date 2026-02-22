import Foundation

final class TableExtractor {
    func extract(from text: String) -> TableExtractionResult {
        let lines = text
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return TableExtractionResult(headers: ["Column 1"], rows: [])
        }

        if let markdownTable = parseMarkdownTable(lines: lines) {
            return normalize(markdownTable)
        }

        let rows: [[String]]
        if let delimiter = detectDelimiter(in: lines) {
            rows = parseByDelimiter(lines: lines, delimiter: delimiter)
        } else {
            rows = parseByMultiSpace(lines: lines)
        }

        if rows.isEmpty {
            return TableExtractionResult(headers: ["Column 1"], rows: lines.map { [$0] })
        }

        if let keyValue = parseKeyValue(lines: lines) {
            return normalize(keyValue)
        }

        let normalized = normalize(rows)
        guard normalized.headers.count == 1 else {
            return normalized
        }
        return TableExtractionResult(headers: ["Column 1"], rows: lines.map { [$0] })
    }

    func render(_ table: TableExtractionResult, format: TableExtractionResult.OutputFormat) throws -> String {
        switch format {
        case .markdown:
            let headerLine = "| " + table.headers.joined(separator: " | ") + " |"
            let separator = "| " + table.headers.map { _ in "---" }.joined(separator: " | ") + " |"
            let rows = table.rows.map { row in "| " + row.joined(separator: " | ") + " |" }.joined(separator: "\n")
            return rows.isEmpty ? [headerLine, separator].joined(separator: "\n") : [headerLine, separator, rows].joined(separator: "\n")
        case .csv:
            let lines = ([table.headers] + table.rows).map { row in row.map { escapeCSV($0) }.joined(separator: ",") }
            return lines.joined(separator: "\n")
        case .json:
            let dicts = table.rows.map { row -> [String: String] in
                var dict: [String: String] = [:]
                for (index, header) in table.headers.enumerated() {
                    dict[header] = index < row.count ? row[index] : ""
                }
                return dict
            }
            let data = try JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted])
            return String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    private func detectDelimiter(in lines: [String]) -> Character? {
        let candidates: [Character] = ["\t", ",", "|", ";"]
        var best: (Character, Double) = ("\t", 1.0)
        for candidate in candidates {
            var totalColumns = 0
            var candidateLines = 0
            for line in lines {
                let columns = line.split(separator: candidate, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
                if columns.count > 1 {
                    totalColumns += columns.count
                    candidateLines += 1
                }
            }
            guard candidateLines > 0 else { continue }
            let avgColumns = Double(totalColumns) / Double(candidateLines)
            if avgColumns > best.1 {
                best = (candidate, avgColumns)
            }
        }
        return best.1 > 1.0 ? best.0 : nil
    }

    private func parseByDelimiter(lines: [String], delimiter: Character) -> [[String]] {
        lines.map { line in
            line.split(separator: delimiter, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    private func parseByMultiSpace(lines: [String]) -> [[String]] {
        lines.map { splitByRepeatedSpaces($0) }
            .filter { !$0.isEmpty }
    }

    private func splitByRepeatedSpaces(_ line: String) -> [String] {
        let pattern = #"\s{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [line]
        }
        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        guard !matches.isEmpty else { return [line] }
        var parts: [String] = []
        var cursor = 0
        for match in matches {
            let range = match.range
            let left = nsLine.substring(with: NSRange(location: cursor, length: range.location - cursor)).trimmingCharacters(in: .whitespaces)
            if !left.isEmpty { parts.append(left) }
            cursor = range.location + range.length
        }
        let tail = nsLine.substring(from: cursor).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { parts.append(tail) }
        return parts.isEmpty ? [line] : parts
    }

    private func parseMarkdownTable(lines: [String]) -> [[String]]? {
        let candidateLines = lines.filter { $0.contains("|") }
        guard candidateLines.count >= 2 else { return nil }
        let parsed = candidateLines.map { line in
            line
                .trimmingCharacters(in: CharacterSet(charactersIn: "| "))
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }.filter { !$0.isEmpty }
        guard parsed.count >= 2 else { return nil }
        let separatorPattern = CharacterSet(charactersIn: "-: ")
        let withoutSeparator = parsed.filter { row in
            !row.allSatisfy { !$0.isEmpty && $0.rangeOfCharacter(from: separatorPattern.inverted) == nil }
        }
        return withoutSeparator.count >= 2 ? withoutSeparator : nil
    }

    private func parseKeyValue(lines: [String]) -> [[String]]? {
        let pairs = lines.compactMap { line -> [String]? in
            guard let range = line.range(of: ":") else { return nil }
            let key = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return [key, value]
        }
        guard pairs.count >= 2 else { return nil }
        return [["Field", "Value"]] + pairs
    }

    private func normalize(_ rows: [[String]]) -> TableExtractionResult {
        let maxColumns = max(rows.map(\.count).max() ?? 1, 1)
        let paddedRows = rows.map { row -> [String] in
            if row.count >= maxColumns {
                return Array(row.prefix(maxColumns))
            }
            return row + Array(repeating: "", count: maxColumns - row.count)
        }

        if paddedRows.count == 1 {
            let headers = defaultHeaders(count: maxColumns)
            return TableExtractionResult(headers: headers, rows: [paddedRows[0]])
        }

        let firstRow = paddedRows[0]
        let isHeaderRow = !firstRow.allSatisfy(isMostlyNumeric)
        if isHeaderRow {
            let body = Array(paddedRows.dropFirst())
            return TableExtractionResult(headers: sanitizeHeaders(firstRow), rows: body)
        }

        return TableExtractionResult(headers: defaultHeaders(count: maxColumns), rows: paddedRows)
    }

    private func sanitizeHeaders(_ headers: [String]) -> [String] {
        headers.enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Column \(index + 1)" : trimmed
        }
    }

    private func defaultHeaders(count: Int) -> [String] {
        (1...max(count, 1)).map { "Column \($0)" }
    }

    private func isMostlyNumeric(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,-%$")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func escapeCSV(_ text: String) -> String {
        let needsQuotes = text.contains(",") || text.contains("\"") || text.contains("\n")
        var value = text.replacingOccurrences(of: "\"", with: "\"\"")
        if needsQuotes {
            value = "\"" + value + "\""
        }
        return value
    }
}
