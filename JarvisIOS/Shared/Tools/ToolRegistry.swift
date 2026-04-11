import Foundation
#if os(macOS)
import AppKit
#endif

public final class JarvisToolRegistry: JarvisToolRegistryProviding {
    private var toolsByID: [String: JarvisTool]

    public init(tools: [JarvisTool] = JarvisToolRegistry.defaultTools) {
        self.toolsByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.capability.id, $0) })
    }

    public func tool(for id: String) -> JarvisTool? {
        toolsByID[id]
    }

    public func capabilities() -> [JarvisToolCapability] {
        toolsByID.values
            .map(\.capability)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

public extension JarvisToolRegistry {
    static let defaultTools: [JarvisTool] = [
        JarvisAppNavigationTool(),
        JarvisKnowledgeLookupTool(),
        JarvisDraftReplyTool(),
        JarvisAllowedRootsListTool(),
        JarvisAllowedRootAddTool(),
        JarvisFilePathValidateTool(),
        JarvisFileSearchTool(),
        JarvisFileReadTool(),
        JarvisFilePreviewTool(),
        JarvisFilePatchTool(),
        JarvisFileCreateTool()
    ]
}

private struct JarvisAppNavigationTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "app.navigate",
        displayName: "App Navigation",
        capability: "app.navigation",
        riskLevel: .low,
        auditCategory: "navigation"
    )

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        JarvisToolResult(
            status: .success,
            userMessage: "Navigation intent prepared for \(invocation.toolID).",
            retryable: false,
            verificationState: .unverified
        )
    }
}

private struct JarvisKnowledgeLookupTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "knowledge.lookup",
        displayName: "Knowledge Lookup",
        capability: "knowledge.lookup",
        riskLevel: .low,
        backgroundPolicy: .backgroundEligible,
        auditCategory: "knowledge"
    )

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        JarvisToolResult(
            status: .success,
            userMessage: "Knowledge lookup queued for local search.",
            retryable: false,
            verificationState: .unverified
        )
    }
}

private struct JarvisDraftReplyTool: JarvisTool {
    let capability = JarvisToolCapability(
        id: "draft.reply",
        displayName: "Draft Reply",
        capability: "draft.reply",
        riskLevel: .low,
        auditCategory: "draft"
    )

    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult {
        let target = invocation.arguments["reply_target"]?.debugValue ?? "current context"
        return JarvisToolResult(
            status: .success,
            userMessage: "Draft reply prepared for \(target).",
            retryable: false,
            verificationState: .unverified
        )
    }
}

private extension JarvisIntentValue {
    var debugValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .list(let value):
            return value.map(\.debugValue).joined(separator: ", ")
        case .object(let value):
            return value.keys.sorted().joined(separator: ", ")
        case .null:
            return "null"
        }
    }
}

struct JarvisToolBackedCapabilityRegistry: CapabilityRegistry {
    private let toolRegistry: any JarvisToolRegistryProviding

    init(toolRegistry: any JarvisToolRegistryProviding = JarvisToolRegistry()) {
        self.toolRegistry = toolRegistry
    }

    func descriptor(for id: CapabilityID) -> CapabilityDescriptor? {
        if let handler = handler(for: id) {
            return handler.descriptor
        }
        return nil
    }

