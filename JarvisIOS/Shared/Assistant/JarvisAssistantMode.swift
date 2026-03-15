import Foundation
import Combine

// MARK: - Assistant Mode

public enum JarvisAssistantMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case general
    case explain
    case summarize
    case write
    case plan
    case code
    case reply
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .general:
            return "General"
        case .explain:
            return "Explain"
        case .summarize:
            return "Summarize"
        case .write:
            return "Write"
        case .plan:
            return "Plan"
        case .code:
            return "Code"
        case .reply:
            return "Reply"
        }
    }
    
    public var icon: String {
        switch self {
        case .general:
            return "bubble.left.and.text.bubble.right"
        case .explain:
            return "text.book.closed"
        case .summarize:
            return "text.quote"
        case .write:
            return "square.and.pencil"
        case .plan:
            return "list.bullet.clipboard"
        case .code:
            return "curlybraces"
        case .reply:
            return "arrowshape.turn.up.left"
        }
    }
    
    public var description: String {
        switch self {
        case .general:
            return "Balanced assistance for any task"
        case .explain:
            return "Clear, thorough explanations with examples"
        case .summarize:
            return "Concise summaries of longer content"
        case .write:
            return "Help writing and drafting content"
        case .plan:
            return "Structured planning and organization"
        case .code:
            return "Coding help with precise technical answers"
        case .reply:
            return "Draft context-aware replies"
        }
    }
    
    public var reasoningHint: String {
        switch self {
        case .general:
            return "Handle this as a high-quality assistant conversation. Answer directly, avoid fluff, and give a practical next step when it would help."
        case .explain:
            return "Explain clearly and thoroughly. Lead with the core concept, then add supporting detail and examples. Make it easy to understand."
        case .summarize:
            return "Compress the content faithfully. Surface the highest-signal points first. Be concise but complete."
        case .write:
            return "Help the user write effectively. Match their requested tone and style. Make the output ready to use."
        case .plan:
            return "Organize the work into concrete, actionable steps. Prioritize effectively and identify dependencies."
        case .code:
            return "Reason step-by-step about the code. Be precise with terminology. Provide working, tested solutions."
        case .reply:
            return "Draft a natural, context-aware reply. Match the conversation tone. Make it ready to send with minimal editing."
        }
    }
    
    public var responseHint: String {
        switch self {
        case .general:
            return "Lead with the answer and add only the most useful supporting detail."
        case .explain:
            return "Start with the core idea, then explain the mechanism. Use examples when they help."
        case .summarize:
            return "Prefer an overview plus compact bullets. Keep it faithful and don't pad."
        case .write:
            return "Write naturally and match the requested tone. Return ready-to-use content."
        case .plan:
            return "Structure as actionable steps with clear priorities. Make it easy to execute."
        case .code:
            return "Be specific, use precise terminology, and prefer directly actionable code."
        case .reply:
            return "Write naturally, preserve important details, and sound like the user."
        }
    }
    
    public var defaultPreset: JarvisGenerationPreset {
        switch self {
        case .general:
            return .balanced
        case .explain:
            return .precise
        case .summarize:
            return .precise
        case .write:
            return .drafting
        case .plan:
            return .balanced
        case .code:
            return .coding
        case .reply:
            return .drafting
        }
    }
    
    public var defaultTemperature: Double {
        switch self {
        case .general:
            return 0.55
        case .explain:
            return 0.45
        case .summarize:
            return 0.35
        case .write:
            return 0.60
        case .plan:
            return 0.50
        case .code:
            return 0.25
        case .reply:
            return 0.55
        }
    }
    
    public var defaultResponseStyle: JarvisAssistantResponseStyle {
        switch self {
        case .general:
            return .balanced
        case .explain:
            return .detailed
        case .summarize:
            return .concise
        case .write:
            return .balanced
        case .plan:
            return .balanced
        case .code:
            return .balanced
        case .reply:
            return .balanced
        }
    }
    
    public var systemPromptSuffix: String {
        switch self {
        case .general:
            return ""
        case .explain:
            return "Use clear language. Define technical terms. Provide concrete examples."
        case .summarize:
            return "Be ruthlessly concise. Every word should earn its place."
        case .write:
            return "Match the user's voice and intent. Edit for clarity and flow."
        case .plan:
            return "Think through dependencies and edge cases. Prioritize ruthlessly."
        case .code:
            return "Test your reasoning. Consider edge cases. Optimize for readability."
        case .reply:
            return "Read the room. Match the tone. Be helpful and natural."
        }
    }
    
    /// Returns the best mode for a given task
    public static func mode(for task: JarvisAssistantTask) -> JarvisAssistantMode {
        switch task {
        case .chat:
            return .general
        case .summarize:
            return .summarize
        case .reply:
            return .reply
        case .draftEmail:
            return .write
        case .analyzeText:
            return .explain
        case .visualDescribe:
            return .explain
        case .prioritizeNotifications:
            return .plan
        case .quickCapture:
            return .general
        case .knowledgeAnswer:
            return .explain
        }
    }
    
    /// Returns the best mode for a given task category
    public static func mode(for category: JarvisTaskCategory) -> JarvisAssistantMode {
        switch category {
        case .generalChat:
            return .general
        case .questionAnswering:
            return .explain
        case .summarization:
            return .summarize
        case .draftingMessage, .draftingEmail:
            return .write
        case .rewritingText:
            return .write
        case .explainingSomething:
            return .explain
        case .planning:
            return .plan
        case .coding:
            return .code
        case .contextAwareReply:
            return .reply
        }
    }
}

