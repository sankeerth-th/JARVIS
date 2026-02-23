# Jarvis (Offline macOS Assistant)

Jarvis is a local-first macOS menu bar assistant built with SwiftUI + AppKit.  
It runs fully offline with Ollama on your Mac and opens with global `Cmd+J`.

## What You Need

- macOS 14+
- Xcode 16+ (Apple Silicon recommended)
- [Ollama](https://ollama.com/) installed locally
- A pulled local model (example: `gemma3:12b`)

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

1. Select scheme: **Jarvis** (not `JarvisMailExtension`).
2. Select run destination: **My Mac**.
3. `Signing & Capabilities`:
   - For target `Jarvis`: choose your Apple Development team.
   - For target `JarvisMailExtension`: use same team.
4. Build once: `Cmd+B`.
5. Run app: `Cmd+R`.

If Xcode asks "Choose an app to run this extension with", you are running the extension scheme by mistake.  
Switch scheme back to `Jarvis`.

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
