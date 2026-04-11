import Foundation

public struct CapabilityID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

enum AllowedCapabilityContext: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case foregroundConversation
    case backgroundTask
    case voiceInitiated
    case shortcutInitiated
    case automation
}

public enum CapabilityPlatformAvailability: String, Codable, Equatable, Sendable {
    case shared
    case macOSOnly
    case iOSOnly
    case unsupported
}

enum ApprovalState: String, Codable, Equatable, Sendable {
    case notRequired
    case required
    case approved
    case denied
}

enum CapabilityExecutionStatus: String, Codable, Equatable, Sendable {
    case pending
    case executing
    case success
    case failed
    case unsupported
    case cancelled
    case requiresApproval
    case denied
}

enum CapabilityVerification: String, Codable, Equatable, Sendable {
    case verified
    case unverified
    case notApplicable
}

struct ScopedPath: Codable, Equatable, Sendable {
    enum ScopeKind: String, Codable, Equatable, Sendable {
        case allowedDirectory
        case bookmark
        case temporary
        case project
        case unknown
    }

    let token: String
    let displayPath: String
    let scopeKind: ScopeKind

    init(token: String, displayPath: String? = nil, scopeKind: ScopeKind = .unknown) {
        self.token = token
        self.displayPath = displayPath ?? token
        self.scopeKind = scopeKind
    }
}

struct FileMatch: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let path: String
    let name: String
    let fileExtension: String
    let size: Int64
    let lastModified: Date

    init(
        path: String,
        name: String,
        fileExtension: String = "",
        size: Int64 = 0,
        lastModified: Date = .distantPast
    ) {
        self.id = path
        self.path = path
        self.name = name
        self.fileExtension = fileExtension
        self.size = size
        self.lastModified = lastModified
    }
}

enum ProjectTemplate: String, Codable, Equatable, Sendable {
    case swiftPackage
    case xcodeApp
    case cliTool
    case unknown
}

enum ProjectAnalysisMode: String, Codable, Equatable, Sendable {
    case lightweight
    case structureOnly
    case summary
}

enum SafeShellCommand: String, Codable, Equatable, Sendable {
    case ls
    case pwd
    case rg
    case gitStatus = "git.status"
}

struct MemoryMatch: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let summary: String
    let labels: [String]

    init(id: UUID = UUID(), summary: String, labels: [String] = []) {
        self.id = id
        self.summary = summary
        self.labels = labels
    }
}

struct FileSearchCapabilityInput: Codable, Equatable, Sendable {
    let roots: [ScopedPath]
    let query: String?
    let glob: String?
    let extensions: [String]
    let contentSearch: Bool
    let limit: Int
}

struct FileSearchCapabilityOutput: Codable, Equatable, Sendable {
    let matches: [FileMatch]
    let truncated: Bool
}

struct FileReadCapabilityInput: Codable, Equatable, Sendable {
    let path: ScopedPath
    let lineRange: ClosedRange<Int>?
    let maxBytes: Int?
}

struct FileReadCapabilityOutput: Codable, Equatable, Sendable {
    let resolvedPath: String
    let contents: String
    let truncated: Bool
    let contentType: String
}

struct FilePreviewCapabilityInput: Codable, Equatable, Sendable {
    let path: ScopedPath
}

struct FilePreviewCapabilityOutput: Codable, Equatable, Sendable {
    let resolvedPath: String
    let previewText: String
    let kind: String
    let metadata: [String: String]
}

struct FilePatchCapabilityInput: Codable, Equatable, Sendable {
    let path: ScopedPath
    let unifiedDiff: String
}

struct FilePatchCapabilityOutput: Codable, Equatable, Sendable {
    let resolvedPath: String
    let fileName: String
    let applied: Bool
    let diffSummary: String
    let lineChangeCount: Int
    let requiresApproval: Bool
    let canApply: Bool
    let rejectionReason: String?
}

struct FileCreateCapabilityInput: Codable, Equatable, Sendable {
    let parent: ScopedPath
    let name: String
    let contents: String
}

