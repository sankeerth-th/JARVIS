# Thread 1: OpenJarvis Distillation for JARVIS iOS

## Purpose
`OpenJarvis-main` was treated as a temporary reference corpus, not as project code. This document compresses its useful ideas into JARVIS-native architecture guidance so the folder can be deleted without losing architectural value.

## Method
This distillation compared:
- the current JARVIS iOS control plane in `JarvisIOS/Shared/Assistant`, `JarvisIOS/Shared/Tools`, `JarvisIOS/Shared/Security`, `JarvisIOS/Shared/Automation`, and `JarvisPhoneAppModel.swift`
- the temporary `OpenJarvis-main` architecture docs and subsystem source under:
  - `docs/architecture`
  - `src/openjarvis/agents`
  - `src/openjarvis/tools`
  - `src/openjarvis/sessions`
  - `src/openjarvis/telemetry`
  - `src/openjarvis/security`
  - `src/openjarvis/workflow`
  - `src/openjarvis/evals`
  - `src/openjarvis/skills`
  - `src/openjarvis/scheduler`

## Current JARVIS iOS Architecture Snapshot

### What JARVIS already has
- A typed orchestration seam centered on `JarvisTaskOrchestrator`
- Request normalization via `JarvisOrchestrationRequest` and `JarvisNormalizedAssistantRequest`
- Request elevation via `JarvisRequestElevator`
- Execution planning via `JarvisExecutionPlanner`
- Typed route decisions via `JarvisIntentRouter`
- A local runtime boundary via `JarvisLocalModelRuntime`
- Local conversation persistence and lightweight local knowledge search
- Tool/capability contracts in `Shared/Tools`
- iOS-specific security primitives for storage and redaction
- A thin automation engine

### What JARVIS is still missing
- A stable assistant control-plane taxonomy used consistently across all modules
- A first-class assistant turn record that cleanly separates:
  - user request
  - route decision
  - plan
  - capability execution
  - runtime generation
  - final surfaced result
- A proper observability layer for assistant turns
- A clear capability execution stage beyond placeholder fallbacks
- Strong seams for later memory enrichment without making memory the center of the design

## OpenJarvis: Transferable Ideas vs Platform Bloat

The strongest lesson from OpenJarvis is not its breadth. It is its layering discipline.

OpenJarvis repeatedly separates:
- ingress
- decision
- capability invocation
- inference
- telemetry
- tracing
- storage

That separation is worth keeping. The cross-platform general-purpose agent platform around it is not.

## Subsystem Distillation

### 1. Orchestration / Agents

#### What OpenJarvis does
- Supports multiple agent styles:
  - simple
  - orchestrator
  - ReAct
  - CodeAct / OpenHands
  - recursive long-context agents
  - sandboxed wrappers
- Uses a shared agent contract with a single `run()` entry point.
- Distinguishes direct mode from agent mode.

#### Why it exists
- To support many workloads, backends, tools, and deployment contexts.

#### What problem it solves
- Prevents all requests from being handled as one generic prompt path.
- Enables explicit multi-turn tool loops when needed.

#### Tradeoffs
- Large surface area
- More policy complexity
- More debugging and evaluation burden
- Desktop/server-first assumptions

#### JARVIS decision
- **Reuse the architectural idea**
- **Reject the agent zoo**

JARVIS iOS should keep:
- one orchestrator
- one normalized request shape
- one execution plan type
- a small set of execution modes

JARVIS should not adopt:
- multiple user-facing “agent” products
- ReAct-style visible reasoning formats
- code-executing agent frameworks on device
- recursive long-horizon agent loops as a default path

#### JARVIS-native direction
The assistant should have one control plane with a few execution paths:
- respond
- clarify
- plan
- capability action
- capability then respond
- memory-informed respond

This is already emerging in JARVIS and should become the canonical model.

### 2. Execution Engine / Runtime

#### What OpenJarvis does
- Treats runtime as a replaceable engine layer.
- Wraps engines with instrumentation and optional security.
- Supports discovery, health checks, and backend selection.

#### Why it exists
- OpenJarvis is backend-agnostic and multi-environment.

#### Tradeoffs
- Engine abstraction is powerful, but broad runtime discovery and cloud/local routing are heavier than JARVIS needs on iPhone.

#### JARVIS decision
- **Reuse the wrapper boundary**
- **Redesign the backend breadth**

JARVIS should keep:
- runtime behind a narrow protocol boundary
- orchestration above runtime
- security and observability as wrappers, not runtime mutations

JARVIS should reject:
- runtime discovery sprawl
- server/cloud-first health probing as the dominant architecture

