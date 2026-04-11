import Foundation

public struct JarvisToolCapability: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let capability: String
    public let riskLevel: JarvisRiskLevel
    public let requiresBiometricAuth: Bool
    public let backgroundPolicy: JarvisBackgroundPolicy
    public let lockScreenEligible: Bool
    public let auditCategory: String

    public init(
        id: String,
        displayName: String,
        capability: String,
        riskLevel: JarvisRiskLevel,
        requiresBiometricAuth: Bool = false,
        backgroundPolicy: JarvisBackgroundPolicy = .foregroundOnly,
        lockScreenEligible: Bool = false,
        auditCategory: String
    ) {
        self.id = id
        self.displayName = displayName
        self.capability = capability
        self.riskLevel = riskLevel
        self.requiresBiometricAuth = requiresBiometricAuth
        self.backgroundPolicy = backgroundPolicy
        self.lockScreenEligible = lockScreenEligible
        self.auditCategory = auditCategory
    }
}

public struct JarvisToolInvocation: Codable, Equatable, Sendable {
    public var toolID: String
    public var arguments: [String: JarvisIntentValue]
    public var sourceIntent: JarvisTypedIntent
    public var authContext: JarvisAuthorizationContext

    public init(
        toolID: String,
        arguments: [String: JarvisIntentValue] = [:],
        sourceIntent: JarvisTypedIntent,
        authContext: JarvisAuthorizationContext = .unlocked
    ) {
        self.toolID = toolID
        self.arguments = arguments
        self.sourceIntent = sourceIntent
        self.authContext = authContext
    }
}

public struct JarvisToolResult: Codable, Equatable, Sendable {
    public var status: JarvisExecutionStatus
    public var userMessage: String
    public var rawResult: Data?
    public var retryable: Bool
    public var verificationState: JarvisVerificationState

    public init(
        status: JarvisExecutionStatus,
        userMessage: String,
        rawResult: Data? = nil,
        retryable: Bool = false,
        verificationState: JarvisVerificationState = .unverified
    ) {
        self.status = status
        self.userMessage = userMessage
        self.rawResult = rawResult
        self.retryable = retryable
        self.verificationState = verificationState
    }
}

public protocol JarvisTool {
    var capability: JarvisToolCapability { get }
    func execute(_ invocation: JarvisToolInvocation) async throws -> JarvisToolResult
}

public protocol JarvisToolRegistryProviding {
    func tool(for id: String) -> JarvisTool?
    func capabilities() -> [JarvisToolCapability]
}

protocol CapabilityHandler {
    var descriptor: CapabilityDescriptor { get }
    func execute(_ invocation: CapabilityInvocation) async throws -> CapabilityResult
}

protocol CapabilityRegistry {
    func descriptor(for id: CapabilityID) -> CapabilityDescriptor?
    func handler(for id: CapabilityID) -> (any CapabilityHandler)?
}

protocol CapabilityExecutor {
    func execute(_ invocation: CapabilityInvocation) async -> CapabilityResult
}

struct JarvisCapabilityResolver {
    private let registry: any CapabilityRegistry

    init(registry: any CapabilityRegistry = JarvisToolBackedCapabilityRegistry()) {
        self.registry = registry
    }

    func resolve(candidate: JarvisAssistantCapabilityCandidate) -> Capability? {
        switch candidate.kind {
        case .searchKnowledge:
            return resolve(id: "knowledge.lookup")
        default:
            return nil
        }
    }

    func resolve(plan: JarvisAssistantExecutionPlan) -> Capability? {
        guard plan.mode == .capabilityAction || plan.mode == .capabilityThenRespond else { return nil }

        if let selectedCapabilityID = plan.selectedCapabilityID {
            return resolve(id: selectedCapabilityID)
        }

        if plan.elevatedRequest.capabilityHint == .searchKnowledge {
            return resolve(id: "knowledge.lookup")
        }

        return nil
    }

    private func resolve(id: CapabilityID) -> Capability? {
        guard let descriptor = registry.descriptor(for: id) else {
            return nil
        }

        return Capability(
            id: descriptor.id.rawValue,
            kind: descriptor.kind,
            risk: descriptor.requiresApproval ? .medium : .low,
            requiresConfirmation: descriptor.requiresApproval,
            platformAvailability: descriptor.platformAvailability
        )
    }
}
