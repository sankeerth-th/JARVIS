# Thread 4: iPhone Foundation (JarvisIOS)

## Product Direction
Jarvis on iPhone is implemented as a fast utility-first assistant, not a command palette port.

- Primary goal: reduce time-to-first-action to a few seconds.
- Entry model: launch to focused home, route into setup if no model is ready, then route into ask/capture/summarize/search/continue.
- Interaction model: touch-first cards/sheets, large tap targets, concise status and feedback.

## Same-Project Architecture
Jarvis remains one Xcode project with separate platform shells:

- `Jarvis` target: macOS AppKit + SwiftUI overlay (`Cmd+J` model).
- `JarvisIOS` target: iPhone-native SwiftUI shell with App Intents.
- Shared iPhone core in `JarvisIOS/Shared` for launch routing, model runtime abstraction, chat domain, and persistence.

### Shared vs Platform-Specific Boundaries
- Shared (portable within iPhone stack in this thread):
  - Launch route parsing/persistence (`JarvisLaunchRoute`, `JarvisLaunchRouteStore`)
  - Chat/domain models (`JarvisChatModels`)
  - Local runtime abstraction (`JarvisLocalModelRuntime`, `JarvisGGUFEngine`)
  - Local conversation/knowledge persistence (`JarvisConversationStore`)
  - Local model import/registry (`JarvisModelLibrary`)
- iPhone-specific:
  - UI shell (`JarvisPhone*View`)
  - Mobile haptics (`JarvisHaptics`)
  - App Intents/App Shortcuts (`JarvisPhoneShortcuts`)
  - Scene lifecycle behavior in `JarvisPhoneAppModel`
- macOS-specific (unchanged in thread 4):
  - `AppDelegate`, menu bar, overlay controller, global hotkey stack
  - AppKit permission and capture surfaces

## Model Import Philosophy
`JarvisIOS` is user-import driven and path-agnostic.

- No hardcoded developer file path.
- User imports model files from Files using native file picker.
- Imported files are copied to app sandbox storage.
- Model metadata + active model selection are persisted in local JSON payload.
- Active model is required before ask/capture/summarize/continue flows.
- Unsupported files are rejected with explicit messaging.

Current supported format:
- `GGUF (.gguf)` only.

Future formats can be added via `JarvisModelFormat` and runtime adapters, but UI copy remains explicit about current GGUF-only support.

## Launch / Shortcut Design
Route-driven quick launch is implemented with `JarvisLaunchRoute` actions:

- `home`
- `ask`
- `quickCapture`
- `summarize`
- `search`
- `continueConversation`

App Intents save a pending route and open the app. On foreground, `JarvisIOS` consumes and applies it. If no active ready model exists, route handling sends user to setup/import flow instead of opening a broken assistant state.

## Local Runtime Boundary
`JarvisLocalModelRuntime` is the iPhone runtime boundary for local GGUF inference.

- State machine: unavailable, cold, loading(progress), ready, generating, paused, failed.
- Runtime now depends on selected imported model from `JarvisModelLibrary`.
- Lifecycle hooks:
  - foreground resume -> restore ready/cold state
  - background -> pause generation
  - memory warning -> unload runtime
- Current engine implementation:
  - `StubGGUFEngine` streams tokens and validates lifecycle + UX behavior.
- Next integration step:
  - replace `StubGGUFEngine` with a real GGUF backend adapter (for example llama.cpp wrapper) behind `JarvisGGUFEngine`.

## UI / Motion Principles
The iPhone shell uses restrained composited effects:

- Layered gradients + material cards for depth
- First-run setup surface with strong import CTA
- Model library with clear active-model status and safety actions
- Smooth sheet/full-screen transitions with minimal layout churn
- Minimal haptics for trigger/success/error
- Explicit setup/import/loading/empty/error states to avoid dead screens

## MVP Scope Delivered
- iPhone target in same project (`JarvisIOS`)
- iPhone-native home/assistant/knowledge/settings shell
- Setup onboarding when no active model exists
- Files-based GGUF import flow
- Local model library with active model selection, delete, and revalidate
- Deep-link/route entry model
- App Intents + App Shortcuts for quick launch and Action button assignment path
- Runtime state machine for local GGUF lifecycle scaffolding
- Conversation persistence + searchable local knowledge snippets

## Known Gaps / Next Steps
- Real GGUF inference binding is not wired yet (`StubGGUFEngine` is active).
- No Share Extension yet for cross-app text intake.
- Voice capture path is text-first in current MVP.
- Shared domain extraction between macOS and iOS can be formalized into a dedicated shared package in a follow-up thread.
