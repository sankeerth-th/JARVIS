# Thread 3 Execution-Core Issues

## Issue 1: Introduce Minimal Execution-Core Vocabulary

- **Purpose**: establish the approved execution-core names as internal, compile-safe value types
- **Scope**: add minimal execution-core types and one-way adapters from existing orchestration models
- **Files/modules**: `JarvisIOS/Shared/Assistant/JarvisAssistantOrchestrationModels.swift`, focused iOS tests
- **Dependencies**: none
- **Risks**: duplicate-model-layer drift if fields expand too early
- **Rollback**: remove the new internal types and adapter properties only

## Issue 2: Add Planner Boundary Adapter

- **Purpose**: introduce the approved `ExecutionPlanner` seam without changing planner logic
- **Scope**: protocol + adapter over the current `JarvisExecutionPlanner`
- **Files/modules**: planner seam file, `JarvisExecutionPlanner.swift`, `JarvisTaskOrchestrator.swift`, tests
- **Dependencies**: Issue 1
- **Risks**: shallow wrapper if the seam exposes the concrete planner shape verbatim
- **Rollback**: switch orchestrator construction back to the concrete planner

## Issue 3: Add Runtime Boundary For Direct-Response Lane

- **Purpose**: route one direct-response lane through the approved runtime seam
- **Scope**: protocol + adapter over local/remote runtime entry points for a single lane
- **Files/modules**: runtime seam file, `JarvisTaskOrchestrator.swift`, `JarvisLocalModelRuntime.swift`, `JarvisOllamaRemoteEngine.swift`, tests
- **Dependencies**: Issues 1-2
- **Risks**: wrapper explosion and duplicated runtime state if a second publisher layer is introduced
- **Rollback**: restore the direct-response lane to current runtime calls

## Issue 4: Attach Minimal Execution Trace

- **Purpose**: make migrated lanes observable before widening migration
- **Scope**: minimal trace assembly and mapping into the existing turn-result path
- **Files/modules**: orchestration models, `JarvisTaskOrchestrator.swift`, tests
- **Dependencies**: Issue 3
- **Risks**: trace/result duplication if trace becomes a second result model
- **Rollback**: stop attaching trace while keeping types dormant

## Issue 5: Migrate One Capability Lane Through Capability Boundary

- **Purpose**: establish the approved capability seam through one real path
- **Scope**: wrap current capability provider and migrate one actionable lane
- **Files/modules**: `JarvisAssistantOrchestrationModels.swift`, `JarvisExecutionPlanner.swift`, `JarvisSkill.swift`, `ToolRegistry.swift`, `JarvisTaskOrchestrator.swift`, tests
- **Dependencies**: Issues 1-4
- **Risks**: changing planner behavior for all capability paths at once
- **Rollback**: route only the migrated lane back to the current capability provider

## Issue 6: Migrate One Memory-Augmented Lane Through MemoryBoundary

- **Purpose**: establish the approved memory seam without changing memory internals
- **Scope**: wrap current memory provider and migrate one memory-aware lane
- **Files/modules**: `JarvisAssistantOrchestrationModels.swift`, `JarvisSemanticMemoryProvider.swift`, `JarvisTaskOrchestrator.swift`, tests
- **Dependencies**: Issues 1-5
- **Risks**: accidentally coupling to `ConversationMemoryManager` or rewriting storage behavior
- **Rollback**: route the migrated lane back to direct provider usage

## Issue 7: Expand Turn Result and Attribution Where Consumed

- **Purpose**: expose trace/attribution through the existing result path only when needed
- **Scope**: add result fields and adapters, avoid UI contract churn
- **Files/modules**: orchestration models, `JarvisTaskOrchestrator.swift`, `JarvisPhoneAppModel.swift`, tests
- **Dependencies**: Issues 1-6
- **Risks**: breaking UI bindings or creating two result sources of truth
- **Rollback**: remove newly added mappings and keep the older result contract

## Issue 8: Add Passive Feedback/Eval Hooks

- **Purpose**: add observation hooks after execution is stable
- **Scope**: post-turn observer seam only
- **Files/modules**: new observer protocol file, `JarvisTaskOrchestrator.swift`, tests
- **Dependencies**: Issues 1-7
- **Risks**: coupling evals into control flow
- **Rollback**: unregister observers and remove the hook call site
