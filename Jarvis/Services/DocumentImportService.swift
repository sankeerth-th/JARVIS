import Foundation
import PDFKit
import UniformTypeIdentifiers
import AppKit

final class DocumentImportService {
    private struct ExtractionResult {
        var content: String
        var pageTexts: [String]
        var pageCount: Int?
        var ocrConfidence: Double?
    }

    private let ocrService: OCRService

    init(ocrService: OCRService = OCRService()) {
        self.ocrService = ocrService
    }

    func importDocument(at url: URL) throws -> Document {
        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .localizedNameKey, .typeIdentifierKey])
        let type = documentType(for: url, uti: resourceValues.typeIdentifier)
        let title = resourceValues.localizedName ?? url.deletingPathExtension().lastPathComponent
        let extraction: ExtractionResult
        switch type {
        case .text, .markdown:
            let text = try String(contentsOf: url)
            extraction = ExtractionResult(content: text, pageTexts: [text], pageCount: 1, ocrConfidence: nil)
        case .pdf:
            extraction = try extractPDFText(url: url)
        case .docx:
            let text = try extractDocx(url: url)
            extraction = ExtractionResult(content: text, pageTexts: [text], pageCount: 1, ocrConfidence: nil)
        case .image:
            extraction = try extractImageText(url: url)
        case .unknown:
            let text = try String(contentsOf: url)
            extraction = ExtractionResult(content: text, pageTexts: [text], pageCount: 1, ocrConfidence: nil)
        }
        var metadata: [String: String] = [:]
        if let pageCount = extraction.pageCount {
            metadata["page_count"] = String(pageCount)
        }
        if let ocrConfidence = extraction.ocrConfidence {
            metadata["ocr_confidence"] = String(format: "%.4f", ocrConfidence)
        }
        if let payload = try? JSONEncoder().encode(extraction.pageTexts),
           let encoded = String(data: payload, encoding: .utf8) {
            metadata["page_texts_json"] = encoded
        }
        return Document(
            url: url,
            type: type,
            title: title,
            content: extraction.content,
            lastModified: resourceValues.contentModificationDate,
            metadata: metadata
        )
    }

    func importText(_ string: String, type: DocumentType = .text, title: String = "Clipboard") -> Document {
        Document(type: type, title: title, content: string, lastModified: Date())
    }

    func openPanelToSelectDocuments(allowsMultiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultiple
        panel.allowedContentTypes = [.plainText, .pdf, .rtf, .text, .image, .init(filenameExtension: "md")!, .init(filenameExtension: "docx")!]
        panel.prompt = "Import"
        let response = panel.runModal()
        guard response == .OK else { return [] }
        return panel.urls
    }

    private func documentType(for url: URL, uti: String?) -> DocumentType {
        if url.pathExtension.lowercased() == "md" { return .markdown }
        if url.pathExtension.lowercased() == "pdf" { return .pdf }
        if url.pathExtension.lowercased() == "docx" { return .docx }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(url.pathExtension.lowercased()) { return .image }
        if url.pathExtension.lowercased() == "txt" { return .text }
        if let uti,
           let type = UTType(uti),
           type.conforms(to: .pdf) { return .pdf }
        if let uti,
           let type = UTType(uti),
           type.conforms(to: .image) { return .image }
        if let uti, let type = UTType(uti), type.conforms(to: .plainText) { return .text }
        return .unknown
    }

    private func extractDocx(url: URL) throws -> String {
        let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        return attributed.string
    }

    private func extractImageText(url: URL) throws -> ExtractionResult {
        guard let image = NSImage(contentsOf: url) else {
            throw NSError(domain: "Jarvis", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to load image"])
        }
        let ocr = try ocrService.recognize(from: image, applyPreprocessing: true)
        let text = ocr.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return ExtractionResult(content: "", pageTexts: [], pageCount: 1, ocrConfidence: ocr.averageConfidence)
        }
        return ExtractionResult(content: text, pageTexts: [text], pageCount: 1, ocrConfidence: ocr.averageConfidence)
    }

    private func extractPDFText(url: URL) throws -> ExtractionResult {
        guard let pdf = PDFDocument(url: url) else {
            throw NSError(domain: "Jarvis", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to load PDF"])
        }
        var pageChunks: [String] = []
        var pageTexts: [String] = []
        var confidenceValues: [Double] = []
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pageText.count >= 40 {
                pageChunks.append(pageText)
                pageTexts.append(pageText)
                continue
            }
            if let image = pageImage(page),
               let ocr = try? ocrService.recognize(from: image, applyPreprocessing: true),
               !ocr.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ocrText = ocr.text.trimmingCharacters(in: .whitespacesAndNewlines)
                pageChunks.append(ocrText)
                pageTexts.append(ocrText)
                confidenceValues.append(ocr.averageConfidence)
            } else if !pageText.isEmpty {
                pageChunks.append(pageText)
                pageTexts.append(pageText)
            }
        }
        let merged = pageChunks.joined(separator: "\n")
        let confidence = confidenceValues.isEmpty ? nil : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        return ExtractionResult(
            content: merged.trimmingCharacters(in: .whitespacesAndNewlines),
            pageTexts: pageTexts,
            pageCount: pdf.pageCount,
            ocrConfidence: confidence
        )
    }

    private func pageImage(_ page: PDFPage) -> NSImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let targetWidth = min(bounds.width, 1600)
        let scale = targetWidth / bounds.width
        let targetSize = NSSize(width: targetWidth, height: bounds.height * scale)
        return page.thumbnail(of: targetSize, for: .mediaBox)
    }
}
