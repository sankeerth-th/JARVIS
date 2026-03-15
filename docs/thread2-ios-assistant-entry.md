# Thread 2: iOS Assistant Entry, Voice, and Shortcut Architecture

## Scope
- Thread 2 owns assistant entry, voice capture, App Intents/App Shortcuts, and iPhone-specific assistant flow.
- Thread 1 remains the owner of local model import/runtime internals.
- The iOS assistant layer now treats runtime readiness as a hard gate before it will send or auto-send requests.

## Assistant Entry Router
- `JarvisLaunchRoute` is the single serialized handoff contract for:
  - App Intents / App Shortcuts
  - deep links
  - in-app quick actions
  - legacy bridge calls
- Supported assistant entry routes:
  - `assistant`
  - `chat`
  - `voice`
  - `visual`
  - `knowledge`
  - `draftReply`
  - `continueConversation`
  - `systemAssistant`
- `JarvisPhoneAppModel` is the sole consumer of launch routes and owns:
  - selected tab
  - active assistant route
  - assistant task
  - assistant task context
  - pending model-library presentation
  - voice auto-start behavior

## Runtime-First Gate
- Assistant entry no longer assumes the runtime is usable.
- The app model derives explicit gate states before sending:
  - `noModel`
  - `unsupportedModel`
  - `fileAccessPending`
  - `fileAccessLost`
  - `runtimeCold`
  - `warming`
  - `ready`
  - `failed`
- Assistant UI uses those states to decide whether to:
  - allow send
  - present warmup
  - show model-library recovery
  - explain why a route is unavailable

## Assistant State Model
- `AssistantExperienceState` now models the full assistant lifecycle:
  - `idle`
  - `armed`
  - `listening`
  - `transcribing`
  - `thinking`
  - `processing`
  - `grounding`
  - `responding`
  - `answerReady`
  - `error`
  - `unavailable`
- `AssistantEntryStyle` differentiates entry surfaces:
  - `standard`
  - `assistant`
  - `chat`
  - `quickAsk`
  - `quickCapture`
  - `draftReply`
  - `summarize`
  - `continueConversation`
  - `voiceFirst`
  - `visualPreview`
  - `systemAssistant`
- `JarvisAssistantTask` now drives prompt shaping and UI expectations:
  - `chat`
  - `summarize`
  - `reply`
  - `draftEmail`
  - `analyzeText`
  - `visualDescribe`
  - `prioritizeNotifications`
  - `quickCapture`
  - `knowledgeAnswer`

## Voice Pipeline
- `JarvisSpeechCoordinator` remains the speech engine boundary over:
  - `Speech`
  - `AVAudioSession`
  - `AVAudioEngine`
  - `SFSpeechRecognizer`
- The assistant layer maps speech output into assistant state transitions:
  - route enters voice mode
  - runtime gate validates availability
  - coordinator requests permission / starts transcription
  - live transcript updates assistant transcript state
  - silence detection commits transcript
  - committed transcript goes through the normal assistant send path
  - streamed model output shows in the same conversation surface
- Voice settings now include:
  - auto-start listening for voice entry
  - auto-send after speech pause
  - speech locale identifier

## Shortcuts and Intents
- `JarvisPhoneShortcuts.swift` now exposes thin route-writing intents instead of direct navigation logic.
- Current intents:
  - `OpenJarvisIntent`
  - `OpenAssistantIntent`
  - `AskJarvisIntent`
  - `VoiceJarvisIntent`
  - `VisualJarvisIntent`
  - `DraftReplyIntent`
  - `QuickCaptureIntent`
  - `SummarizeTextIntent`
  - `OpenKnowledgeIntent`
  - `SearchLocalKnowledgeIntent`
  - `OpenModelLibraryIntent`
  - `ContinueConversationIntent`
- Each intent:
  - sets `openAppWhenRun = true`
  - writes one `JarvisLaunchRoute`
  - lets the app model resolve navigation after launch

## Visual Soft Preview
- Visual entry remains visible, but the app is explicit that this is a staged preview.
- The assistant checks model capability flags before presenting it as ready.
- If visual runtime support is not available, the route stays honest:
  - preview state only
  - clear unavailable reason
  - no fake image-inference claim

## Supported Model Product Shape
- `JarvisSupportedModelCatalog` now classifies imported models as:
  - `primaryRecommended`
  - `secondarySupported`
  - `importOnly`
  - `unsupported`
- Current product messaging:
  - primary recommendation: `Gemma 3 4B IT Q4_0`
  - secondary supported fallback: `Llama 3.2 1B Instruct 4-bit`
  - generic GGUF imports remain bookmarkable but are not presented as equal activation targets on iPhone
- Model library and assistant recovery UI surface the compatibility class and capability summary.

## Verification
- iOS app build:
  - `xcodebuild -project Jarvis.xcodeproj -scheme JarvisIOS -destination 'platform=iOS Simulator,name=iPhone 17' build`
- The shared `JarvisIOS` scheme now includes `JarvisIOSTests` in its test action.
- Real local inference validation still requires a physical iPhone:
  - simulator build success is necessary
  - runtime import/warmup/streaming must still be confirmed on-device

## Real-Device Validation Checklist
- Import the primary recommended model on an iPhone.
- Activate it and warm it successfully.
- Launch assistant from:
  - app UI
  - shortcut
  - deep link
  - voice entry
- Confirm:
  - route lands in the intended surface
  - voice auto-send works after pause
  - warmup and failure states are explicit
  - visual route stays in preview/unavailable mode when vision support is absent
