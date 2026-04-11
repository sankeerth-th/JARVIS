# Ubiquitous Language

## Assistant execution core

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Assistant Request** | The raw user ask plus invocation metadata at the moment it enters the control plane. | Query, input, payload |
| **Normalized Request** | The canonical typed request after source, route, conversation, preferences, and context references are attached. | Parsed request, prepared input |
| **Elevated Request** | A normalized request whose weak or ambiguous wording has been strengthened into an actionable internal framing. | Expanded prompt, rewritten prompt |
| **Typed Intent** | The semantic label describing what the user is trying to accomplish. | Intent guess, classifier output |
| **Route Decision** | The control-plane choice of lane, fallback behavior, and confirmation needs for one request. | Router result, policy route |
| **Execution Mode** | The high-level strategy for a turn such as direct response, clarify, plan only, or capability action. | Path, flow, branch |
| **Execution Plan** | The ordered set of planned stages for one assistant turn. | Plan, pipeline, workflow |
| **Planned Step** | One named stage in an execution plan, such as normalize, inspect capabilities, build context, or infer. | Action step, stage item |
| **Execution Lane** | The runtime lane selected for a turn, such as local-fast or remote-reasoning. | Model tier, backend path |
| **Policy Decision** | A rule-based decision that constrains execution, fallback, confirmation, or capability handling. | Guardrail choice, routing rule |
| **Assistant Turn Result** | The single public outcome of a turn, including surfaced content, diagnostics, and status. | Response object, completion |
| **Execution Trace** | A structured record of how a single turn was processed end to end. | Debug log, internal trace |

## Capabilities and adapters

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Capability** | A user-meaningful action the assistant can route to and verify. | Tool, command, action target |
| **Capability Candidate** | A possible capability the planner identifies before execution is chosen. | Potential tool, option |
| **Capability Result** | The typed outcome of a capability attempt, including verification state and user-safe wording. | Tool output, action response |
| **Verification** | The truth status of an action result: verified, unverified, or failed. | Confidence, assumption |
| **Adapter** | A boundary object that lets the execution core talk to a subsystem without taking ownership of its internals. | Bridge, shim, wrapper |
| **Lane Migration** | A controlled shift of execution from one lane or adapter to another without changing request or result semantics. | Backend switch, reroute |

## Context and memory

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Conversation** | A persisted user-visible thread of assistant turns. | Chat, history blob |
| **Session** | The live working context for a conversation while the app is active. | Thread, conversation |
| **Conversation Context** | Recent messages and local state used to keep a turn coherent. | Memory, history |
| **Knowledge** | User-owned local material that can be searched and used for grounded answers. | Memory store, retrieval corpus |
| **Memory Boundary** | The rule that memory augmentation is optional and external to the core execution contract. | Memory system, persistent context |
| **Memory Snapshot** | The specific memory/context payload made available to one turn. | Retrieved memory, recall packet |

## Runtime and safety

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Execution Runtime** | The subsystem that loads the model, warms it, streams tokens, and performs inference. | Engine, backend |
| **Warmup** | The transition phase that prepares the runtime to accept a turn. | Preload, boot |
| **Readiness** | The current ability of the runtime to accept inference work. | Health, availability |
| **Authorization Context** | The trust state under which a capability may execute. | Security mode, auth flag |
| **Sensitive Action** | A capability that requires stronger confirmation or protection before execution. | Dangerous tool, risky step |
| **Audit Record** | A persisted record of a security-relevant or user-sensitive event. | Log line, event row |

## Relationships

- An **Assistant Request** becomes exactly one **Normalized Request**.
- A **Normalized Request** may produce one **Elevated Request**.
- A **Route Decision** selects one **Execution Lane** and one **Execution Mode**.
- An **Execution Plan** contains one or more **Planned Steps**.
- A **Capability Candidate** may become one executed **Capability**.
- A **Capability** returns one **Capability Result** with a **Verification** state.
- A **Conversation** contains many assistant turns.
- One assistant turn yields exactly one **Assistant Turn Result** and may emit one **Execution Trace**.
- A **Memory Snapshot** may inform a turn, but the **Memory Boundary** keeps it outside the core request/result contract.

## Example dialogue

> **Dev:** "When a user says 'open knowledge,' is that an **Assistant Request** or a **Capability**?"

> **Domain expert:** "It starts as an **Assistant Request**, but the **Route Decision** should identify it as a capability-oriented ask and choose `capabilityAction`."

> **Dev:** "So the **Execution Plan** should not go straight to the **Execution Runtime**?"

> **Domain expert:** "Correct. A navigation **Capability** should run first, and the **Capability Result** must carry a clear **Verification** state."

> **Dev:** "If memory helps answer a follow-up, where does that live?"

> **Domain expert:** "Inside a **Memory Snapshot** for that turn. The **Memory Boundary** means the core types still work even if no memory is attached."

## Flagged ambiguities

- "memory" is overloaded in the current discussion. Use **Conversation Context** for recent in-thread material, **Knowledge** for local searchable user-owned content, and **Memory Snapshot** only for the specific augmentation payload attached to a turn.
- "tool" and "capability" are not the same. Use **Capability** for user-meaningful action semantics and **Adapter** or implementation-specific tool only behind that boundary.
- "session" and "conversation" are distinct. A **Conversation** is persisted and user-visible; a **Session** is the live working context while the app is active.
- "engine," "runtime," and "lane" should not be used interchangeably. Use **Execution Runtime** for the inference subsystem and **Execution Lane** for the selected path through it.
