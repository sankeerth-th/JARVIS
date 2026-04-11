import Foundation

@MainActor
struct MemoryBoundaryRequest {
    let request: JarvisOrchestrationRequest
    let normalizedRequest: JarvisNormalizedAssistantRequest
    let classification: JarvisTaskClassification
    let resolvedSkill: JarvisResolvedSkill
}

@MainActor
protocol MemoryBoundary {
    func prepare(request: MemoryBoundaryRequest) async -> MemorySnapshot

    func record(request: MemoryBoundaryRequest, result: AssistantTurnResult) async
}

@MainActor
struct JarvisExecutionMemoryBoundaryAdapter: MemoryBoundary {
    private let memoryManager: ConversationMemoryManager
    private let memoryProvider: JarvisAssistantMemoryProviding

    init(
        memoryManager: ConversationMemoryManager,
        memoryProvider: JarvisAssistantMemoryProviding
    ) {
        self.memoryManager = memoryManager
        self.memoryProvider = memoryProvider
    }

    func prepare(request: MemoryBoundaryRequest) async -> MemorySnapshot {
        let context = memoryManager.prepareContext(
            conversation: request.request.conversation,
            prompt: request.request.prompt,
            classification: request.classification,
            skill: request.resolvedSkill,
            taskBudget: request.classification.task.historyLimit
        )
        let augmentation = await memoryProvider.augmentation(
            for: request.normalizedRequest,
            classification: request.classification
        )

        return MemorySnapshot(context: context, augmentation: augmentation)
    }

    func record(request: MemoryBoundaryRequest, result: AssistantTurnResult) async {
        memoryManager.recordInteraction(
            conversationID: request.request.conversation.id,
            userMessage: JarvisChatMessage(role: .user, text: request.request.prompt),
            assistantMessage: JarvisChatMessage(role: .assistant, text: result.responseText),
            task: request.request.task,
            classification: request.classification
        )
    }
}
