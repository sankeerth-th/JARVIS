import Foundation

public enum JarvisAutomationTriggerKind: String, Codable, Equatable, Sendable {
    case schedule
    case appShortcut
    case homeEvent
    case manual
}

public struct JarvisAutomationTrigger: Codable, Equatable, Sendable {
    public var kind: JarvisAutomationTriggerKind
    public var scheduleExpression: String?
    public var sourceIdentifier: String?

    public init(
        kind: JarvisAutomationTriggerKind,
        scheduleExpression: String? = nil,
        sourceIdentifier: String? = nil
    ) {
        self.kind = kind
        self.scheduleExpression = scheduleExpression
        self.sourceIdentifier = sourceIdentifier
    }
}

public struct JarvisAutomationCondition: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var type: String
    public var expectedValue: String

    public init(id: UUID = UUID(), type: String, expectedValue: String) {
        self.id = id
        self.type = type
        self.expectedValue = expectedValue
    }
}

public struct JarvisAutomationStep: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var toolID: String
    public var arguments: [String: JarvisIntentValue]

    public init(id: UUID = UUID(), toolID: String, arguments: [String: JarvisIntentValue] = [:]) {
        self.id = id
        self.toolID = toolID
        self.arguments = arguments
    }
}

public struct JarvisAutomationFailurePolicy: Codable, Equatable, Sendable {
    public var shouldNotify: Bool
    public var shouldContinue: Bool
    public var maxRetryCount: Int

    public init(shouldNotify: Bool = true, shouldContinue: Bool = false, maxRetryCount: Int = 0) {
        self.shouldNotify = shouldNotify
        self.shouldContinue = shouldContinue
        self.maxRetryCount = max(0, maxRetryCount)
    }
}

public struct JarvisAutomationNotificationPolicy: Codable, Equatable, Sendable {
    public var notifyOnSuccess: Bool
    public var notifyOnFailure: Bool

    public init(notifyOnSuccess: Bool = false, notifyOnFailure: Bool = true) {
        self.notifyOnSuccess = notifyOnSuccess
        self.notifyOnFailure = notifyOnFailure
    }
}

public struct JarvisAutomationWorkflow: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: JarvisAutomationTrigger
    public var conditions: [JarvisAutomationCondition]
    public var steps: [JarvisAutomationStep]
    public var failurePolicy: JarvisAutomationFailurePolicy
    public var notificationPolicy: JarvisAutomationNotificationPolicy
    public var isEnabled: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        trigger: JarvisAutomationTrigger,
        conditions: [JarvisAutomationCondition] = [],
        steps: [JarvisAutomationStep],
        failurePolicy: JarvisAutomationFailurePolicy = .init(),
        notificationPolicy: JarvisAutomationNotificationPolicy = .init(),
        isEnabled: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.conditions = conditions
        self.steps = steps
        self.failurePolicy = failurePolicy
        self.notificationPolicy = notificationPolicy
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
    }
}

public struct JarvisAutomationStepResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var stepID: UUID
    public var toolID: String
    public var status: JarvisExecutionStatus
    public var message: String

    public init(
        id: UUID = UUID(),
        stepID: UUID,
        toolID: String,
        status: JarvisExecutionStatus,
        message: String
    ) {
        self.id = id
        self.stepID = stepID
        self.toolID = toolID
        self.status = status
        self.message = message
    }
}

public struct JarvisAutomationRunResult: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var status: JarvisExecutionStatus
    public var startedAt: Date
    public var finishedAt: Date
    public var stepResults: [JarvisAutomationStepResult]
    public var retryCount: Int

    public init(
        workflowID: UUID,
        status: JarvisExecutionStatus,
        startedAt: Date,
        finishedAt: Date,
        stepResults: [JarvisAutomationStepResult],
        retryCount: Int = 0
    ) {
        self.workflowID = workflowID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.stepResults = stepResults
        self.retryCount = retryCount
    }
}