#### JARVIS-native direction
One primary local runtime boundary on iPhone, optionally one remote lane later, but both hidden behind a single `AssistantRuntime` abstraction.

### 3. Intelligence / Reasoning Layer

#### What OpenJarvis does
- Has routing and learning systems that select engines/models/policies.
- Uses analysis context to choose a model lane.

#### Why it exists
- To optimize large heterogeneous deployments.

#### Tradeoffs
- Useful for policy separation, risky when it becomes an opaque meta-system.

#### JARVIS decision
- **Reuse typed route decisions**
- **Reject learned routing as a first move**

JARVIS should keep:
- heuristic routing
- explicit route decision objects
- route reason strings
- explicit fallback behavior

JARVIS should defer:
- learned routing
- auto-optimization pipelines
- multiple remote/local fleet strategies

### 4. Tools / Capability Abstractions

#### What OpenJarvis does
- Defines tool metadata, confirmation requirements, latency/cost hints, and execution wrappers.
- Supports native tools and MCP-adapted tools.

#### Why it exists
- To let agents act on systems instead of only answering with text.

#### Tradeoffs
- Tool ecosystems expand fast and demand strong boundaries, risk controls, and auditability.

#### JARVIS decision
- **Reuse capability metadata and execution contracts**
- **Reject open-ended tool ecosystems for iPhone MVP**

JARVIS should keep:
- explicit capability metadata
- risk levels
- auth requirements
- user-facing result contracts
- registry-based capability lookup

JARVIS should defer:
- generalized MCP ingestion on device
- arbitrary shell / file / browser / code tools

#### JARVIS-native direction
Capabilities should be narrow, high-confidence, and iPhone-native:
- app navigation
- model management
- knowledge lookup
- draft preparation
- quick capture save/copy/share
- later: camera / screenshot / notification / automation hooks with explicit permission boundaries

### 5. Sessions / Context Handling

#### What OpenJarvis does
- Uses cross-channel session identity and long-lived session stores.
- Supports session consolidation and decay.

#### Why it exists
- It runs across CLI, messaging, channels, and agents.

#### Tradeoffs
- Strong for channel interoperability.
- Too broad for a local iPhone assistant where conversation is already app-bound.

#### JARVIS decision
- **Reuse the distinction between session and message**
- **Redesign session identity as app-native**

JARVIS should keep:
- a persistent conversation/session boundary
- conversation compression/summarization seams
- explicit session metadata

JARVIS should reject:
- cross-channel identity as a core assumption
- server-style session management

#### JARVIS-native direction
Session means one ongoing local assistant thread with local context, optional memory summaries, and future cross-surface continuity inside the app.

### 6. Memory / Learning Systems

#### What OpenJarvis does
- Treats memory as pluggable searchable storage with optional dense/sparse/hybrid retrieval.
- Adds context injection and learning/routing systems.

#### Why it exists
- To support document grounding, personalization, and benchmark-driven improvement.

#### Tradeoffs
- Powerful but easy to overbuild.
- Dense retrieval and learning loops are expensive in local mobile environments.

#### JARVIS decision
- **Reuse the “memory is a provider, not the center” idea**
- **Reject retrieval backend proliferation on iPhone**

JARVIS should keep:
- memory provider interfaces
- knowledge retrieval as a distinct subsystem
- memory augmentation as optional per-turn policy

JARVIS should defer:
- multiple retrieval backends
- on-device learned routing
- autonomous long-term learning loops

### 7. Evals / Feedback Loops

#### What OpenJarvis does
- Has a real benchmark/eval framework with environments, scoring, traces, and exports.

#### Why it exists
- To compare models, agents, and strategies across many workloads.

#### Tradeoffs
- Essential for a platform project.
- Too heavy as a runtime concept inside an iPhone assistant.

#### JARVIS decision
- **Reuse the principle of offline evaluability**
- **Reject in-product eval framework complexity**

JARVIS should keep:
- stable execution records
- traceable turn outcomes
- enough structure to replay or inspect decisions later

JARVIS should defer:
- benchmark runners
- environment simulators
- pricing/energy score infrastructure as a first-class iOS subsystem

### 8. Telemetry / Tracing / Debugging

#### What OpenJarvis does
- Separates telemetry from traces.
- Telemetry records numeric metrics.
- Traces record decision steps and tool/inference events.

#### Why it exists
- To support debugging, evaluation, and optimization.

#### Tradeoffs
- Very high leverage if kept narrow.
- Dangerous if turned into massive logging on device.

#### JARVIS decision
- **Strongly reuse**

This is the most valuable transferable idea for JARVIS after orchestration.

