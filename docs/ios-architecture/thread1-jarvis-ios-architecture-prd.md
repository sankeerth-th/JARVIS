# PRD: JARVIS iOS Assistant Architecture Direction

## Document Status
Distilled architecture PRD based on the current JARVIS iOS codebase and concepts learned from the temporary `OpenJarvis-main` reference corpus. This PRD is JARVIS-native and should remain valid after that folder is deleted.

## Problem
JARVIS iOS has a working local assistant stack, but its long-term architecture risks drifting into either:
- a thin chat wrapper over local inference, or
- an overbuilt clone of a general-purpose agent platform

Neither is correct for an on-device iPhone assistant.

JARVIS needs a stable assistant control plane that:
- keeps the app local-first and Apple-native
- supports future actions and memory without requiring platform sprawl
- remains observable and safe
- stays compatible with a constrained iPhone runtime

## Product Goal
Create a next-generation JARVIS iOS architecture that behaves like a serious assistant system:
- typed requests
- explicit decisions
- clear execution plans
- guarded capabilities
- traceable outcomes
- simple runtime boundaries

## Non-Goals
- building a multi-agent platform
- cloning OpenJarvis module structure
- introducing a broad MCP ecosystem on-device
- embedding a benchmark harness into the iPhone app
- turning the assistant into a workflow engine by default

## Users
- primary: JARVIS iPhone user invoking fast local assistant flows
- secondary: internal JARVIS developers extending memory, capabilities, and response quality

## Core Architectural Requirements

### 1. Single Assistant, Typed Control Plane
The assistant must remain one product surface, but internally each turn must move through typed stages:
- request
- normalization
- elevation
- route decision
- execution plan
- capability handling or context assembly
- runtime inference if needed
- turn result

### 2. Capability-First Routing for Actionable Requests
The control plane must stop treating all requests as generic generation.

Actionable requests should route to capability handling first when appropriate.

Examples:
- navigation
- knowledge lookup
- draft preparation
- save/copy/share
- future device-integrated actions

### 3. Runtime as a Service Boundary
The runtime layer must stay responsible only for:
- load
- warmup
- readiness
- streaming
- inference

It must not become the home for orchestration, memory policy, or capability logic.

### 4. Memory as Optional Augmentation
Memory is a provider to the turn, not the center of the whole system.

The architecture must support:
- no-memory turns
- conversation-context turns
- memory-informed turns

without changing the control-plane shape.

### 5. Traceable Turns
Every assistant turn should be understandable after the fact through:
- execution history
- a compact turn trace
- lightweight diagnostics

The app should be debuggable without adopting a heavy platform telemetry stack.

### 6. Security as a Cross-Cutting Wrapper
Sensitive persistence and capability execution must be protected without modifying the runtime contract.

## Proposed Architecture

### Layer 1: UI Coordination Layer
Responsibilities:
- route entry
- focused-state handling
- view state
- rendering turn outputs

Must not own:
- classification
- planning
- capability policy
- runtime decisions

### Layer 2: Assistant Control Plane
Responsibilities:
- normalize request
- elevate request
- classify intent
- select route
- choose execution mode
- produce execution plan
- finalize turn result

Core types:
- `NormalizedRequest`
- `ElevatedRequest`
- `RouteDecision`
- `ExecutionPlan`
- `ExecutionStep`
- `TurnResult`
- `TurnTrace`

### Layer 3: Capability Layer
Responsibilities:
- declare capability metadata
- map intents to capability candidates
- execute safe capabilities
- verify outcomes

This layer should be narrow and explicit. It should not grow into a general tool marketplace.

### Layer 4: Context Layer
Responsibilities:
- recent conversation context
- lightweight knowledge retrieval
- optional memory augmentation

### Layer 5: Runtime Layer
Responsibilities:
- model readiness
- warmup
- generation
- streaming

### Layer 6: Observability Layer
Responsibilities:
- execution history
- turn traces
- diagnostics surface

### Layer 7: Security Layer
Responsibilities:
- protected local storage
- redaction
- sensitive action authorization
- audit events for sensitive actions

## Functional Requirements

### Request Handling
The system must support explicit request classes such as:
- greeting
- question answering
- coding
- drafting
- planning
- summarization
- device action
- app navigation
- knowledge lookup
- clarification

### Execution Modes
The system must support:
- direct response
- clarify
- plan only
- memory-augmented response
- capability action
- capability then respond
- visual route

### Capability Safety
For capability-oriented requests, the assistant must not hallucinate completion. It must either:
- execute a verified capability, or
- return an honest structured fallback

### Observability
Each turn must preserve enough information to answer:
- what did the user ask?
- what route did the control plane choose?
- was memory used?
- was a capability attempted?
- was the model called?
- what final result was surfaced?

## Architectural Decisions

### Adopt
- typed request lifecycle
- typed execution plans
- capability metadata and verification
- turn traces
- wrapper-style security

### Redesign
- session model for app-native continuity
- scheduling for iOS lifecycle constraints
- observability for low-footprint local use

### Defer
- dense retrieval backend proliferation
- learned routing
- generalized external tool ecosystems
- platform-scale eval harnesses

### Reject
- multi-agent product surface
- general-purpose workflow engine for normal assistant turns
- desktop/server-first systems thinking as the default

## Rollout Direction

### Phase 1
Stabilize the current control plane around:
- canonical vocabulary
- traceable turns
- capability-first routing
- runtime isolation

### Phase 2
Add richer capability execution and structured outputs.

### Phase 3
Add memory enrichment and response optimization using the same contracts.

## Pressure Test

### Risk: Overengineering
If JARVIS copies OpenJarvis breadth, it will become slower to evolve and harder to stabilize on iPhone.

Mitigation:
- keep one orchestrator
- keep one assistant product
- add only the seams that have immediate leverage

### Risk: iPhone Runtime Constraints
Complex multi-turn tool loops and large context strategies can create latency and memory pressure.

Mitigation:
- capability-first routing for action requests
- simple direct-response path for most turns
- explicit plan-only path instead of hidden long reasoning loops

### Risk: Memory Growth
If memory becomes the architecture center, every subsystem becomes coupled to retrieval and summarization behavior.

Mitigation:
- memory provider stays optional
- request/plan contracts must work with or without memory

### Risk: Observability Gaps
Without turn traces, future threads will re-debug the same routing failures repeatedly.

Mitigation:
- persist execution history
- add compact turn traces
- separate user-facing status from diagnostic trace

### Risk: Tool Safety
Capability growth without typed risk boundaries will cause user-trust failures.

Mitigation:
- capability metadata
- authorization context
- verification state
- honest structured fallback when not implemented

### Risk: Rollout Fragility
Large rewrites across runtime, memory, and UI at once will create merge conflicts and regressions.

Mitigation:
- evolve the architecture from the control plane outward
- leave runtime and memory internals behind stable protocols

## Success Criteria
This architecture direction succeeds if later threads can:
- add memory without changing the runtime contract
- add capabilities without rewriting the orchestrator
- add response optimization without changing request types
- inspect failed turns without guesswork
- delete `OpenJarvis-main` with no lost dependency

## Final Direction
JARVIS iOS should become a **local-first assistant control plane with typed execution**, not a shrunken general agent platform.