struct FileCreateCapabilityOutput: Codable, Equatable, Sendable {
    let resolvedPath: String
    let created: Bool
    let fileName: String
    let requiresApproval: Bool
    let canCreate: Bool
    let overwritten: Bool
}

struct ProjectScaffoldCapabilityInput: Codable, Equatable, Sendable {
    let destination: ScopedPath
    let template: ProjectTemplate
    let name: String
}

struct ProjectScaffoldCapabilityOutput: Codable, Equatable, Sendable {
    let rootPath: String
    let createdFilesCount: Int
    let summary: String
}

struct ProjectOpenCapabilityInput: Codable, Equatable, Sendable {
    let path: ScopedPath
}

struct ProjectOpenCapabilityOutput: Codable, Equatable, Sendable {
    let opened: Bool
    let target: String
}

struct ProjectAnalyzeCapabilityInput: Codable, Equatable, Sendable {
    let root: ScopedPath
    let mode: ProjectAnalysisMode
}

struct ProjectAnalyzeCapabilityOutput: Codable, Equatable, Sendable {
    let summary: String
    let detectedStack: [String]
    let interestingPaths: [String]
}

struct AppOpenCapabilityInput: Codable, Equatable, Sendable {
    let bundleID: String?
    let appURL: URL?
}

struct AppOpenCapabilityOutput: Codable, Equatable, Sendable {
    let launched: Bool
    let resolvedAppName: String?
}

struct AppFocusCapabilityInput: Codable, Equatable, Sendable {
    let bundleID: String
}

struct AppFocusCapabilityOutput: Codable, Equatable, Sendable {
    let focused: Bool
}

struct FinderRevealCapabilityInput: Codable, Equatable, Sendable {
    let path: ScopedPath
}

struct FinderRevealCapabilityOutput: Codable, Equatable, Sendable {
    let revealed: Bool
}

struct SystemOpenURLCapabilityInput: Codable, Equatable, Sendable {
    let url: URL
}

struct SystemOpenURLCapabilityOutput: Codable, Equatable, Sendable {
    let opened: Bool
}

struct ShellRunSafeCapabilityInput: Codable, Equatable, Sendable {
    let command: SafeShellCommand
    let cwd: ScopedPath?
}

struct ShellRunSafeCapabilityOutput: Codable, Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let truncated: Bool
}

struct MemorySearchCapabilityInput: Codable, Equatable, Sendable {
    let query: String
    let limit: Int
}

struct MemorySearchCapabilityOutput: Codable, Equatable, Sendable {
    let matches: [MemoryMatch]
}

struct MemoryStoreCapabilityInput: Codable, Equatable, Sendable {
    let content: String
    let labels: [String]
}

struct MemoryStoreCapabilityOutput: Codable, Equatable, Sendable {
    let stored: Bool
    let summary: String
}

enum CapabilityInputPayload: Codable, Equatable, Sendable {
    case none
    case fileSearch(FileSearchCapabilityInput)
    case fileRead(FileReadCapabilityInput)
    case filePreview(FilePreviewCapabilityInput)
    case filePatch(FilePatchCapabilityInput)
    case fileCreate(FileCreateCapabilityInput)
    case projectScaffold(ProjectScaffoldCapabilityInput)
    case projectOpen(ProjectOpenCapabilityInput)
    case projectAnalyze(ProjectAnalyzeCapabilityInput)
    case appOpen(AppOpenCapabilityInput)
    case appFocus(AppFocusCapabilityInput)
    case finderReveal(FinderRevealCapabilityInput)
    case systemOpenURL(SystemOpenURLCapabilityInput)
    case shellRunSafe(ShellRunSafeCapabilityInput)
    case memorySearch(MemorySearchCapabilityInput)
    case memoryStore(MemoryStoreCapabilityInput)
}

