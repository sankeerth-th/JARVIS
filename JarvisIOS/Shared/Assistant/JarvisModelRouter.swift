import Foundation

@MainActor
public final class JarvisModelRouter {
    public init() {}

    public func lane(
        for decision: JarvisRouteDecision,
        request: JarvisNormalizedAssistantRequest
    ) -> JarvisModelLane {
        switch decision.typedIntent.mode {
        case .workflow:
            return .remoteReasoning
        case .clarify:
            return .localFast
        case .action:
            return .localFast
        case .respond:
            break
        }

        if request.prompt.count > 400 {
            return .remoteReasoning
        }

        if request.executionPreferences.prefersStructuredOutput == true &&
            (decision.selectedSkillID == "planning" || decision.selectedSkillID == "knowledge_lookup") {
            return .remoteReasoning
        }

        return decision.lane
    }
}