    func handler(for id: CapabilityID) -> (any CapabilityHandler)? {
        switch id.rawValue {
        case "file.search":
            return JarvisToolCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .fileSearch,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .shortcutInitiated],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "filesystem.search"
                ),
                toolRegistry: toolRegistry
            )
        case "file.read":
            return JarvisToolCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .fileRead,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .shortcutInitiated],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "filesystem.read"
                ),
                toolRegistry: toolRegistry
            )
        case "file.preview":
            return JarvisToolCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .filePreview,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .shortcutInitiated],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "filesystem.preview"
                ),
                toolRegistry: toolRegistry
            )
        case "file.patch":
            return JarvisToolCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .filePatch,
                    requiresApproval: true,
                    allowedContexts: [.foregroundConversation],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "filesystem.patch"
                ),
                toolRegistry: toolRegistry
            )
        case "file.create":
            return JarvisToolCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .fileCreate,
                    requiresApproval: true,
                    allowedContexts: [.foregroundConversation],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "filesystem.create"
                ),
                toolRegistry: toolRegistry
            )
        case "knowledge.lookup":
            return JarvisToolCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .knowledgeLookup,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .backgroundTask, .shortcutInitiated],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "knowledge.lookup"
                ),
                toolRegistry: toolRegistry
            )
        case "draft.reply":
            return JarvisToolCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .draftAction,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .voiceInitiated],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "draft.reply"
                ),
                toolRegistry: toolRegistry
            )
        case "app.open":
            return JarvisAppOpenCapabilityHandler()
        case "app.focus":
            return JarvisUnsupportedCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .appFocus,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .shortcutInitiated],
                    supportsCancellation: false,
                    platformAvailability: .macOSOnly,
                    traceCategory: "app.focus"
                ),
                message: "App focus is not available in this build yet."
            )
        case "finder.reveal":
            return JarvisUnsupportedCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .finderReveal,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .shortcutInitiated],
                    supportsCancellation: false,
                    platformAvailability: .macOSOnly,
                    traceCategory: "finder.reveal"
                ),
                message: "Finder reveal is not available in this build yet."
            )
        case "system.open_url":
            return JarvisSystemOpenURLCapabilityHandler()
        case "project.open":
            return JarvisUnsupportedCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .projectOpen,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .shortcutInitiated],
                    supportsCancellation: false,
                    platformAvailability: .macOSOnly,
                    traceCategory: "project.open"
                ),
                message: "Project opening is not available in this build yet."
            )
        case "project.analyze":
            return JarvisUnsupportedCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .projectAnalyze,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "project.analyze"
                ),
                message: "Project analysis is not available in this build yet."
            )
        case "project.scaffold":
            return JarvisUnsupportedCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .projectScaffold,
                    requiresApproval: true,
                    allowedContexts: [.foregroundConversation],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "project.scaffold"
                ),
                message: "Project scaffolding is not available in this build yet."
            )
        case "shell.run.safe":
            return JarvisUnsupportedCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .shellRunSafe,
                    requiresApproval: true,
                    allowedContexts: [.foregroundConversation],
                    supportsCancellation: true,
                    platformAvailability: .macOSOnly,
                    traceCategory: "shell.run.safe"
                ),
                message: "Safe shell execution is not available in this build yet."
            )
        case "memory.search":
            return JarvisUnsupportedCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .memorySearch,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .backgroundTask],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "memory.search"
                ),
                message: "Memory search is not available in this build yet."
            )
        case "memory.store":
            return JarvisUnsupportedCapabilityHandler(
                descriptor: CapabilityDescriptor(
                    id: id,
                    kind: .memoryStore,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation, .backgroundTask],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "memory.store"
                ),
                message: "Memory store is not available in this build yet."
            )
        default:
            return nil
        }
    }
}

struct JarvisToolBackedCapabilityExecutor: CapabilityExecutor {
    private let registry: any CapabilityRegistry
    private let approvalRuntime: any CapabilityApprovalRuntime

    init(
        registry: any CapabilityRegistry = JarvisToolBackedCapabilityRegistry(),
        approvalRuntime: any CapabilityApprovalRuntime = JarvisDefaultCapabilityApprovalRuntime()
    ) {
        self.registry = registry
        self.approvalRuntime = approvalRuntime
    }