// MARK: - Mode Configuration

public struct ModeConfiguration: Equatable, Codable {
    public let mode: JarvisAssistantMode
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var repeatPenalty: Double
    public var maxTokens: Int?
    public var responseStyle: JarvisAssistantResponseStyle
    public var enableStreaming: Bool
    public var streamingBufferSize: Int
    
    public init(
        mode: JarvisAssistantMode,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        repeatPenalty: Double? = nil,
        maxTokens: Int? = nil,
        responseStyle: JarvisAssistantResponseStyle? = nil,
        enableStreaming: Bool = true,
        streamingBufferSize: Int = 8
    ) {
        self.mode = mode
        self.temperature = temperature ?? mode.defaultTemperature
        self.topP = topP ?? 0.90
        self.topK = topK ?? 40
        self.repeatPenalty = repeatPenalty ?? 1.08
        self.maxTokens = maxTokens
        self.responseStyle = responseStyle ?? mode.defaultResponseStyle
        self.enableStreaming = enableStreaming
        self.streamingBufferSize = streamingBufferSize
    }
    
    public static func `default`(for mode: JarvisAssistantMode) -> ModeConfiguration {
        ModeConfiguration(mode: mode)
    }
}

// MARK: - Mode Prompt Template

public struct ModePromptTemplate: Equatable {
    public let mode: JarvisAssistantMode
    public let systemInstruction: String
    public let assistantRole: String
    public let taskInstruction: String
    public let responseInstruction: String
    public let contextBlocks: [JarvisPromptContextBlock]
    
    public init(
        mode: JarvisAssistantMode,
        systemInstruction: String? = nil,
        assistantRole: String? = nil,
        taskInstruction: String? = nil,
        responseInstruction: String? = nil,
        contextBlocks: [JarvisPromptContextBlock] = []
    ) {
        self.mode = mode
        self.systemInstruction = systemInstruction ?? ModePromptTemplate.defaultSystemInstruction(for: mode)
        self.assistantRole = assistantRole ?? ModePromptTemplate.defaultAssistantRole(for: mode)
        self.taskInstruction = taskInstruction ?? mode.reasoningHint
        self.responseInstruction = responseInstruction ?? mode.responseHint
        self.contextBlocks = contextBlocks
    }
    
    private static func defaultSystemInstruction(for mode: JarvisAssistantMode) -> String {
        let base = "You are Jarvis, a sharp, reliable, on-device iPhone assistant."
        let suffix = mode.systemPromptSuffix
        return suffix.isEmpty ? base : "\(base) \(suffix)"
    }
    
    private static func defaultAssistantRole(for mode: JarvisAssistantMode) -> String {
        switch mode {
        case .general:
            return "You are Jarvis, a proactive iPhone assistant. Reason cleanly, act on the user's intent, and optimize for usefulness on a phone-sized screen."
        case .explain:
            return "You are Jarvis, an expert teacher. Break down complex topics into understandable pieces. Use examples and analogies when helpful."
        case .summarize:
            return "You are Jarvis, a master of brevity. Distill information to its essence without losing meaning."
        case .write:
            return "You are Jarvis, a skilled writing assistant. Help craft clear, compelling content that matches the user's voice and purpose."
        case .plan:
            return "You are Jarvis, a strategic planner. Organize work into clear, actionable steps with proper prioritization."
        case .code:
            return "You are Jarvis, a senior software engineer. Provide precise, tested solutions with clean, readable code."
        case .reply:
            return "You are Jarvis, a communication expert. Draft natural, context-aware replies that sound like the user."
        }
    }
    
    public func toBlueprint() -> JarvisPromptBlueprint {
        JarvisPromptBlueprint(
            systemInstruction: systemInstruction,
            assistantRole: assistantRole,
            taskTypeInstruction: taskInstruction,
            responseInstruction: responseInstruction,
            contextBlocks: contextBlocks,
            userInputPrefix: "User request:"
        )
    }
}

// MARK: - Mode Manager

@MainActor
public final class JarvisModeManager: ObservableObject {
    @Published public private(set) var currentMode: JarvisAssistantMode = .general
    @Published public private(set) var configurations: [JarvisAssistantMode: ModeConfiguration] = [:]
    
    public init() {
        // Initialize default configurations for all modes
        for mode in JarvisAssistantMode.allCases {
            configurations[mode] = ModeConfiguration.default(for: mode)
        }
    }
    
    public func setMode(_ mode: JarvisAssistantMode) {
        currentMode = mode
    }
    
    public func configuration(for mode: JarvisAssistantMode) -> ModeConfiguration {
        configurations[mode] ?? ModeConfiguration.default(for: mode)
    }
    
    public func updateConfiguration(_ configuration: ModeConfiguration) {
        configurations[configuration.mode] = configuration
    }
    
    public func template(for mode: JarvisAssistantMode) -> ModePromptTemplate {
        ModePromptTemplate(mode: mode)
    }
    
    public func applyMode(to classification: JarvisTaskClassification) -> JarvisTaskClassification {
        let mode = JarvisAssistantMode.mode(for: classification.category)
        let config = configuration(for: mode)
        
        return JarvisTaskClassification(
            category: classification.category,
            task: classification.task,
            preset: mode.defaultPreset,
            confidence: classification.confidence,
            reasoningHint: mode.reasoningHint,
            responseHint: mode.responseHint,
            shouldInjectKnowledge: classification.shouldInjectKnowledge,
            shouldPreferStructuredOutput: classification.shouldPreferStructuredOutput
        )
    }
}
