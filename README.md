# Jarvis (Local-First Siri Alternative)

Jarvis is a SwiftUI + AppKit macOS 14+ menu bar app that turns your Mac into a fully offline personal assistant powered by the local Ollama runtime. It focuses on privacy (no cloud calls), actionable summaries, and faster workflows triggered from a global `⌘J` overlay.

## Highlights
- **Offline by design:** Every interaction stays on-device. Jarvis talks to Ollama over `http://localhost:11434` and never uploads text or screenshots.
- **Menu bar + overlay palette:** Runs as a background accessory app with a Carbon-backed global hotkey. Press `⌘J` anywhere to open the command palette, search history, trigger skills, or run workflows.
- **Rich skills:**
  - Notes/docs summarization for TXT/MD/PDF/DOCX (PDFKit + NSAttributedString reader).
  - Priority inbox that ingests forwarded notifications, applies quiet hours + keyword rules, and proposes drafts.
  - Email drafting from OCR’d screenshots (Vision framework + Screen Recording permissions).
  - Table extractor with Markdown/CSV/JSON export plus a deterministic smart calculator.
  - Clipboard watcher (optional) that surfaces quick actions like grammar fixes, checklist conversion, and meeting recaps.
  - Local knowledge base with SQLite embeddings (Ollama’s `/api/embeddings`) or keyword fallback plus semantic search UI.
  - Workflow macros (“skills”) that chain summaries, doc lookups, and prompts for automations such as daily wrap-ups.
- **Tool calling safety:** The assistant only performs sensitive actions (OCR, file reads, notification lookups) after explicit approval in the overlay.
- **Diagnostics + privacy controls:** Clear history, disable logging, see permission status, and get “start Ollama” guidance if the daemon isn’t reachable.

## Quick Start
1. **Install dependencies**
   ```bash
   brew install swiftlint # optional
   curl -fsSL https://ollama.com/install.sh | sh
   ollama pull mistral
   ```
2. **Open the project**
   ```bash
   open Jarvis.xcodeproj
   ```
3. **Select the `Jarvis` scheme** → run on macOS 14+ (Apple Silicon recommended).
4. **First launch onboarding**
   - Grant *Accessibility* (global hotkey / notification scraping helper).
   - Grant *Screen Recording* for screenshot-to-email drafting.
   - Approve *Notifications* so Jarvis can show prioritised digests.
5. **Start Ollama** if it isn’t running already:
   ```bash
   ollama serve
   ```
   The overlay shows a red banner and “Retry” button until the API responds.

## Building Blocks
- **Architecture:** MVVM + service layer. Core services live under `Jarvis/Services` (Ollama client, document import, OCR, screenshot capture, notification rules, knowledge index, workflows, calculator, permissions, etc.). View models orchestrate context assembly per tab, while SwiftUI views render the command palette, diagnostics, settings, and skill panes. Persistence uses a handcrafted SQLite wrapper (`JarvisDatabase`) with WAL mode for conversations, macros, and indexed documents.
- **Overlay & hotkey:** `HotKeyCenter` registers CMD+J via Carbon so it works globally. `OverlayWindowController` keeps the translucent SwiftUI palette centered on the user’s current display and remembers window geometry.
- **Tool protocol:** `ConversationService` injects a system prompt instructing Ollama to emit `<<tool{"name":"…"}>>` payloads. `CommandPaletteViewModel` parses the stream, asks for confirmation when needed, and delegates to `ToolExecutionService` for calculator/notification/doc search/OCR helpers.
- **Document pipeline:** `DocumentImportService` handles text, Markdown, PDF (PDFKit), and DOCX (NSAttributedString). Results feed into quick actions (summaries, grammar fixes, table extraction) and the local knowledge base.
- **Knowledge base:** `LocalIndexService` indexes user-selected folders. When embeddings are unavailable, it falls back to keyword vectors so search still works offline.
- **Notifications:** `NotificationService` listens for forwarded notifications (via `DistributedNotificationCenter` signal “com.jarvis.forwardedNotification”) and enriches them with keyword + quiet-hour rules. `NotificationsView` lets you tweak focus mode, add keyword → priority mappings, and copy summaries.
- **Workflows & macros:** Stored in SQLite and editable in the Macros tab. Each step can run prompts, summarize notifications, or pull context from the indexed knowledge base, making it easy to create “Daily wrap-up” or “Code review” recipes.
- **Calculator & tables:** Smart calculator uses deterministic parsing plus `NSExpression`, with unit tests. Table extraction infers delimiters, returns Markdown/CSV/JSON, and is driveable from OCR text/clipboard.

## Permissions & Privacy
Jarvis is careful about data flow:
- **No screenshots stored** — OCR runs in-memory and drafts keep only extracted text.
- **History controls** — “Clear History” removes conversations, and “Disable logging” stops persistence altogether.
- **Selective clipboard watcher** — opt-in via Settings. Toggle off to immediately stop polling.
- **Tool approvals** — Screen capture, notification listing, and doc searches require a manual “Approve” button press inside the overlay.

## Extending Jarvis Skills
- **Add quick actions:** Edit `AppSettings.quickActions` defaults or expose new buttons in `CommandPaletteView`.
- **New documents:** Implement another importer inside `DocumentImportService` and wire actions through `CommandPaletteViewModel.importDocuments`.
- **New tools:** Extend `ToolInvocation.ToolName`, update the system prompt, and teach `ToolExecutionService` how to run the action (plus whether confirmation is needed).
- **Workflow macros:** Each `MacroStep` can call prompts or internal services. Add new step kinds (e.g., calendar/Reminders) by enriching `WorkflowEngine`.

## Testing & QA
1. **Unit tests** (calculator, table parser, settings persistence): `⌘U` or `xcodebuild test -scheme Jarvis -destination 'platform=macOS'`.
2. **Manual test plan**
   - Launch app → ensure menu bar icon replaces Dock.
   - Press `⌘J` on multiple displays; overlay follows cursor display.
   - Toggle privacy banner by stopping/starting `ollama serve`.
   - Import sample PDFs/DOCX and run each document action (summary/bullets/grammar/table).
   - Simulate notification ingestion via `DistributedNotificationCenter` or share extension, confirm priority buckets + keyword overrides.
   - Run “Draft email reply” on a captured Messages/Mail window and adjust tone buttons.
   - Add folders to the knowledge base, verify search results appear with semantic matches.
   - Enable clipboard watcher, copy text, trigger quick actions, then disable watcher.
   - Create/run/delete macros, verifying the execution log updates.
   - Visit Diagnostics tab to ensure permissions + latency values update.

## Folder Map
```
Jarvis.xcodeproj/           Xcode project
Jarvis/                     App sources (SwiftUI + services + resources)
JarvisTests/                Unit tests + Info.plist
README.md                   This file
```

Jarvis is intentionally self-contained: no CocoaPods/SPM dependencies are required beyond the system SDK and the local Ollama server. EOF
