import Foundation
import PDFKit
import UniformTypeIdentifiers
import AppKit

final class DocumentImportService {
    private let ocrService: OCRService

    init(ocrService: OCRService = OCRService()) {
        self.ocrService = ocrService
    }

    func importDocument(at url: URL) throws -> Document {
        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .localizedNameKey, .typeIdentifierKey])
        let type = documentType(for: url, uti: resourceValues.typeIdentifier)
        let title = resourceValues.localizedName ?? url.deletingPathExtension().lastPathComponent
        let content: String
        switch type {
        case .text, .markdown:
            content = try String(contentsOf: url)
        case .pdf:
            content = try extractPDFText(url: url)
        case .docx:
            content = try extractDocx(url: url)
        case .image:
            content = try extractImageText(url: url)
        case .unknown:
            content = try String(contentsOf: url)
        }
        return Document(url: url, type: type, title: title, content: content, lastModified: resourceValues.contentModificationDate)
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

    private func extractImageText(url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url) else {
            throw NSError(domain: "Jarvis", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to load image"])
        }
        let text = try ocrService.recognizeText(from: image).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "No text detected in image."
        }
        return text
    }

    private func extractPDFText(url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw NSError(domain: "Jarvis", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to load PDF"])
        }
        var pageChunks: [String] = []
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pageText.count >= 40 {
                pageChunks.append(pageText)
                continue
            }
            if let image = pageImage(page),
               let ocrText = try? ocrService.recognizeText(from: image).trimmingCharacters(in: .whitespacesAndNewlines),
               !ocrText.isEmpty {
                pageChunks.append(ocrText)
            } else if !pageText.isEmpty {
                pageChunks.append(pageText)
            }
        }
        let merged = pageChunks.joined(separator: "\n")
        if merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No extractable text found in PDF."
        }
        return merged
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
