import Foundation

public enum JarvisRiskLevel: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
    case critical
}

public enum JarvisAuthorizationContext: String, Codable, Equatable, Sendable {
    case unlocked
    case biometricRequired
    case backgroundOnly
}

public enum JarvisBackgroundPolicy: String, Codable, Equatable, Sendable {
    case foregroundOnly
    case backgroundEligible
}

public enum JarvisVerificationState: String, Codable, Equatable, Sendable {
    case unverified
    case verified
    case partial
}

public enum JarvisExecutionStatus: String, Codable, Equatable, Sendable {
    case success
    case failed
    case partial
}

public struct JarvisPolicyDecision: Equatable, Sendable {
    public var isAllowed: Bool
    public var riskLevel: JarvisRiskLevel
    public var requiresBiometricAuth: Bool
    public var reason: String

    public init(
        isAllowed: Bool,
        riskLevel: JarvisRiskLevel,
        requiresBiometricAuth: Bool = false,
        reason: String
    ) {
        self.isAllowed = isAllowed
        self.riskLevel = riskLevel
        self.requiresBiometricAuth = requiresBiometricAuth
        self.reason = reason
    }
}

@MainActor
public final class JarvisPolicyEngine {
    public init() {}

    public func evaluate(_ decision: JarvisRouteDecision) -> JarvisPolicyDecision {
        if decision.typedIntent.mode == .action {
            if decision.typedIntent.intent.contains("home.") || decision.typedIntent.intent.contains("device") {
                return JarvisPolicyDecision(
                    isAllowed: true,
                    riskLevel: .medium,
                    requiresBiometricAuth: decision.requiresConfirmation,
                    reason: "Native action path requires confirmation before execution."
                )
            }

            return JarvisPolicyDecision(
                isAllowed: true,
                riskLevel: .low,
                requiresBiometricAuth: false,
                reason: "Action is in an app-scoped execution domain."
            )
        }

        if decision.typedIntent.mode == .workflow {
            return JarvisPolicyDecision(
                isAllowed: true,
                riskLevel: .medium,
                requiresBiometricAuth: false,
                reason: "Workflow creation is allowed but should be validated before persistence."
            )
        }

        return JarvisPolicyDecision(
            isAllowed: true,
            riskLevel: .low,
            reason: "Response-only path."
        )
    }
}