    func execute(_ invocation: CapabilityInvocation) async -> CapabilityResult {
        guard let handler = registry.handler(for: invocation.capabilityID) else {
            return CapabilityResult(
                status: .unsupported,
                userMessage: "That capability is not available in this build.",
                verification: .notApplicable,
                approvalState: .notRequired,
                state: .init(
                    capabilityID: invocation.capabilityID,
                    kind: .unsupported,
                    approvalState: .notRequired,
                    verification: .notApplicable,
                    output: .none,
                    statusMessage: "That capability is not available in this build.",
                    traceDetails: ["capability_id": invocation.capabilityID.rawValue]
                ),
                traceDetails: ["capability_id": invocation.capabilityID.rawValue]
            )
        }

        let approvalDecision = await approvalRuntime.evaluate(invocation: invocation, descriptor: handler.descriptor)
        if let terminalResult = approvalDecision.terminalResult {
            return terminalResult
        }

        do {
            let executingDetails = [
                "capability_id": invocation.capabilityID.rawValue,
                "trace_category": handler.descriptor.traceCategory,
                "approval_state": approvalDecision.approvalState.rawValue
            ]
            _ = CapabilityExecutionState(
                capabilityID: invocation.capabilityID,
                kind: .executing,
                approvalState: approvalDecision.approvalState,
                verification: .notApplicable,
                output: .none,
                statusMessage: "Executing capability.",
                traceDetails: executingDetails
            )

            let authorizedInvocation = CapabilityInvocation(
                requestID: invocation.requestID,
                conversationID: invocation.conversationID,
                capabilityID: invocation.capabilityID,
                input: invocation.input,
                typedIntent: invocation.typedIntent,
                policyDecision: invocation.policyDecision,
                approvalState: approvalDecision.approvalState
            )
            return try await handler.execute(authorizedInvocation)
        } catch {
            return CapabilityResult(
                status: .failed,
                userMessage: "Capability execution failed: \(error.localizedDescription)",
                verification: .unverified,
                approvalState: approvalDecision.approvalState,
                state: .init(
                    capabilityID: invocation.capabilityID,
                    kind: .failed,
                    approvalState: approvalDecision.approvalState,
                    verification: .unverified,
                    output: .none,
                    statusMessage: "Capability execution failed: \(error.localizedDescription)",
                    traceDetails: [
                        "capability_id": invocation.capabilityID.rawValue,
                        "trace_category": handler.descriptor.traceCategory,
                        "approval_state": approvalDecision.approvalState.rawValue
                    ]
                ),
                traceDetails: [
                    "capability_id": invocation.capabilityID.rawValue,
                    "trace_category": handler.descriptor.traceCategory,
                    "approval_state": approvalDecision.approvalState.rawValue
                ]
            )
        }
    }
}

struct JarvisDefaultCapabilityApprovalRuntime: CapabilityApprovalRuntime {
    func evaluate(
        invocation: CapabilityInvocation,
        descriptor: CapabilityDescriptor
    ) async -> CapabilityApprovalDecision {
        let baseTrace = [
            "capability_id": invocation.capabilityID.rawValue,
            "trace_category": descriptor.traceCategory
        ]

        guard descriptor.requiresApproval else {
            return .allow(approvalState: .notRequired)
        }

        switch invocation.approvalState {
        case .approved:
            return .allow(approvalState: .approved)
        case .denied:
            return .block(
                with: CapabilityResult(
                    status: .denied,
                    userMessage: "This action was denied and was not executed.",
                    verification: .notApplicable,
                    approvalState: .denied,
                    state: .init(
                        capabilityID: invocation.capabilityID,
                        kind: .denied,
                        approvalState: .denied,
                        verification: .notApplicable,
                        output: .none,
                        statusMessage: "This action was denied and was not executed.",
                        traceDetails: baseTrace.merging(["approval_transition": "denied"], uniquingKeysWith: { _, new in new })
                    ),
                    traceDetails: baseTrace.merging(["approval_transition": "denied"], uniquingKeysWith: { _, new in new })
                )
            )
        case .required, .notRequired:
            return .block(
                with: CapabilityResult(
                    status: .requiresApproval,
                    userMessage: "This action requires approval before it can run.",
                    verification: .notApplicable,
                    approvalState: .required,
                    state: .init(
                        capabilityID: invocation.capabilityID,
                        kind: .requiresApproval,
                        approvalState: .required,
                        verification: .notApplicable,
                        output: .none,
                        statusMessage: "This action requires approval before it can run.",
                        traceDetails: baseTrace.merging(["approval_transition": "pending"], uniquingKeysWith: { _, new in new })
                    ),
                    traceDetails: baseTrace.merging(["approval_transition": "pending"], uniquingKeysWith: { _, new in new })
                )
            )
        }
    }
}

private struct JarvisToolCapabilityHandler: CapabilityHandler {
    let descriptor: CapabilityDescriptor
    private let toolRegistry: any JarvisToolRegistryProviding

