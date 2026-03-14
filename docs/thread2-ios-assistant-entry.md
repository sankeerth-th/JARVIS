# Thread 2: iOS Assistant Entry Foundation

## Current isolated work
- Added a reusable speech layer in [`JarvisIOS/Shared/Voice/JarvisSpeechCoordinator.swift`](/Users/sanks04/Desktop/JARVIS/JarvisIOS/Shared/Voice/JarvisSpeechCoordinator.swift).
- Added focused tests in [`JarvisIOSTests/JarvisSpeechCoordinatorTests.swift`](/Users/sanks04/Desktop/JARVIS/JarvisIOSTests/JarvisSpeechCoordinatorTests.swift).

## Speech foundation shape
- `JarvisSpeechCoordinator` is the app-facing state machine for voice capture.
- `JarvisSpeechRecognitionClient` is the boundary between UI/app state and the live `Speech` + `AVAudioSession` + `AVAudioEngine` stack.
- The coordinator owns:
  - permission flow
  - speech state (`idle`, `requestingPermission`, `ready`, `listening`, `transcribing`, `stopping`, `failed`)
  - transcript accumulation
  - silence-based auto-send
  - stale session suppression
- The live client owns:
  - microphone permission
  - speech recognition permission
  - audio session activation/deactivation
  - audio engine tap lifecycle
  - recognition task lifecycle

## Integration points for the next pass
- Replace the current preview-only voice path in [`JarvisIOS/JarvisPhoneAppModel.swift`](/Users/sanks04/Desktop/JARVIS/JarvisIOS/JarvisPhoneAppModel.swift) with the coordinator.
- Bind assistant UI in [`JarvisIOS/Views/Modern/AssistantTabView.swift`](/Users/sanks04/Desktop/JARVIS/JarvisIOS/Views/Modern/AssistantTabView.swift) to coordinator state instead of synthetic `startVoicePreview()` / `stopVoicePreview()`.
- Add target privacy strings for:
  - microphone usage
  - speech recognition usage
- Route `voiceInput` launch actions into:
  - assistant tab selection
  - composer focus handling
  - optional auto-start listening

## Current verification status
- Narrow iOS SDK type-check for `JarvisSpeechCoordinator.swift`: passed.
- Full iOS target/test build: currently blocked by an existing package issue in `swift-jinja` (`OrderedCollections` module resolution), unrelated to the speech layer.
