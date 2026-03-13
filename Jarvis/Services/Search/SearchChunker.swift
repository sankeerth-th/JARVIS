import Foundation

final class SearchChunker {
    func chunk(payload: IngestedDocumentPayload) -> [IndexedChunkRecord] {
        if payload.file.sourceType == "pdf", !payload.pageTexts.isEmpty {
            return chunkPDF(payload: payload)
        }
        if payload.file.sourceType == "image" || payload.file.sourceType == "screenshot" {
            return chunkOCRText(payload: payload)
        }
        return chunkTextual(payload: payload)
    }

    private func chunkTextual(payload: IngestedDocumentPayload) -> [IndexedChunkRecord] {
        let paragraphs = payload.normalizedText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return buildChunks(paragraphs: paragraphs, fileID: payload.file.id, page: nil, targetLength: 700, overlapSentences: 1)
    }

    private func chunkPDF(payload: IngestedDocumentPayload) -> [IndexedChunkRecord] {
        var chunks: [IndexedChunkRecord] = []
        var ordinal = 0
        for (pageIndex, pageText) in payload.pageTexts.enumerated() {
            let normalized = SearchIngestionService.normalizeText(pageText)
            guard !normalized.isEmpty else { continue }
            let paragraphs = normalized
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let pageChunks = buildChunks(paragraphs: paragraphs, fileID: payload.file.id, page: pageIndex + 1, targetLength: 620, overlapSentences: 1)
            for chunk in pageChunks {
                chunks.append(
                    IndexedChunkRecord(
                        id: chunk.id,
                        fileID: chunk.fileID,
                        ordinal: ordinal,
                        page: chunk.page,
                        chunkHash: chunk.chunkHash,
                        text: chunk.text,
                        normalizedText: chunk.normalizedText,
                        embedding: nil,
                        embeddingModel: nil,
                        embeddingDim: nil
                    )
                )
                ordinal += 1
            }
        }
        return chunks
    }

    private func chunkOCRText(payload: IngestedDocumentPayload) -> [IndexedChunkRecord] {
        let lines = payload.normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var groups: [String] = []
        var current: [String] = []
        for line in lines {
            current.append(line)
            if current.count >= 4 {
                groups.append(current.joined(separator: " "))
                if current.count > 2 {
                    current = Array(current.suffix(2)) // keep context overlap
                }
            }
        }
        if !current.isEmpty {
            groups.append(current.joined(separator: " "))
        }
        return buildChunks(paragraphs: groups, fileID: payload.file.id, page: nil, targetLength: 420, overlapSentences: 1)
    }

    private func buildChunks(paragraphs: [String], fileID: UUID, page: Int?, targetLength: Int, overlapSentences: Int) -> [IndexedChunkRecord] {
        var chunks: [IndexedChunkRecord] = []
        var buffer: [String] = []
        var ordinal = 0

        func flush() {
            let text = buffer.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let normalized = SearchIngestionService.normalizeText(text)
            let hash = SearchIngestionService.sha256Hex(normalized)
            chunks.append(
                IndexedChunkRecord(
                    id: UUID(),
                    fileID: fileID,
                    ordinal: ordinal,
                    page: page,
                    chunkHash: hash,
                    text: text,
                    normalizedText: normalized,
                    embedding: nil,
                    embeddingModel: nil,
                    embeddingDim: nil
                )
            )
            ordinal += 1

            if overlapSentences > 0 {
                let tail = text
                    .split(separator: ".")
                    .suffix(overlapSentences)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                buffer = tail
            } else {
                buffer.removeAll(keepingCapacity: true)
            }
        }

        for paragraph in paragraphs {
            buffer.append(paragraph)
            let length = buffer.reduce(0) { $0 + $1.count }
            if length >= targetLength {
                flush()
            }
        }
        flush()

        var seenHashes: Set<String> = []
        return chunks.filter { chunk in
            if seenHashes.contains(chunk.chunkHash) { return false }
            seenHashes.insert(chunk.chunkHash)
            return true
        }
    }
}
