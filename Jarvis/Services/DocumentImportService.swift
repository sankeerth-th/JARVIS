import Foundation
import PDFKit
import UniformTypeIdentifiers
import AppKit

final class DocumentImportService {
    func importDocument(at url: URL) throws -> Document {
        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .localizedNameKey, .typeIdentifierKey])
        let type = documentType(for: url, uti: resourceValues.typeIdentifier)
        let title = resourceValues.localizedName ?? url.deletingPathExtension().lastPathComponent
        let content: String
        switch type {
        case .text, .markdown:
            content = try String(contentsOf: url)
        case .pdf:
            guard let pdf = PDFDocument(url: url) else { throw NSError(domain: "Jarvis", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to load PDF"])}
            content = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        case .docx:
            content = try Self.extractDocx(url: url)
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
        panel.allowedContentTypes = [.plainText, .pdf, .rtf, .text, .init(filenameExtension: "md")!, .init(filenameExtension: "docx")!]
        panel.prompt = "Import"
        let response = panel.runModal()
        guard response == .OK else { return [] }
        return panel.urls
    }

    private func documentType(for url: URL, uti: String?) -> DocumentType {
        if url.pathExtension.lowercased() == "md" { return .markdown }
        if url.pathExtension.lowercased() == "pdf" { return .pdf }
        if url.pathExtension.lowercased() == "docx" { return .docx }
        if url.pathExtension.lowercased() == "txt" { return .text }
        if let uti,
           let type = UTType(uti),
           type.conforms(to: .pdf) { return .pdf }
        if let uti, let type = UTType(uti), type.conforms(to: .plainText) { return .text }
        return .unknown
    }

    private static func extractDocx(url: URL) throws -> String {
        let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        return attributed.string
    }
}
