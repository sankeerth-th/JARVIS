# Thread 1: JARVIS Ubiquitous Language

This glossary defines the canonical terms that later threads should use. The goal is to remove ambiguity before deeper implementation.

## Core Product Terms

### Assistant
The single JARVIS product personality presented to the user. Not a family of exposed agents.

### Turn
One assistant interaction cycle from user input to final surfaced result.

### Conversation
A persisted sequence of turns grouped as one user-visible thread.

### Session
The live working context for a conversation during app use. A session can hold transient state that should not automatically be treated as long-term memory.

## Control-Plane Terms

### Request
The raw incoming user input plus invocation metadata.

### Normalized Request
The canonical typed form of a request after source, route context, task, preferences, and conversation context are attached.

### Elevated Request
A normalized request after heuristic interpretation has strengthened weak phrasing into a more actionable internal framing.

### Intent
What the user is trying to accomplish, expressed as a typed semantic label.

### Route Decision
The control-plane decision that selects the processing lane for a request. This may include:
- typed intent
- selected model lane
- confirmation requirement
- fallback behavior

### Execution Mode
The high-level turn strategy. Canonical modes:
- `directResponse`
- `clarify`
- `planOnly`
- `memoryAugmentedResponse`
- `capabilityAction`
- `capabilityThenRespond`
- `visualRoute`

### Execution Plan
The ordered plan for a single turn. It explains what stages the system will run and why.

### Execution Step
One stage within an execution plan, such as normalize, classify, inspect capabilities, build context, infer, or finalize.

### Response Contract
The compact control-plane rule set for how a response should be shaped for a request type.

### Delivery Mode
How the result should be surfaced:
- streaming text
- structured card
- status only

## Capability Terms

### Capability
A user-meaningful action the assistant can route to, such as:
- app navigation
- knowledge lookup
- draft preparation
- save/copy/share

### Capability Candidate
A potential action the planner identifies before deciding whether to execute or fallback.

### Tool
The executable implementation behind a capability contract. In JARVIS, tools should remain narrow and app-native.

### Capability Action
A turn mode where the control plane routes the request to an action instead of generic generation.

### Capability Then Respond
A turn mode where the assistant executes or stages an action, then produces a user-facing response.

### Verification State
Whether an action result is verified, unverified, or failed. The assistant must not hallucinate completion.

## Context and Memory Terms

### Conversation Context
Recent messages and other local context used to keep a turn coherent.

### Knowledge
Locally saved, user-owned content that can be searched and used for grounded answers.

### Memory Augmentation
Optional insertion of relevant prior context into a turn. This is a policy choice, not a guarantee for every turn.

### Memory Provider
The subsystem that can supply memory/context to a turn without becoming the center of orchestration.

### Long-Term Memory
Persisted facts or summaries intended to survive beyond a single conversation session.

## Runtime Terms

### Runtime
The model execution layer responsible for load, warmup, streaming, and inference.

### Model Lane
The selected runtime lane for a turn, such as local-fast or remote-reasoning. This is a route-level choice, not a UI concept.

### Warmup
The phase where the runtime transitions to a usable state before inference.

### Readiness
The runtime’s current ability to accept inference work.

## Observability Terms

### Execution History
A persisted summary log of recent assistant turns and their outcomes.

### Turn Trace
A structured record of how a single turn was processed:
- request
- decision
- plan
- capability handling
- context use
- runtime use
- final result

### Telemetry
Lightweight numeric signals about runtime or turn performance.

### Diagnostics
Developer- or power-user-facing explanations about the current assistant state and decisions.

## Security Terms

### Authorization Context
The current trust state for an action, such as unlocked, confirmed, or restricted.

### Sensitive Action
Any capability requiring stronger confirmation, elevated trust, or explicit user acknowledgement.

### Redaction
Removal or masking of sensitive content before persistence or display.

### Audit Record
A persisted record that a sensitive action or security-relevant event occurred.

## Terms to Avoid

These terms are too broad or misleading for JARVIS iOS and should not become architectural centerpieces:
- “agent” as the primary user-facing product unit
- “tool-calling framework” as a design goal
- “workflow engine” for normal chat turns
- “memory” when the actual concept is only recent conversation context
- “session” when the actual concept is a persisted conversation

## Naming Guidance for Future Threads

Prefer:
- `AssistantRequest`
- `NormalizedRequest`
- `ElevatedRequest`
- `RouteDecision`
- `ExecutionPlan`
- `ExecutionStep`
- `CapabilityCandidate`
- `CapabilityResult`
- `TurnResult`
- `TurnTrace`
- `ExecutionHistory`

Avoid introducing synonyms for the same thing. One concept should have one name.
