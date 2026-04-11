import Foundation

public protocol JarvisAutomationRunning {
    func run(_ workflow: JarvisAutomationWorkflow) async -> JarvisAutomationRunResult
}

public protocol JarvisTriggerEvaluating {
    func shouldFire(_ trigger: JarvisAutomationTrigger, now: Date) async -> Bool
}

public final class JarvisTriggerEvaluator: JarvisTriggerEvaluating {
    public init() {}

    public func shouldFire(_ trigger: JarvisAutomationTrigger, now: Date) async -> Bool {
        switch trigger.kind {
        case .manual, .appShortcut:
            return true
        case .schedule:
            return trigger.scheduleExpression?.isEmpty == false
        case .homeEvent:
            return trigger.sourceIdentifier?.isEmpty == false
        }
    }
}

public final class JarvisAutomationEngine: JarvisAutomationRunning {
    private let toolRegistry: JarvisToolRegistryProviding
    private let triggerEvaluator: JarvisTriggerEvaluating

    public init(
        toolRegistry: JarvisToolRegistryProviding = JarvisToolRegistry(),
        triggerEvaluator: JarvisTriggerEvaluating = JarvisTriggerEvaluator()
    ) {
        self.toolRegistry = toolRegistry
        self.triggerEvaluator = triggerEvaluator
    }

    public func run(_ workflow: JarvisAutomationWorkflow) async -> JarvisAutomationRunResult {
        let startedAt = Date()
        let shouldFire = await triggerEvaluator.shouldFire(workflow.trigger, now: startedAt)
        guard shouldFire, workflow.isEnabled else {
            return JarvisAutomationRunResult(
                workflowID: workflow.id,
                status: .failed,
                startedAt: startedAt,
                finishedAt: Date(),
                stepResults: []
            )
        }

        var stepResults: [JarvisAutomationStepResult] = []
        var overallStatus: JarvisExecutionStatus = .success

        for step in workflow.steps {
            guard let tool = toolRegistry.tool(for: step.toolID) else {
                stepResults.append(
                    JarvisAutomationStepResult(
                        stepID: step.id,
                        toolID: step.toolID,
                        status: .failed,
                        message: "Tool not registered."
                    )
                )
                overallStatus = workflow.failurePolicy.shouldContinue ? .partial : .failed
                if !workflow.failurePolicy.shouldContinue { break }
                continue
            }

            do {
                let result = try await tool.execute(
                    JarvisToolInvocation(
                        toolID: step.toolID,
                        arguments: step.arguments,
                        sourceIntent: JarvisTypedIntent(
                            mode: .workflow,
                            intent: "automation.run",
                            confidence: 1.0,
                            requiresConfirmation: false,
                            reasoningSummary: workflow.name
                        )
                    )
                )
                stepResults.append(
                    JarvisAutomationStepResult(
                        stepID: step.id,
                        toolID: step.toolID,
                        status: result.status,
                        message: result.userMessage
                    )
                )
                if result.status != .success {
                    overallStatus = workflow.failurePolicy.shouldContinue ? .partial : .failed
                    if !workflow.failurePolicy.shouldContinue { break }
                }
            } catch {
                stepResults.append(
                    JarvisAutomationStepResult(
                        stepID: step.id,
                        toolID: step.toolID,
                        status: .failed,
                        message: error.localizedDescription
                    )
                )
                overallStatus = workflow.failurePolicy.shouldContinue ? .partial : .failed
                if !workflow.failurePolicy.shouldContinue { break }
            }
        }

        return JarvisAutomationRunResult(
            workflowID: workflow.id,
            status: overallStatus,
            startedAt: startedAt,
            finishedAt: Date(),
            stepResults: stepResults,
            retryCount: 0
        )
    }
}
