# Jarvis (Offline macOS + iPhone Assistant)

Jarvis is a local-first macOS menu bar assistant built with SwiftUI + AppKit.  
It runs fully offline with Ollama on your Mac and opens with global `Cmd+J`.
The same project now also includes an iPhone-native target (`JarvisIOS`) with App Shortcuts, deep links, and on-device GGUF runtime scaffolding.

## What You Need

- macOS 14+
- Xcode 16+ (Apple Silicon recommended)
- [Ollama](https://ollama.com/) installed locally
- A pulled local model (example: `gemma3:12b`)
- For iPhone target: iOS 17+ simulator/device in Xcode

## Install From GitHub (Clean Setup)

1. Clone:
   ```bash
   git clone <YOUR_GITHUB_REPO_URL> JARVIS
   cd JARVIS
   ```
2. Verify project is readable:
   ```bash
   xcodebuild -list -project Jarvis.xcodeproj
   ```
3. Install/start Ollama and pull a model:
   ```bash
   ollama pull gemma3:12b
   ollama serve
   ```
4. In another terminal, confirm Ollama is reachable:
   ```bash
   curl http://127.0.0.1:11434/api/tags
   ```
5. Open project in Xcode:
   ```bash
   open Jarvis.xcodeproj
   ```

## Xcode Setup (Important)

1. Select scheme:
   - **Jarvis** for macOS menu bar app
   - **JarvisIOS** for iPhone app
2. Select run destination:
   - `My Mac` for `Jarvis`
   - iPhone simulator/device for `JarvisIOS`
3. `Signing & Capabilities`:
   - For target `Jarvis`: choose your Apple Development team.
   - For target `JarvisMailExtension`: use same team.
4. Build once: `Cmd+B`.
5. Run app: `Cmd+R`.

If Xcode asks "Choose an app to run this extension with", you are running the extension scheme by mistake.  
Switch scheme back to `Jarvis`.

## iPhone MVP (Thread 4)

`JarvisIOS` is an iPhone-first shell, not a resized macOS overlay.

- Home screen optimized for fast first action
- First-run setup that requires importing a local model
- Assistant sheet with local model state + streaming UI
- Local knowledge surface (search saved conversation outputs)
- Model Library with active model switching/revalidate/remove
- Settings/status screen for model state and quick-launch guidance
- App Intents + App Shortcuts:
  - Open Jarvis
  - Ask Jarvis
  - Quick Capture
  - Summarize Text
  - Search Local Knowledge
  - Continue Last Conversation

### iPhone Model Import

`JarvisIOS` does not use hardcoded model paths.

- Import model files from Files using the in-app `Import Model` flow.
- Current supported format is `GGUF (.gguf)`.
- Imported files are copied into app sandbox storage and tracked in the in-app model library.
- Set one imported model as active before using Ask/Capture/Summarize actions.

## First Launch Permissions

Grant only what Jarvis needs:

- Accessibility (global hotkey and optional automation)
- Screen Recording (window/area capture for OCR)
- Notifications (priority inbox features)
- File access is user-selected via Open Panel/bookmarks

Then restart Jarvis once after granting permissions.

## Basic Run Checklist

1. Jarvis icon appears in menu bar.
2. Press `Cmd+J` from any app -> overlay opens.
3. Diagnostics tab shows:
   - Ollama: Connected
   - Model: selected and available
4. Import a document in Documents tab and run `Summarize`.

## Retrieval & Search (v2)

Jarvis now uses a unified local retrieval pipeline:

- OCR + text extraction feeds normalized content into a chunk index.
- Indexing stores file metadata (path/type/timestamps/page count/OCR confidence/content hash).
- Search uses intent-aware lexical retrieval + reranking + duplicate suppression.
- Results include lightweight reasoning and optional debug details in the Search tab.

See `/Users/sanks04/Desktop/JARVIS/docs/retrieval-pipeline.md` for architecture details.

## Mail Extension (Optional)

The main app works without this.

To enable and use the extension in Apple Mail:

1. Build and run Jarvis once.
2. Open Mail -> Settings -> Extensions.
3. Enable `JarvisMailExtension` if listed.
4. Open a **new compose** window or click **Reply** on any email.
5. In the compose toolbar, click the **Extensions** button, then select **Jarvis**.
6. The Jarvis panel appears with:
   - `Draft with Jarvis`
   - `Improve tone`
   - `Summarize thread`
7. If thread/body text is limited by MailKit, click `Paste from clipboard` after copying the relevant text.
8. Use `Copy to clipboard`, then paste into the Mail body (`Insert` shows guidance when direct insertion is unavailable).

If it does not appear:

- Ensure both targets are signed with the same non-adhoc Apple Development team.
- Quit and reopen Mail.
- Rebuild Jarvis.
- Open a new compose/reply window after enabling the extension (Mail does not attach already-open compose windows).
- Check Console logs using subsystem `com.offline.Jarvis.MailExtension` to confirm callbacks:
  - `handler(for:) requested`
  - `mailComposeSessionDidBegin`
  - `viewController(for:) requested`

## Troubleshooting

### `Cmd+J` does not work

- Confirm scheme is `Jarvis`.
- Confirm Jarvis is running (menu bar icon visible).
- Re-check Accessibility permission.
- Quit and relaunch Jarvis.

### Ollama "connection refused"

Use:
```bash
curl http://127.0.0.1:11434/api/tags
```

- If it fails, start Ollama:
  ```bash
  ollama serve
  ```
- If `address already in use`, Ollama is already running; do not start a second instance.

### Screen capture keeps asking permission

1. System Settings -> Privacy & Security -> Screen & System Audio Recording.
2. Toggle Jarvis off/on.
3. Quit Jarvis fully and relaunch.

### Search results look stale or repetitive

1. In Search tab, click `Re-index` for configured folders.
2. Enable `Debug ranking` to inspect why each result was ranked.
3. Confirm indexed folders are scoped correctly (All indexed folders vs Single folder).

### "Open Mail" opens browser

Set Apple Mail as default mail app:
Mail -> Settings -> General -> Default email reader.

### Build warning: `not stripping binary because it is signed`

This is a warning only. Build can still succeed.

## Build/Test From Terminal

Build:
```bash
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Debug -destination 'generic/platform=macOS' build
```

iPhone build (simulator, no signing required):
```bash
xcodebuild -project Jarvis.xcodeproj -scheme JarvisIOS -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Run tests:
```bash
xcodebuild test -project Jarvis.xcodeproj -scheme Jarvis -destination 'platform=macOS'
```

## Project Layout

```text
Jarvis.xcodeproj/        Xcode project
Jarvis/                  App source (UI, view models, services)
JarvisMailExtension/     Optional Apple Mail extension target
JarvisTests/             Unit tests
README.md                Setup + usage docs
```

## Publishing New Features Regularly

Recommended flow for each update:

1. Create feature branch:
   ```bash
   git checkout -b codex/<feature-name>
   ```
2. Implement + test (`Cmd+B`, `Cmd+U`).
3. Update `README.md` for user-facing changes.
4. Commit with clear message.
5. Push and open PR to `main`.

Jarvis is designed to stay local-first as features grow: keep network optional and disabled by default.
