import Foundation
import CryptoKit

struct IngestedDocumentPayload {
    var file: IndexedFileRecord
    var normalizedText: String
    var content: String
    var pageTexts: [String]
}

final class SearchIngestionService {
    private let importService: DocumentImportService
    private let fileManager = FileManager.default

    init(importService: DocumentImportService) {
        self.importService = importService
    }

    static let supportedExtensions: Set<String> = [
        "md", "txt", "rtf", "text", "markdown", "pdf", "docx", "png", "jpg", "jpeg", "heic", "tif", "tiff"
    ]

    func ingestFile(at url: URL, indexVersion: Int) throws -> IngestedDocumentPayload? {
        let document = try importService.importDocument(at: url)
        let normalized = Self.normalizeText(document.content)
        if Self.isPlaceholderText(normalized) || normalized.isEmpty {
            return nil
        }

        let values = try url.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .localizedNameKey
        ])

        let ext = url.pathExtension.lowercased()
        let sourceType = sourceType(for: ext, documentType: document.type)
        let contentHash = Self.sha256Hex(normalized)
        let category = inferCategory(title: document.title, path: url.path, content: normalized, sourceType: sourceType)
        let ocrConfidence = Double(document.metadata["ocr_confidence"] ?? "")

        // Avoid polluting the index with low-confidence OCR noise from screenshots/scans.
        if sourceType == "image",
           let ocrConfidence,
           ocrConfidence < 0.28,
           normalized.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count < 20 {
            return nil
        }

        let file = IndexedFileRecord(
            id: UUID(),
            title: document.title,
            path: url.path,
            filename: values.localizedName ?? url.lastPathComponent,
            fileExtension: ext,
            sourceType: sourceType,
            category: category,
            contentHash: contentHash,
            fileSize: Int64(values.fileSize ?? 0),
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate,
            lastIndexed: Date(),
            pageCount: Int(document.metadata["page_count"] ?? ""),
            ocrConfidence: ocrConfidence,
            indexVersion: indexVersion,
            embeddingModel: nil,
            embeddingDim: nil
        )

        let pageTexts = Self.decodePageTexts(from: document.metadata["page_texts_json"]) ?? [normalized]

        return IngestedDocumentPayload(file: file, normalizedText: normalized, content: document.content, pageTexts: pageTexts)
    }

    private func sourceType(for ext: String, documentType: DocumentType) -> String {
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext) { return "image" }
        if ext == "pdf" { return "pdf" }
        if ext == "docx" { return "docx" }
        if documentType == .markdown || ext == "md" || ext == "markdown" { return "markdown" }
        if documentType == .text { return "text" }
        return "document"
    }

    private func inferCategory(title: String, path: String, content: String, sourceType: String) -> String? {
        let haystack = "\(title.lowercased()) \(path.lowercased()) \(content.prefix(2500).lowercased())"
        if haystack.contains("resume") || haystack.contains("curriculum vitae") || haystack.contains("education") && haystack.contains("experience") {
            return "resume"
        }
        if haystack.contains("invoice") || haystack.contains("amount due") || haystack.contains("payment") {
            return "invoice"
        }
        if sourceType == "image" && (haystack.contains("screenshot") || haystack.contains("screen")) {
            return "screenshot"
        }
        if haystack.contains("notes") || haystack.contains("meeting") {
            return "notes"
        }
        return nil
    }

    static func normalizeText(_ text: String) -> String {
        let withoutControl = text.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }
            .map(String.init)
            .joined()
        var normalized = withoutControl
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")

        normalized = normalized.replacingOccurrences(
            of: "([A-Za-z])\\-\\n([A-Za-z])",
            with: "$1$2",
            options: String.CompareOptions.regularExpression
        )
        normalized = normalized.replacingOccurrences(of: "[ ]{2,}", with: " ", options: String.CompareOptions.regularExpression)
        normalized = normalized.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: String.CompareOptions.regularExpression)
        return normalized.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    static func isPlaceholderText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        return trimmed == "no text detected in image."
            || trimmed == "no extractable text found in pdf."
            || trimmed == "no preview available."
    }

    static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func decodePageTexts(from value: String?) -> [String]? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
}
