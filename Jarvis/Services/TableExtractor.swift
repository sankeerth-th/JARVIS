import Foundation

final class TableExtractor {
    func extract(from text: String) -> TableExtractionResult {
        let delimiter = detectDelimiter(in: text)
        let lines = text.split(whereSeparator: { $0.isNewline }).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var rows: [[String]] = []
        for line in lines {
            let columns = line.split(separator: delimiter, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            rows.append(columns)
        }
        let headers = rows.first ?? []
        let body = rows.count > 1 ? Array(rows.dropFirst()) : []
        return TableExtractionResult(headers: headers, rows: body)
    }

    func render(_ table: TableExtractionResult, format: TableExtractionResult.OutputFormat) throws -> String {
        switch format {
        case .markdown:
            let headerLine = "| " + table.headers.joined(separator: " | ") + " |"
            let separator = "| " + table.headers.map { _ in "---" }.joined(separator: " | ") + " |"
            let rows = table.rows.map { row in "| " + row.joined(separator: " | ") + " |" }.joined(separator: "\n")
            return [headerLine, separator, rows].joined(separator: "\n")
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

    private func detectDelimiter(in text: String) -> Character {
        let candidates: [Character] = ["\t", ",", "|", ";"]
        var best: (Character, Int) = ("\t", -1)
        for candidate in candidates {
            let count = text.reduce(into: 0) { partialResult, char in
                if char == candidate { partialResult += 1 }
            }
            if count > best.1 { best = (candidate, count) }
        }
        return best.1 > 0 ? best.0 : ","
    }

    private func escapeCSV(_ text: String) -> String {
        var needsQuotes = text.contains(",") || text.contains("\"") || text.contains("\n")
        var value = text.replacingOccurrences(of: "\"", with: "\"\"")
        if needsQuotes {
            value = "\"" + value + "\""
        }
        return value
    }
}