    init(descriptor: CapabilityDescriptor, toolRegistry: any JarvisToolRegistryProviding) {
        self.descriptor = descriptor
        self.toolRegistry = toolRegistry
    }

    func execute(_ invocation: CapabilityInvocation) async throws -> CapabilityResult {
        guard let tool = toolRegistry.tool(for: descriptor.id.rawValue) else {
            return CapabilityResult(
                status: .unsupported,
                userMessage: "That capability is not wired to a tool yet.",
                verification: .notApplicable,
                approvalState: invocation.approvalState,
                state: .init(
                    capabilityID: descriptor.id,
                    kind: .unsupported,
                    approvalState: invocation.approvalState,
                    verification: .notApplicable,
                    output: .none,
                    statusMessage: "That capability is not wired to a tool yet.",
                    traceDetails: ["capability_id": descriptor.id.rawValue]
                ),
                traceDetails: ["capability_id": descriptor.id.rawValue]
            )
        }

        let toolResult = try await tool.execute(
            JarvisToolInvocation(
                toolID: descriptor.id.rawValue,
                arguments: invocation.toolArguments,
                sourceIntent: invocation.typedIntent,
                authContext: descriptor.requiresApproval ? .biometricRequired : .unlocked
            )
        )

        return CapabilityResult(
            status: toolResult.capabilityStatus,
            userMessage: toolResult.userMessage,
            output: invocation.decodeToolOutput(from: toolResult.rawResult, for: descriptor.id),
            verification: toolResult.capabilityVerification,
            approvalState: invocation.approvalState,
            state: .init(
                capabilityID: descriptor.id,
                kind: CapabilityExecutionStateKind(toolResult.capabilityStatus),
                approvalState: invocation.approvalState,
                verification: toolResult.capabilityVerification,
                output: invocation.decodeToolOutput(from: toolResult.rawResult, for: descriptor.id),
                statusMessage: toolResult.userMessage,
                traceDetails: [
                    "capability_id": descriptor.id.rawValue,
                    "trace_category": descriptor.traceCategory,
                    "approval_state": invocation.approvalState.rawValue
                ]
            ),
            traceDetails: [
                "capability_id": descriptor.id.rawValue,
                "trace_category": descriptor.traceCategory,
                "approval_state": invocation.approvalState.rawValue
            ]
        )
    }
}

private struct JarvisUnsupportedCapabilityHandler: CapabilityHandler {
    let descriptor: CapabilityDescriptor
    let message: String

    func execute(_ invocation: CapabilityInvocation) async throws -> CapabilityResult {
        _ = invocation
        return CapabilityResult(
            status: .unsupported,
            userMessage: message,
            verification: .notApplicable,
            approvalState: .notRequired,
            state: .init(
                capabilityID: descriptor.id,
                kind: .unsupported,
                approvalState: .notRequired,
                verification: .notApplicable,
                output: .none,
                statusMessage: message,
                traceDetails: [
                    "capability_id": descriptor.id.rawValue,
                    "trace_category": descriptor.traceCategory
                ]
            ),
            traceDetails: [
                "capability_id": descriptor.id.rawValue,
                "trace_category": descriptor.traceCategory
            ]
        )
    }
}

private struct JarvisAppOpenCapabilityHandler: CapabilityHandler {
    let descriptor = CapabilityDescriptor(
        id: "app.open",
        kind: .appOpen,
        requiresApproval: false,
        allowedContexts: [.foregroundConversation, .shortcutInitiated],
        supportsCancellation: false,
        platformAvailability: .macOSOnly,
        traceCategory: "app.open"
    )

