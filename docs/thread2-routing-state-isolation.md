# Thread 2 Routing and State Isolation

## Request Flow
1. `CommandPaletteViewModel.send(prompt:requestedAction:)` builds a `RouteSignal` from active tab, quick action context, and local state.
2. `IntentClassifier` deterministically classifies prompt intent.
3. `RoutePlanner` builds a typed `RoutePlan` with:
   - intent
   - prompt template
   - memory scope
   - allowed tools
   - output destination
   - streaming policy
4. View model logs route diagnostics (`feature=Routing`) and starts a `StreamRequest` via `StreamOwnershipController`.
5. User/tool/assistant messages are tagged with route metadata (`requestID`, `intent`, `promptTemplate`, `memoryScope`, `source`).
6. `ConversationService.streamResponse` receives `RoutePlan`, builds route-specific system prompt, injects only permitted context, scopes conversation history by `memoryScope`, and streams from Ollama.
7. Stream chunks are accepted only if ownership matches the active request ID.

## State Ownership
- UI tab/navigation state stays in `CommandPaletteViewModel.selectedTab`.
- Route execution state is request-scoped in `StreamOwnershipController.activeRequest`.
- Stream display state is isolated with `isStreamingSelectedConversation`, `visibleStreamingBuffer`, and `visibleThinkingStatus`.
- Tool confirmations are request-scoped using `pendingToolRequestID`.

## Memory Scopes
`MemoryScope` is explicit in `RoutePlan`:
- `chatThread`
- `searchTransient`
- `documentTask`
- `ocrTask`
- `mailSession`
- `diagnosticsTask`
- `macroTask`
- `reflectiveScratch`
- `explanationScratch`
- `quickActionTransient`

The context builder now respects `RouteContextPolicy`, so document/search/mail/notifications context is injected only for matching routes.
Conversation history is also scoped through `ConversationScopeFilter`:
- `chatThread` includes chat-tagged + legacy untagged history, but excludes explicitly transient scopes.
- Non-chat scopes include only matching-scope turns, plus a fallback latest user turn for legacy conversations.

## Prompt Boundaries
Prompt construction is route-template driven (`PromptTemplateID`):
- `generalChat`
- `searchAssistant`
- `documentRewrite`
- `ocrInterpreter`
- `mailDraft`
- `diagnostics`
- `reflective`
- `explanation`
- `quickAction`

`ConversationService` includes only route-approved tool instructions. Routes with no tools explicitly forbid tool syntax.

## Tool Access Control
Before any parsed tool invocation executes, `CommandPaletteViewModel.consume(...)` checks the active route allowlist. Disallowed tools are blocked and logged (`type=tool.blocked`).

## Stream Lifecycle and Cancellation
- Starting a new request cancels existing stream ownership (`stream.cancelled`).
- Each stream has a unique `requestID` and bound `conversationID`.
- Tokens are ignored if request ownership is stale.
- Completion only persists when the request still owns the stream.
- Switching conversations while streaming cancels active request to avoid cross-thread contamination.

## Diagnostics and Debugging
Routing logs are persisted to `feature_events` under feature `Routing` with event types:
- `route.selected`
- `stream.cancelled`
- `stream.completed`
- `tool.executed`
- `tool.blocked`
- `tool.rejected`
- `tool.error`

Diagnostics UI now shows a "Routing Events" section, and the command palette shows a short route summary banner for immediate debugging.
