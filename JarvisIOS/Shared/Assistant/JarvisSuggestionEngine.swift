import Foundation

// MARK: - Suggestion Context

public struct SuggestionContext: Equatable {
    public let responseText: String
    public let classification: JarvisTaskClassification
    public let mode: JarvisAssistantMode
    public let conversationHistory: [JarvisChatMessage]
    public let userIntent: String
    
    public init(
        responseText: String,
        classification: JarvisTaskClassification,
        mode: JarvisAssistantMode,
        conversationHistory: [JarvisChatMessage] = [],
        userIntent: String = ""
    ) {
        self.responseText = responseText
        self.classification = classification
        self.mode = mode
        self.conversationHistory = conversationHistory
        self.userIntent = userIntent
    }
}

// MARK: - Suggestion Template

public struct SuggestionTemplate: Equatable {
    public let title: String
    public let icon: String
    public let action: JarvisAssistantSuggestionDescriptorAction
    public let relevanceScore: Double
    public let conditions: [SuggestionCondition]
    
    public init(
        title: String,
        icon: String,
        action: JarvisAssistantSuggestionDescriptorAction,
        relevanceScore: Double = 1.0,
        conditions: [SuggestionCondition] = []
    ) {
        self.title = title
        self.icon = icon
        self.action = action
        self.relevanceScore = relevanceScore
        self.conditions = conditions
    }
}

// MARK: - Suggestion Condition

public enum SuggestionCondition: Equatable {
    case responseContains(String)
    case responseLengthGreaterThan(Int)
    case responseLengthLessThan(Int)
    case taskCategory(JarvisTaskCategory)
    case mode(JarvisAssistantMode)
    case hasCode
    case hasList
    case hasQuestion
    case confidenceGreaterThan(Double)
    
    public func evaluate(context: SuggestionContext) -> Bool {
        switch self {
        case .responseContains(let substring):
            return context.responseText.lowercased().contains(substring.lowercased())
            
        case .responseLengthGreaterThan(let length):
            return context.responseText.count > length
            
        case .responseLengthLessThan(let length):
            return context.responseText.count < length
            
        case .taskCategory(let category):
            return context.classification.category == category
            
        case .mode(let mode):
            return context.mode == mode
            
        case .hasCode:
            return context.responseText.contains("```") ||
                   context.responseText.contains("func ") ||
                   context.responseText.contains("class ") ||
                   context.responseText.contains("struct ")
            
        case .hasList:
            return context.responseText.contains("1.") ||
                   context.responseText.contains("- ") ||
                   context.responseText.contains("• ")
            
        case .hasQuestion:
            return context.responseText.contains("?")
            
        case .confidenceGreaterThan(let threshold):
            return context.classification.confidence > threshold
        }
    }
}

// MARK: - Suggestion Engine

@MainActor
public final class SuggestionEngine {
    
    private var templates: [SuggestionTemplate] = []
    private let maxSuggestions = 5
    
    public init() {
        registerDefaultTemplates()
    }
    
    // MARK: - Public API
    
    public func generateSuggestions(
        responseText: String,
        classification: JarvisTaskClassification,
        mode: JarvisAssistantMode,
        conversationHistory: [JarvisChatMessage] = []
    ) -> [JarvisAssistantSuggestionDescriptor] {
        
        let context = SuggestionContext(
            responseText: responseText,
            classification: classification,
            mode: mode,
            conversationHistory: conversationHistory
        )
        
        // Filter and score templates
        let scoredTemplates = templates.compactMap { template -> (SuggestionTemplate, Double)? in
            let matches = template.conditions.allSatisfy { $0.evaluate(context: context) }
            guard matches else { return nil }
            
            let score = calculateRelevance(template: template, context: context)
            return (template, score)
        }
        
        // Sort by relevance and take top N
        let sorted = scoredTemplates.sorted { $0.1 > $1.1 }.prefix(maxSuggestions)
        
        return sorted.map { $0.0.toDescriptor() }
    }
    
    public func registerTemplate(_ template: SuggestionTemplate) {
        templates.append(template)
    }
    