enum CapabilityOutputPayload: Codable, Equatable, Sendable {
    case none
    case fileSearch(FileSearchCapabilityOutput)
    case fileRead(FileReadCapabilityOutput)
    case filePreview(FilePreviewCapabilityOutput)
    case filePatch(FilePatchCapabilityOutput)
    case fileCreate(FileCreateCapabilityOutput)
    case projectScaffold(ProjectScaffoldCapabilityOutput)
    case projectOpen(ProjectOpenCapabilityOutput)
    case projectAnalyze(ProjectAnalyzeCapabilityOutput)
    case appOpen(AppOpenCapabilityOutput)
    case appFocus(AppFocusCapabilityOutput)
    case finderReveal(FinderRevealCapabilityOutput)
    case systemOpenURL(SystemOpenURLCapabilityOutput)
    case shellRunSafe(ShellRunSafeCapabilityOutput)
    case memorySearch(MemorySearchCapabilityOutput)
    case memoryStore(MemoryStoreCapabilityOutput)
}

struct CapabilityDescriptor: Equatable, Sendable {
    let id: CapabilityID
    let kind: CapabilityKind
    let requiresApproval: Bool
    let allowedContexts: Set<AllowedCapabilityContext>
    let supportsCancellation: Bool
    let platformAvailability: CapabilityPlatformAvailability
    let traceCategory: String
}

struct CapabilityInvocation: Equatable, Sendable {
    let requestID: UUID
    let conversationID: UUID
    let capabilityID: CapabilityID
    let input: CapabilityInputPayload
    let typedIntent: JarvisTypedIntent
    let policyDecision: JarvisPolicyDecision?
    let approvalState: ApprovalState
}

enum CapabilityExecutionStateKind: String, Codable, Equatable, Sendable {
    case pending
    case executing
    case success
    case failed
    case requiresApproval
    case denied
    case unsupported
    case cancelled
}

struct CapabilityExecutionState: Equatable, Sendable {
    let capabilityID: CapabilityID
    let kind: CapabilityExecutionStateKind
    let approvalState: ApprovalState
    let verification: CapabilityVerification
    let output: CapabilityOutputPayload
    let statusMessage: String
    let traceDetails: [String: String]
}

struct CapabilityApprovalDecision: Equatable, Sendable {
    let shouldExecute: Bool
    let approvalState: ApprovalState
    let terminalResult: CapabilityResult?

    static func allow(approvalState: ApprovalState) -> CapabilityApprovalDecision {
        CapabilityApprovalDecision(shouldExecute: true, approvalState: approvalState, terminalResult: nil)
    }

    static func block(with result: CapabilityResult) -> CapabilityApprovalDecision {
        CapabilityApprovalDecision(shouldExecute: false, approvalState: result.approvalState, terminalResult: result)
    }
}

protocol CapabilityApprovalRuntime {
    func evaluate(
        invocation: CapabilityInvocation,
        descriptor: CapabilityDescriptor
    ) async -> CapabilityApprovalDecision
}

struct CapabilityResult: Equatable, Sendable {
    let status: CapabilityExecutionStatus
    let userMessage: String
    let output: CapabilityOutputPayload
    let verification: CapabilityVerification
    let approvalState: ApprovalState
    let state: CapabilityExecutionState
    let traceDetails: [String: String]

    init(
        status: CapabilityExecutionStatus,
        userMessage: String,
        output: CapabilityOutputPayload = .none,
        verification: CapabilityVerification = .notApplicable,
        approvalState: ApprovalState = .notRequired,
        state: CapabilityExecutionState? = nil,
        traceDetails: [String: String] = [:]
    ) {
        self.status = status
        self.userMessage = userMessage
        self.output = output
        self.verification = verification
        self.approvalState = approvalState
        self.state = state ?? CapabilityExecutionState(
            capabilityID: "",
            kind: CapabilityExecutionStateKind(status),
            approvalState: approvalState,
            verification: verification,
            output: output,
            statusMessage: userMessage,
            traceDetails: traceDetails
        )
        self.traceDetails = traceDetails
    }
}

struct AssistantRequest: Equatable, Identifiable {
    let id: UUID
    let conversationID: UUID
    let text: String
    let task: JarvisAssistantTask
    let source: JarvisAssistantInvocationSourceKind
}

struct MemorySnapshot: Equatable {
    let context: MemoryContext
    let augmentation: JarvisAssistantMemoryAugmentation