    func execute(_ invocation: CapabilityInvocation) async throws -> CapabilityResult {
#if os(macOS)
        if case .appOpen(let input) = invocation.input {
            if let appURL = input.appURL {
                let opened = NSWorkspace.shared.open(appURL)
                return CapabilityResult(
                    status: opened ? .success : .failed,
                    userMessage: opened ? "App opened." : "Unable to open app.",
                    output: .appOpen(.init(launched: opened, resolvedAppName: appURL.deletingPathExtension().lastPathComponent)),
                    verification: opened ? .verified : .unverified,
                    approvalState: .notRequired,
                    state: .init(
                        capabilityID: descriptor.id,
                        kind: opened ? .success : .failed,
                        approvalState: .notRequired,
                        verification: opened ? .verified : .unverified,
                        output: .appOpen(.init(launched: opened, resolvedAppName: appURL.deletingPathExtension().lastPathComponent)),
                        statusMessage: opened ? "App opened." : "Unable to open app.",
                        traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
                    ),
                    traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
                )
            }

            if let bundleID = input.bundleID,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let opened = NSWorkspace.shared.open(url)
                return CapabilityResult(
                    status: opened ? .success : .failed,
                    userMessage: opened ? "App opened." : "Unable to open app.",
                    output: .appOpen(.init(launched: opened, resolvedAppName: url.deletingPathExtension().lastPathComponent)),
                    verification: opened ? .verified : .unverified,
                    approvalState: .notRequired,
                    state: .init(
                        capabilityID: descriptor.id,
                        kind: opened ? .success : .failed,
                        approvalState: .notRequired,
                        verification: opened ? .verified : .unverified,
                        output: .appOpen(.init(launched: opened, resolvedAppName: url.deletingPathExtension().lastPathComponent)),
                        statusMessage: opened ? "App opened." : "Unable to open app.",
                        traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
                    ),
                    traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
                )
            }
        }
#endif
        return CapabilityResult(
            status: .unsupported,
            userMessage: "App opening is only available on macOS builds with an executable target.",
            verification: .notApplicable,
            approvalState: .notRequired,
            state: .init(
                capabilityID: descriptor.id,
                kind: .unsupported,
                approvalState: .notRequired,
                verification: .notApplicable,
                output: .none,
                statusMessage: "App opening is only available on macOS builds with an executable target.",
                traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
            ),
            traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
        )
    }
}

private struct JarvisSystemOpenURLCapabilityHandler: CapabilityHandler {
    let descriptor = CapabilityDescriptor(
        id: "system.open_url",
        kind: .systemOpenURL,
        requiresApproval: false,
        allowedContexts: [.foregroundConversation, .shortcutInitiated],
        supportsCancellation: false,
        platformAvailability: .macOSOnly,
        traceCategory: "system.open_url"
    )

    func execute(_ invocation: CapabilityInvocation) async throws -> CapabilityResult {
#if os(macOS)
        if case .systemOpenURL(let input) = invocation.input {
            let opened = NSWorkspace.shared.open(input.url)
            return CapabilityResult(
                status: opened ? .success : .failed,
                userMessage: opened ? "URL opened." : "Unable to open URL.",
                output: .systemOpenURL(.init(opened: opened)),
                verification: opened ? .verified : .unverified,
                approvalState: .notRequired,
                state: .init(
                    capabilityID: descriptor.id,
                    kind: opened ? .success : .failed,
                    approvalState: .notRequired,
                    verification: opened ? .verified : .unverified,
                    output: .systemOpenURL(.init(opened: opened)),
                    statusMessage: opened ? "URL opened." : "Unable to open URL.",
                    traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
                ),
                traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
            )
        }
#endif
        return CapabilityResult(
            status: .unsupported,
            userMessage: "Opening URLs through the system is only available on macOS builds with an executable target.",
            verification: .notApplicable,
            approvalState: .notRequired,
            state: .init(
                capabilityID: descriptor.id,
                kind: .unsupported,
                approvalState: .notRequired,
                verification: .notApplicable,
                output: .none,
                statusMessage: "Opening URLs through the system is only available on macOS builds with an executable target.",
                traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
            ),
            traceDetails: ["capability_id": descriptor.id.rawValue, "trace_category": descriptor.traceCategory]
        )
    }
}

private extension JarvisToolResult {
    var capabilityStatus: CapabilityExecutionStatus {
        switch status {
        case .success:
            return .success
        case .failed:
            return .failed
        case .partial:
            return .failed
        }
    }

    var capabilityVerification: CapabilityVerification {
        switch verificationState {
        case .verified:
            return .verified
        case .unverified, .partial:
            return .unverified
        }
    }
}

