# Plan: Thread 3 Execution-Core Rollout

> Source PRD: `docs/ios-architecture/thread1-jarvis-ios-architecture-prd.md` + `docs/jarvis-vnext-ios-agent-runtime-spec.md` + approved Thread 2 execution core

## Architectural decisions

Durable decisions that apply across all phases:

- **Execution core**: converge toward the approved value-type pipeline `AssistantRequest -> ExecutionPlan -> ExecutionTrace -> AssistantTurnResult` through adapters, not rewrites.
- **Composition root**: keep construction in `JarvisPhoneAppModel`; do not move UI ownership into the execution core.
- **Planner seam**: adapt the existing `JarvisExecutionPlanner` before changing planner behavior.
- **Runtime seam**: adapt the existing `JarvisLocalModelRuntime` and remote lane without rewriting runtime internals.
- **Capability seam**: use the current `JarvisAssistantCapabilityProviding` injection point as the first `Capability` boundary.
- **Memory seam**: use the current `JarvisAssistantMemoryProviding` injection point as the first `MemoryBoundary`.
- **Observability**: introduce minimal trace first, expand attribution later.
- **Migration style**: one lane per slice, build must remain green, no speculative field expansion.

---

## Phase 1: Minimal Execution-Core Types

**User stories**: typed request lifecycle, typed execution plans, traceable outcomes

### What to build

Introduce minimal compile-safe execution-core value types and one-way adapters around the current orchestration models. No callers migrate in this phase.

### Acceptance criteria

- [ ] Minimal `AssistantRequest`, `ExecutionPlan`, `PlannedStep`, `ExecutionTrace`, and `AssistantTurnResult` exist
- [ ] The new types stay adapter-backed and internal-facing
- [ ] No execution behavior changes
- [ ] The app still builds

---

## Phase 2: Planner Seam

**User stories**: explicit decisions, typed execution plans

### What to build

Add the `ExecutionPlanner` protocol seam and adapt the existing planner behind it. Keep decision logic unchanged.

### Acceptance criteria

- [ ] Orchestrator can depend on a planner boundary instead of the concrete planner
- [ ] Existing planner outputs are preserved
- [ ] No runtime or UI behavior changes

---

## Phase 3: Runtime Seam (Direct-Response Lane)

**User stories**: runtime as a service boundary, simple runtime boundaries

### What to build

Add the `ExecutionRuntime` seam and migrate only the direct-response lane through it. Keep `JarvisPhoneAppModel` runtime ownership stable.

### Acceptance criteria

- [ ] Direct-response lane executes through the runtime boundary
- [ ] Runtime lifecycle behavior remains unchanged
- [ ] No capability or memory lane migration yet

---

## Phase 4: Minimal Trace

**User stories**: traceable turns, lightweight diagnostics

### What to build

Create minimal trace assembly for migrated lanes and attach it to the existing turn result path without changing UI contracts.

### Acceptance criteria

- [ ] Every migrated lane produces a minimal trace
- [ ] Trace stays small and execution-scoped
- [ ] Current UI/result mapping remains stable

---

## Phase 5: Capability Boundary (One Lane)

**User stories**: capability-first routing for actionable requests

### What to build

Wrap the existing capability provider behind the approved boundary and migrate one capability-routed lane only.

### Acceptance criteria

- [ ] One capability lane runs through the capability boundary
- [ ] Existing capability behavior is preserved
- [ ] No multi-lane capability migration

---

## Phase 6: Memory Boundary (One Lane)

**User stories**: memory as optional augmentation

### What to build

Wrap the existing memory provider behind the approved boundary and migrate one memory-augmented lane only.

### Acceptance criteria

- [ ] One memory-aware lane consumes the memory boundary
- [ ] Memory storage internals remain untouched
- [ ] No global memory-flow rewrite

---

## Phase 7: Result and Attribution Expansion

**User stories**: traceable outcomes, compact turn trace

### What to build

Expand result and attribution fields only where they are now needed by migrated lanes and diagnostics.

### Acceptance criteria

- [ ] Result expansion is adapter-led
- [ ] `JarvisPhoneAppModel` UI contract remains stable
- [ ] No duplicate source-of-truth for result data

---

## Phase 8: Passive Feedback and Evals

**User stories**: observability, extensibility without rewrite

### What to build

Add passive post-turn feedback/eval hooks that observe completed turns without influencing execution control flow.

### Acceptance criteria

- [ ] Hooks run after successful or failed turn completion
- [ ] Hook failures do not affect execution
- [ ] No planner/runtime coupling to eval logic