    init(
        context: MemoryContext = MemoryContext(),
        augmentation: JarvisAssistantMemoryAugmentation = .none
    ) {
        self.context = context
        self.augmentation = augmentation
    }

    var summary: String? {
        augmentation.summary ?? context.summary?.summaryText
    }

    var contextLines: [String] {
        if !augmentation.supplementalContext.isEmpty {
            return augmentation.supplementalContext.flatMap { block in
                block.content.split(separator: "\n").map(String.init)
            }
        }

        return context.retrievedMemories.map { match in
            "- \(match.record.kind.promptTitle): \(match.record.content)"
        }
    }
}

struct ExecutionPlan: Equatable, Identifiable {
    let id: UUID
    let requestID: UUID
    let intent: JarvisTypedIntent
    let lane: JarvisModelLane
    let steps: [PlannedStep]
}

struct PlannedStep: Equatable, Identifiable {
    let id: UUID
    let kind: PlannedStepKind
    let capability: Capability?
}

enum PlannedStepKind: String, Equatable {
    case decision
    case generation
    case capability
    case verification
}

struct Capability: Equatable, Identifiable {
    let id: String
    let kind: CapabilityKind
    let risk: JarvisRiskLevel
    let requiresConfirmation: Bool
    let platformAvailability: CapabilityPlatformAvailability
}

enum CapabilityKind: String, Equatable {
    case fileSearch
    case fileRead
    case filePreview
    case filePatch
    case fileCreate
    case projectScaffold
    case projectOpen
    case projectAnalyze
    case appOpen
    case appFocus
    case finderReveal
    case systemOpenURL
    case shellRunSafe
    case memorySearch
    case memoryStore
    case appRoute
    case knowledgeLookup
    case draftAction
    case automationAction
    case homeAction
}

struct ExecutionTrace: Equatable {
    let requestID: UUID
    let planID: UUID
    let lane: JarvisModelLane
    let steps: [StepTrace]
    let status: JarvisExecutionStatus
}

struct StepTrace: Equatable, Identifiable {
    let id: UUID
    let stepID: UUID
    let capabilityID: String?
    let status: JarvisExecutionStatus
}

struct AssistantTurnResult: Equatable {
    let requestID: UUID
    let plan: ExecutionPlan
    let trace: ExecutionTrace
    let responseText: String
    let suggestions: [JarvisAssistantSuggestionDescriptor]
    let messageAttribution: JarvisMessageMemoryAttribution
    let capabilityState: CapabilityExecutionState?

