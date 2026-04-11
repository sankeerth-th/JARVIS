# Plan: JARVIS iOS Execution Core Rollout

> Source PRD: Thread 1 architecture direction + Thread 2 approved execution-core design

## Architectural decisions

Durable decisions that apply across all phases:

- **Execution spine**: value-type pipeline with protocol boundaries.
- **Core contracts**: `AssistantRequest`, `MemorySnapshot`, `ExecutionPlan`, `PlannedStep`, `Capability`, `ExecutionPlanner`, `ExecutionRuntime`, `ExecutionTrace`, `AssistantTurnResult`, `MemoryBoundary`.
- **Migration strategy**: adapter-led only; existing `Jarvis...` orchestration models remain compatibility types until the new spine serves current flows.
- **Execution ownership**: planning, execution, memory preparation/recording, capability invocation, and trace production must move out of the overloaded orchestrator over time.
- **Tool boundary**: planned capabilities must resolve to executable tool references; heuristic capability labels are insufficient.
- **Memory boundary**: memory preparation and memory recording must be unified behind one execution-facing seam.
- **App-facing consumers**: update last; `JarvisPhoneAppModel` must not become execution-core owner.

---

## Phase 1: Minimal Core Types And Adapters

**User stories**: establish the typed execution seam without breaking the current app flow.

### What to build

Introduce the approved minimal execution-core types as top-level values and add adapters to and from the current orchestration models. Keep behavior in place for now; only create the migration seam.

### Acceptance criteria

- [ ] New core types compile without requiring broad call-site changes.
- [ ] Existing orchestration code can convert into and out of the new core types.
- [ ] No runtime, UI, or memory behavior changes are required yet.

---

## Phase 2: Planner Seam

**User stories**: planning decisions are produced through a stable core planner contract instead of staying implicit in the orchestrator.

### What to build

Introduce `ExecutionPlanner` and adapt the current planner path so it produces the new `ExecutionPlan` through compatibility bridges while preserving existing execution behavior.

### Acceptance criteria

- [ ] `ExecutionPlan` becomes the planner-facing artifact for one lane without changing user-visible output.
- [ ] Route, policy, and model-lane decisions are visible on the plan.
- [ ] Existing planner behavior is preserved by characterization coverage.

---

## Phase 3: Runtime Seam For One Direct-Response Lane

**User stories**: one direct-response execution path runs through a stable runtime contract.

### What to build

Introduce `ExecutionRuntime` and wrap the current orchestrator execution path for the direct-response lane only. Keep other modes on the legacy path.

### Acceptance criteria

- [ ] One direct-response lane executes through `ExecutionRuntime`.
- [ ] The app remains build-stable and behaviorally unchanged for non-migrated lanes.
- [ ] Runtime ownership is separated from planning for the migrated lane.

---

## Phase 4: Minimal Execution Trace

**User stories**: migrated turns produce a stable debugging contract with real step outcomes.

### What to build

Add `ExecutionTrace` and `StepTrace` for the migrated lane. Record actual step statuses without expanding into analytics or UI redesign.

### Acceptance criteria

- [ ] Migrated lane emits `ExecutionTrace`.
- [ ] Trace records lane used, step outcomes, and final status.
- [ ] Existing diagnostics continue to work through adapters.

---

## Phase 5: Capability Boundary For One Capability-Routed Lane

**User stories**: a single capability-routed lane plans against a resolved capability and binds to executable tools.

### What to build

Introduce the `Capability` execution contract and migrate one capability-routed lane so planning binds to a resolved executable capability instead of heuristic labels alone.

### Acceptance criteria

- [ ] One capability-routed lane plans with `Capability` and executes against the tool registry.
- [ ] Planner/runtime split is real for that lane.
- [ ] Non-migrated capability paths remain untouched.

---

## Phase 6: Memory Boundary For One Memory-Aware Lane

**User stories**: one memory-aware lane uses a stable execution-facing memory seam for preparation and recording.

### What to build

Introduce `MemoryBoundary` and migrate one memory-aware response lane to use `prepare(for:)` and `record(request:result:)` instead of direct memory-manager/provider coupling.

### Acceptance criteria

- [ ] One lane gets memory via `MemoryBoundary.prepare`.
- [ ] Post-turn recording uses `MemoryBoundary.record`.
- [ ] The legacy memory internals remain behind adapters.

---

## Phase 7: Result And Attribution Expansion Where Consumed

**User stories**: the migrated core can return the single public turn result and bridge to current app-facing consumers.

### What to build

Stabilize `AssistantTurnResult` for migrated lanes and expand attribution only where currently consumed. Keep app-facing consumers on adapters until the seam is stable.

### Acceptance criteria

- [ ] `AssistantTurnResult` is the public outcome for migrated lanes.
- [ ] Existing app-facing consumers continue to work through compatibility adapters.
- [ ] No broad UI churn is required.

---

## Phase 8: Passive Feedback And Eval Hooks

**User stories**: migrated lanes expose lightweight debugging and evaluation hooks without changing execution ownership.

### What to build

Add passive hooks for trace inspection, execution history, and evaluation capture around the migrated seams only.

### Acceptance criteria

- [ ] Feedback hooks are additive and passive.
- [ ] No new runtime or planner ownership shifts are introduced.
- [ ] Debug visibility improves without broadening the execution contracts.
