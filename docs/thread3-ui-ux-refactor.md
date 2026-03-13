# Jarvis Thread 3 UI/UX Refactor Notes

## UI direction
Jarvis now follows a restrained, native-leaning macOS workspace style:
- calm dark surfaces with subtle depth
- clear hierarchy between shell, navigation, and task content
- sparse accent usage for primary actions and active state
- keyboard-first behavior preserved without aggressive visual treatment

## Shell structure
The overlay shell is organized as:
1. Header toolbar: product identity, privacy status, model selector, logging toggle, global actions
2. Sidebar navigation: stable section list for all major modules
3. Primary content pane: task-focused view for the active module
4. Compact mode: focused quick-ask entry point that expands into full workspace

## Design primitives introduced
`JarvisDesignSystem.swift` defines:
- spacing/radius tokens (`JarvisSpacing`, `JarvisRadius`)
- typography tokens (`JarvisTypography`)
- surface/border/accent tokens (`JarvisPalette`, `JarvisBorderStrength`)
- button variants (`JarvisButtonStyle`, `JarvisButtonTone`)
- sidebar selection style (`JarvisSidebarTabStyle`)
- reusable panel and input modifiers (`jarvisCard`, `jarvisInputContainer`)
- section and status components (`JarvisSectionHeader`, `JarvisStatusBadge`)
- reusable state rows (`JarvisStatusRow`, `JarvisPermissionRow`, `JarvisResultRow`, `JarvisEmptyStateRow`, `JarvisLoadingRow`)

## Responsive shell behavior
Overlay widths map to three profiles:
- `< 980`: focus mode (compact quick-ask only; no sidebar, no utility pane)
- `980-1179`: compact workspace (160pt sidebar, 268pt chat utility pane)
- `>= 1180`: full workspace (196pt sidebar, 320pt chat utility pane)

## Component naming map (Figma-ready)
Use these names for design handoff consistency:
- `Shell/Window`
- `Shell/HeaderToolbar`
- `Shell/SidebarNav/Item`
- `Shell/ContentPane`
- `Chat/ConversationRow/User`
- `Chat/ConversationRow/Assistant`
- `Chat/InputComposer`
- `Search/ResultRow`
- `Search/ScopeBanner`
- `Document/StageCard/Source`
- `Document/StageCard/Action`
- `Document/StageCard/Output`
- `Diagnostics/ServiceRow`
- `Diagnostics/ModuleRow`
- `Privacy/EventRow`
- `State/StatusBanner/{Info|Warning|Error|Success}`
- `State/EmptyRow`
- `State/LoadingRow`
- `Controls/Button/{Primary|Secondary|Danger|Tertiary|Text}`

State variants:
- `default`, `selected`, `focused`, `disabled`, `loading`, `error`.

Spacing rules:
- use token steps only: `6`, `10`, `14`, `20`.
- one dominant primary action per section; secondary actions grouped to the right.

## Intentional simplifications
- Removed glow-heavy and concept-style styling from the overlay shell
- Replaced horizontal chip tab rail with stable sidebar navigation
- Reduced competing panel treatments by using one consistent card language
- Standardized status/loading/empty/result row patterns across major screens

## How to keep future screens consistent
When adding a new screen:
1. Start with `JarvisSectionHeader` for purpose clarity
2. Use `jarvisCard` for grouped surfaces and avoid custom ad hoc panel chrome
3. Use `JarvisButtonStyle` tones for action hierarchy:
   - `primary` for the main action
   - `secondary` for supporting actions
   - `danger` only for destructive actions
4. Keep one dominant content region and avoid parallel competing panels
5. Prefer list/detail patterns and native controls over decorative custom UI

## Out of scope for this thread
- Search/indexing reliability internals
- OCR pipeline behavior changes
- Chat routing/state architecture
- Mail extension internals
- Permission engine rewrites