JARVIS should define:
- **Turn Metrics**: lightweight numeric diagnostics
- **Turn Trace**: human-readable step record for a single assistant turn
- **Execution History**: persisted summaries for recent turns

JARVIS should not adopt:
- event-bus-wide generalized platform telemetry first
- energy/perf measurement systems in product code

#### JARVIS-native direction
For each assistant turn, record:
- request id
- conversation id
- route decision
- execution mode
- capability candidates
- selected capability, if any
- memory used or not
- runtime used or not
- fallback path used or not
- final status
- user-visible summary

### 9. Scheduler / Task Timing

#### What OpenJarvis does
- Has a persistent scheduler with recurring tasks, stores, and task logs.

#### Why it exists
- It supports background automation across environments.

#### Tradeoffs
- Strong concept, but desktop/server polling assumptions do not map directly to iOS lifecycle constraints.

#### JARVIS decision
- **Reuse automation workflow concepts**
- **Redesign scheduling to App Intents / system scheduling realities**

JARVIS should keep:
- automation workflow object
- explicit trigger and step model
- execution result records

JARVIS should reject:
- background polling daemon assumptions
- cron-first architecture on iPhone

### 10. Security

#### What OpenJarvis does
- Wraps engines with guardrails rather than modifying engine internals.
- Protects tools and file ingest separately.
- Audits security events.

#### Why it exists
- To keep safety cross-cutting and composable.

#### Tradeoffs
- Correct pattern. Some of the server/file-system policies are too broad for iPhone.

#### JARVIS decision
- **Strongly reuse**

JARVIS should keep:
- wrapper/decorator model
- tool-specific capability checks
- sensitive content redaction
- storage protection
- audit trail for sensitive actions

JARVIS should reject:
- generalized desktop file policy assumptions
- broad shell/tool security as a default design center

## Distilled Architecture Direction for JARVIS iOS

### Core Principle
JARVIS iOS should become a **typed assistant control plane over a local-first runtime**, not a mini clone of a general multi-agent platform.

### Recommended top-level layers
1. **Surface Layer**
   - SwiftUI views
   - app state coordination
   - route entry points

2. **Assistant Control Plane**
   - request normalization
   - request elevation
   - route decision
   - execution planning
   - capability routing
   - assistant turn result packaging

3. **Capability Layer**
   - explicit capability registry
   - guarded action execution
   - verification and user-facing results

4. **Context Layer**
   - conversation context
   - lightweight knowledge retrieval
   - optional memory augmentation provider

5. **Runtime Layer**
   - local GGUF runtime
   - warmup/readiness/inference

6. **Observability Layer**
   - execution history
   - turn traces
   - debug diagnostics

7. **Security Layer**
   - storage protection
   - redaction
   - capability authorization

## What JARVIS Should Reuse, Redesign, Defer, Reject

### Reuse
- explicit orchestration boundary
- typed execution modes
- capability metadata and risk declarations
- trace vs telemetry separation
- wrapper-style security
- execution history

### Redesign for iPhone
- sessions
- scheduling
- capability set
- route/model lane selection
- observability footprint

### Defer
- broad memory backends
- eval harnesses
- multi-agent families
- MCP ecosystems
- learned routing

### Reject
- general-purpose desktop/server platform breadth
- broad tool ecosystems on-device
- cron/poller scheduler assumptions
- recursive/reasoning-heavy agent families as the default assistant path

## Architecture Direction After `OpenJarvis-main` Is Deleted

The lasting direction should be:
- one assistant product
- one orchestrator
- one normalized request model
- one execution plan type
- one capability system
- one turn trace format
- one lightweight observability story

The reference folder is useful because it proves the value of separation. It is not the blueprint for the final JARVIS codebase.

## Anti-Copy Rules

- Do not copy OpenJarvis module names into JARVIS unless the concept already exists naturally in JARVIS.
- Do not import the OpenJarvis idea of many exposed agent types into the iPhone product surface.
- Do not reproduce OpenJarvis file/module granularity just because it is available in the reference corpus.
- Do not make JARVIS dependent on MCP, workflow DAGs, eval runners, or scheduler daemons as part of the core iOS assistant path.
- Do not adopt desktop/server-centric assumptions like global event buses, cron polling, or cross-channel identity as default architecture.

## Migration Constraints

- Migration must be adapter-led, not rewrite-led.
- The existing JARVIS runtime boundary must remain stable while control-plane seams deepen.
- Memory must enter through provider interfaces, not by coupling retrieval/storage into request or result types.
- Capability execution must be introduced behind typed contracts so unavailable actions can degrade honestly.
- Observability should start with turn traces and execution history, not a generalized telemetry platform.
