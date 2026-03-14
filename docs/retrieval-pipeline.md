# Retrieval Pipeline (v2)

Jarvis uses a local-only retrieval pipeline for OCR ingestion, indexing, and search ranking.

## Flow

1. **Ingestion** (`SearchIngestionService`)
   - Loads files from configured folders.
   - Uses `DocumentImportService` for text extraction.
   - Uses Vision OCR (local) for images/scanned PDF pages.
   - Normalizes text and computes `contentHash`.
   - Persists file metadata: path, filename, extension, size, created/modified, page count, OCR confidence, inferred category.

2. **Chunking** (`SearchChunker`)
   - `txt/md/docx`: paragraph-aware chunks.
   - `pdf`: page-aware chunks.
   - OCR-heavy image/screenshot text: smaller overlapping chunks.
   - Each chunk stores provenance (`fileID`, ordinal, page) and `chunkHash`.

3. **Indexing** (`JarvisDatabase` v2 tables)
   - `indexed_files_v2`: file-level metadata and dedup keys.
   - `indexed_chunks_v2`: chunk storage.
   - `indexed_chunks_fts_v2`: lexical retrieval via SQLite FTS5.
   - `search_runs_v2`: query intent, strategy, latency, debug summary.

4. **Query understanding** (`SearchQueryAnalyzer`)
   - Classifies query intent: filename/content/recent/OCR/exact phrase/broad semantic.
   - Produces a retrieval strategy and FTS query.

5. **Retrieval + rerank** (`SearchRanker`)
   - Candidate generation from FTS (and broad fallback if needed).
   - Scoring uses lexical score, filename/path relevance, metadata fit, recency, OCR confidence, and optional semantic similarity when embedding dimensions/model match.
   - Diversity pass keeps best chunk per file, enforces deterministic ordering, and suppresses duplicate content hashes.

6. **Result output**
   - Returns file-level results with snippet, score, and "why this result" reasons.
   - Optional debug summary is exposed in Search UI.

## Duplicate suppression logic

- **File-level dedup during indexing**: skip reindex when `contentHash + fileSize + modifiedAt` unchanged.
- **Chunk-level dedup**: remove duplicate `chunkHash` per file.
- **Result-level dedup**: same-file chunk flooding is prevented; repeated content hashes are suppressed for non-filename intents.

## Search observability

- Ingestion events, search runs, and failures are stored as `feature_events`.
- Search strategy and latency snapshots are stored in `search_runs_v2`.
- UI debug mode exposes per-result score contributions (lexical/filename/metadata/recency/OCR/duplicate adjustments).

## Migration / compatibility

- v2 schema is additive; existing `indexed_documents` remains for fallback compatibility.
- `search_index_version` in `index_meta` controls deterministic rebuild behavior.
- If version changes, v2 tables are rebuilt; legacy table is untouched.

## Extending semantic search later

- Chunk embeddings are optional fields in `indexed_chunks_v2`.
- Semantic scoring is active only when query embedding and chunk embedding are model/dimension compatible.
- This avoids mixing hashed fallback vectors with real Ollama embeddings.