    public func clearTemplates() {
        templates.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func calculateRelevance(template: SuggestionTemplate, context: SuggestionContext) -> Double {
        var score = template.relevanceScore
        
        // Boost based on classification match
        if template.conditions.contains(where: { 
            if case .taskCategory(let cat) = $0 { return cat == context.classification.category }
            return false
        }) {
            score += 0.2
        }
        
        // Boost based on mode match
        if template.conditions.contains(where: {
            if case .mode(let m) = $0 { return m == context.mode }
            return false
        }) {
            score += 0.15
        }
        
        // Boost for longer responses (more to work with)
        if context.responseText.count > 200 {
            score += 0.1
        }
        
        return min(score, 1.0)
    }
    
    // MARK: - Default Templates
    
    private func registerDefaultTemplates() {
        // General follow-up templates
        registerTemplate(SuggestionTemplate(
            title: "Follow-up",
            icon: "arrow.turn.down.right",
            action: .prompt("Can you expand on that with one practical next step?"),
            relevanceScore: 0.8
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Summarize",
            icon: "text.quote",
            action: .task(.summarize, "Summarize this for me"),
            conditions: [.responseLengthGreaterThan(300)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Save to Knowledge",
            icon: "bookmark",
            action: .saveToKnowledge,
            relevanceScore: 0.7
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Voice Follow-up",
            icon: "waveform",
            action: .voiceFollowUp,
            relevanceScore: 0.6
        ))
        
        // Coding-specific templates
        registerTemplate(SuggestionTemplate(
            title: "Add Tests",
            icon: "checklist",
            action: .prompt("Add the most important test cases for that solution."),
            conditions: [.taskCategory(.coding), .hasCode]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Explain Code",
            icon: "doc.text.magnifyingglass",
            action: .prompt("Explain that code in simpler terms."),
            conditions: [.taskCategory(.coding), .hasCode]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Optimize",
            icon: "bolt",
            action: .prompt("How can I optimize that code for better performance?"),
            conditions: [.taskCategory(.coding), .hasCode]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Refactor",
            icon: "hammer",
            action: .prompt("Refactor that code to be cleaner and more maintainable."),
            conditions: [.taskCategory(.coding), .responseLengthGreaterThan(200)]
        ))
        
        // Summarization templates
        registerTemplate(SuggestionTemplate(
            title: "Expand",
            icon: "plus.bubble",
            action: .prompt("Expand the summary with one more layer of detail."),
            conditions: [.taskCategory(.summarization)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Rewrite Shorter",
            icon: "text.badge.minus",
            action: .prompt("Rewrite that in about half the length."),
            conditions: [.taskCategory(.summarization), .responseLengthGreaterThan(200)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Key Points",
            icon: "list.bullet",
            action: .prompt("Extract just the key points as a bulleted list."),
            conditions: [.taskCategory(.summarization)]
        ))
        
        // Drafting templates
        registerTemplate(SuggestionTemplate(
            title: "More Direct",
            icon: "arrow.right.to.line",
            action: .prompt("Rewrite that to sound more direct and concise."),
            conditions: [.taskCategory(.draftingMessage)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Warmer Tone",
            icon: "heart.text.square",
            action: .prompt("Rewrite that with a warmer, more human tone."),
            conditions: [.taskCategory(.draftingMessage)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Professional",
            icon: "briefcase",
            action: .prompt("Make that sound more professional and formal."),
            conditions: [.taskCategory(.draftingEmail)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Shorter",
            icon: "text.badge.minus",
            action: .prompt("Rewrite that in about half the length."),
            conditions: [.taskCategory(.draftingMessage), .responseLengthGreaterThan(150)]
        ))
        
        // Explanation templates
        registerTemplate(SuggestionTemplate(
            title: "Simpler",
            icon: "textformat.alt",
            action: .prompt("Explain that in simpler language."),
            conditions: [.taskCategory(.explainingSomething)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Example",
            icon: "lightbulb",
            action: .prompt("Add one practical example."),
            conditions: [.taskCategory(.explainingSomething)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Analogy",
            icon: "theatermasks",
            action: .prompt("Explain that using an analogy."),
            conditions: [.taskCategory(.explainingSomething)]
        ))
        
        // Planning templates
        registerTemplate(SuggestionTemplate(
            title: "Checklist",
            icon: "checklist",
            action: .prompt("Turn that plan into a checklist with priorities."),
            conditions: [.taskCategory(.planning), .hasList]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Timeline",
            icon: "calendar",
            action: .prompt("Add estimated timeframes to each step."),
            conditions: [.taskCategory(.planning)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Risks",
            icon: "exclamationmark.triangle",
            action: .prompt("What are the main risks or blockers for this plan?"),
            conditions: [.taskCategory(.planning)]
        ))
        
        // Question answering templates
        registerTemplate(SuggestionTemplate(
            title: "Sources",
            icon: "books.vertical",
            action: .prompt("What sources or evidence support that answer?"),
            conditions: [.taskCategory(.questionAnswering)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Related",
            icon: "link",
            action: .prompt("What related topics should I also understand?"),
            conditions: [.taskCategory(.questionAnswering), .confidenceGreaterThan(0.7)]
        ))
        
        // Reply-specific templates
        registerTemplate(SuggestionTemplate(
            title: "Formal Tone",
            icon: "textformat.abc",
            action: .prompt("Rewrite that reply with a more formal tone."),
            conditions: [.taskCategory(.contextAwareReply)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Friendly Tone",
            icon: "face.smiling",
            action: .prompt("Rewrite that reply with a friendlier, more casual tone."),
            conditions: [.taskCategory(.contextAwareReply)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Add Question",
            icon: "questionmark.bubble",
            action: .prompt("Add a clarifying question to that reply."),
            conditions: [.taskCategory(.contextAwareReply)]
        ))
        
        // Mode-specific templates
        registerTemplate(SuggestionTemplate(
            title: "Deep Dive",
            icon: "arrow.down.circle",
            action: .prompt("Go deeper on that topic."),
            conditions: [.mode(.explain)]
        ))
        
        registerTemplate(SuggestionTemplate(
            title: "Quick Version",
            icon: "bolt",
            action: .prompt("Give me the quick version of that."),
            conditions: [.mode(.explain), .responseLengthGreaterThan(300)]
        ))
    }
}

// MARK: - Template Extension

extension SuggestionTemplate {
    func toDescriptor() -> JarvisAssistantSuggestionDescriptor {
        JarvisAssistantSuggestionDescriptor(
            title: title,
            icon: icon,
            action: action
        )
    }
}