private extension CapabilityInvocation {
    var toolArguments: [String: JarvisIntentValue] {
        switch input {
        case .none:
            return [:]
        case .fileSearch(let input):
            var args: [String: JarvisIntentValue] = [
                "limit": .number(Double(input.limit))
            ]
            if let query = input.query {
                args["query"] = .string(query)
            }
            return args
        case .fileRead(let input):
            return ["path": .string(input.path.token)]
        case .filePreview(let input):
            return [
                "path": .string(input.path.token),
                "max_length": .number(2_000)
            ]
        case .filePatch(let input):
            return [
                "path": .string(input.path.token),
                "updated_content": .string(input.unifiedDiff)
            ]
        case .fileCreate(let input):
            return [
                "path": .string((input.parent.token as NSString).appendingPathComponent(input.name)),
                "content": .string(input.contents),
                "overwrite": .bool(false)
            ]
        case .appOpen(let input):
            var args: [String: JarvisIntentValue] = [:]
            if let bundleID = input.bundleID {
                args["bundle_id"] = .string(bundleID)
            }
            if let appURL = input.appURL {
                args["app_url"] = .string(appURL.absoluteString)
            }
            return args
        case .appFocus(let input):
            return ["bundle_id": .string(input.bundleID)]
        case .finderReveal(let input):
            return ["path": .string(input.path.token)]
        case .systemOpenURL(let input):
            return ["url": .string(input.url.absoluteString)]
        case .memorySearch(let input):
            return ["query": .string(input.query), "limit": .number(Double(input.limit))]
        case .memoryStore(let input):
            return ["content": .string(input.content), "labels": .list(input.labels.map(JarvisIntentValue.string))]
        case .projectScaffold, .projectOpen, .projectAnalyze, .shellRunSafe:
            return [:]
        }
    }

    func decodeToolOutput(from data: Data?, for capabilityID: CapabilityID) -> CapabilityOutputPayload {
        guard let data else { return .none }

        switch capabilityID.rawValue {
        case "file.search":
            if let response = try? JSONDecoder().decode(JarvisFileSearchResponse.self, from: data) {
                return .fileSearch(
                    .init(
                        matches: response.results.map {
                            .init(
                                path: $0.path,
                                name: $0.name,
                                fileExtension: $0.fileExtension,
                                size: $0.size,
                                lastModified: $0.lastModified
                            )
                        },
                        truncated: false
                    )
                )
            }
        case "file.read":
            if let response = try? JSONDecoder().decode(JarvisFileReadResponse.self, from: data) {
                return .fileRead(
                    .init(
                        resolvedPath: response.path,
                        contents: response.content,
                        truncated: response.truncated,
                        contentType: "text/plain"
                    )
                )
            }
        case "file.preview":
            if let response = try? JSONDecoder().decode(JarvisFilePreviewResponse.self, from: data) {
                return .filePreview(
                    .init(
                        resolvedPath: response.path,
                        previewText: response.preview,
                        kind: "text",
                        metadata: [
                            "name": response.name,
                            "extension": response.fileExtension,
                            "truncated": response.truncated ? "true" : "false",
                            "byteCount": String(response.byteCount)
                        ]
                    )
                )
            }
        case "file.patch":
            if let response = try? JSONDecoder().decode(JarvisFilePatchResponse.self, from: data) {
                return .filePatch(
                    .init(
                        resolvedPath: response.path,
                        fileName: response.fileName,
                        applied: response.applied,
                        diffSummary: response.diffPreview,
                        lineChangeCount: response.lineChangeCount,
                        requiresApproval: response.requiresApproval,
                        canApply: response.canApply,
                        rejectionReason: response.canApply ? nil : "contentMismatch"
                    )
                )
            }
        case "file.create":
            if let response = try? JSONDecoder().decode(JarvisFileCreateResponse.self, from: data) {
                return .fileCreate(
                    .init(
                        resolvedPath: response.path,
                        created: response.created,
                        fileName: response.fileName,
                        requiresApproval: response.requiresApproval,
                        canCreate: response.canCreate,
                        overwritten: response.overwritten
                    )
                )
            }
        default:
            break
        }

        return .none
    }
}