    func finalizedResponseText(
        fallbackStreamingText: String = "",
        runtimeStreamingText: String = ""
    ) -> String {
        [responseText, fallbackStreamingText, runtimeStreamingText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}

extension AssistantRequest {
    init(_ request: JarvisOrchestrationRequest) {
        self.init(
            id: request.id,
            conversationID: request.conversation.id,
            text: request.prompt,
            task: request.task,
            source: request.sourceKind
        )
    }

    init(_ request: JarvisNormalizedAssistantRequest) {
        self.init(
            id: request.id,
            conversationID: request.conversationID,
            text: request.prompt,
            task: request.requestedTask,
            source: request.sourceKind
        )
    }
}

extension PlannedStep {
    init(_ step: JarvisAssistantExecutionStep, capability: Capability? = nil) {
        self.init(
            id: step.id,
            kind: PlannedStepKind(step.kind),
            capability: capability
        )
    }
}

extension ExecutionPlan {
    init(_ plan: JarvisAssistantExecutionPlan) {
        let resolvedCapability = JarvisCapabilityResolver().resolve(plan: plan)
        self.init(
            id: plan.id,
            requestID: plan.request.id,
            intent: ExecutionPlan.resolveTypedIntent(from: plan),
            lane: plan.selectedModelLane ?? plan.routeDecision?.lane ?? .localFast,
            steps: plan.steps.map { step in
                let capability = step.kind == .inspectCapabilities ? resolvedCapability : nil
                return PlannedStep(step, capability: capability)
            }
        )
    }

    private static func resolveTypedIntent(from plan: JarvisAssistantExecutionPlan) -> JarvisTypedIntent {
        if let typedIntent = plan.routeDecision?.typedIntent {
            return typedIntent
        }

        return JarvisTypedIntent(
            mode: plan.mode.intentMode,
            intent: plan.elevatedRequest.elevatedIntent,
            confidence: plan.classification.confidence,
            requiresConfirmation: plan.policyDecision?.requiresBiometricAuth ?? false,
            reasoningSummary: plan.diagnostics.reasoning.joined(separator: " ")
        )
    }
}

extension ExecutionTrace {
    init(
        plan: JarvisAssistantExecutionPlan,
        finalStatus: JarvisExecutionStatus,
        stepStatuses: [UUID: JarvisExecutionStatus]
    ) {
        self.init(
            requestID: plan.request.id,
            planID: plan.id,
            lane: plan.selectedModelLane ?? plan.routeDecision?.lane ?? .localFast,
            steps: plan.steps.map { step in
                StepTrace(
                    id: step.id,
                    stepID: step.id,
                    capabilityID: nil,
                    status: stepStatuses[step.id] ?? .partial
                )
            },
            status: finalStatus
        )
    }

    init(_ result: JarvisAssistantTurnResult) {
        if let executionTrace = result.executionTrace {
            self = executionTrace
            return
        }

        self.init(
            requestID: result.request.id,
            planID: result.plan.id,
            lane: result.plan.selectedModelLane ?? result.plan.routeDecision?.lane ?? .localFast,
            steps: [],
            status: result.error == nil ? .success : .failed
        )
    }
}

extension AssistantTurnResult {
    init(_ result: JarvisAssistantTurnResult) {
        let plan = ExecutionPlan(result.plan)
        self.init(
            requestID: result.request.id,
            plan: plan,
            trace: result.executionTrace ?? ExecutionTrace(result),
            responseText: result.responseText,
            suggestions: result.suggestions,
            messageAttribution: result.messageAttribution,
            capabilityState: result.capabilityState
        )
    }
}

extension JarvisOrchestrationRequest {
    var coreAssistantRequest: AssistantRequest {
        AssistantRequest(self)
    }
}

extension JarvisNormalizedAssistantRequest {
    var coreAssistantRequest: AssistantRequest {
        AssistantRequest(self)
    }
}

extension JarvisAssistantExecutionPlan {
    var coreExecutionPlan: ExecutionPlan {
        ExecutionPlan(self)
    }
}

extension JarvisAssistantTurnResult {
    var coreExecutionTrace: ExecutionTrace {
        ExecutionTrace(self)
    }

    var coreAssistantTurnResult: AssistantTurnResult {
        AssistantTurnResult(self)
    }
}

extension JarvisOrchestrationResult {
    var coreAssistantTurnResult: AssistantTurnResult {
        turnResult.coreAssistantTurnResult
    }
}

private extension PlannedStepKind {
    init(_ kind: JarvisAssistantExecutionStepKind) {
        switch kind {
        case .inspectCapabilities:
            self = .capability
        case .infer:
            self = .generation
        case .finalizeTurn:
            self = .verification
        case .normalizeRequest, .classifyIntent, .chooseMode, .consultMemory, .buildContext, .preparePrompt, .warmRuntime:
            self = .decision
        }
    }
}

private extension JarvisAssistantExecutionMode {
    var intentMode: JarvisIntentMode {
        switch self {
        case .capabilityAction, .capabilityThenRespond:
            return .action
        case .clarify:
            return .clarify
        case .planOnly:
            return .workflow
        case .directResponse, .memoryAugmentedResponse, .visualRoute:
            return .respond
        }
    }
}

extension CapabilityExecutionStateKind {
    init(_ status: CapabilityExecutionStatus) {
        switch status {
        case .pending:
            self = .pending
        case .executing:
            self = .executing
        case .success:
            self = .success
        case .failed:
            self = .failed
        case .unsupported:
            self = .unsupported
        case .cancelled:
            self = .cancelled
        case .requiresApproval:
            self = .requiresApproval
        case .denied:
            self = .denied
        }
    }
}
