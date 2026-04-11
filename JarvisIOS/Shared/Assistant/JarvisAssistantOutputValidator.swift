import Foundation

public enum JarvisAssistantGenerationStopReason: String, Codable, Equatable {
    case eos = "eos"
    case stopSequence = "stop_sequence"
    case maxTokens = "max_tokens"
    case repetitionAbort = "repetition_abort"
    case memoryAbort = "memory_abort"
    case thermalAbort = "thermal_abort"
    case externalCancel = "external_cancel"
    case validationFailure = "validation_failure"
    case unknown = "unknown"
}

public enum JarvisAssistantOutputValidationStatus: String, Codable, Equatable {
    case passed
    case empty
    case punctuationOnly
    case tooShort
    case missingCodeStructure
}

public struct JarvisAssistantOutputValidationResult: Equatable, Codable {
    public let status: JarvisAssistantOutputValidationStatus
    public let normalizedText: String
    public let failureDetail: String?

    public init(
        status: JarvisAssistantOutputValidationStatus,
        normalizedText: String,
        failureDetail: String? = nil
    ) {
        self.status = status
        self.normalizedText = normalizedText
        self.failureDetail = failureDetail
    }

    public var isValid: Bool {
        status == .passed
    }
}

enum JarvisAssistantOutputValidator {
    static func validate(
        text: String,
        classification: JarvisTaskClassification
    ) -> JarvisAssistantOutputValidationResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return JarvisAssistantOutputValidationResult(
                status: .empty,
                normalizedText: "",
                failureDetail: "The model returned no text."
            )
        }

        let punctuationTrimmed = normalized.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        if punctuationTrimmed.isEmpty {
            return JarvisAssistantOutputValidationResult(
                status: .punctuationOnly,
                normalizedText: normalized,
                failureDetail: "The model returned punctuation-only output."
            )
        }

        let alphanumericCount = normalized.unicodeScalars.filter(CharacterSet.alphanumerics.contains).count
        if alphanumericCount < 3 || normalized.count < 2 {
            return JarvisAssistantOutputValidationResult(
                status: .tooShort,
                normalizedText: normalized,
                failureDetail: "The model output was too short to be useful."
            )
        }

        if classification.category == .coding && !containsCodeLikeStructure(normalized) {
            return JarvisAssistantOutputValidationResult(
                status: .missingCodeStructure,
                normalizedText: normalized,
                failureDetail: "Coding output did not contain code-like structure."
            )
        }

        return JarvisAssistantOutputValidationResult(
            status: .passed,
            normalizedText: normalized
        )
    }

    static func isHighValueRetryTask(_ classification: JarvisTaskClassification) -> Bool {
        switch classification.category {
        case .coding, .draftingEmail, .draftingMessage, .planning, .contextAwareReply:
            return true
        default:
            return false
        }
    }

    private static func containsCodeLikeStructure(_ text: String) -> Bool {
        if text.contains("```") || text.contains("`") {
            return true
        }

        let lowered = text.lowercased()
        let markers = [
            "func ", "let ", "var ", "const ", "class ", "struct ", "enum ",
            "return ", "if ", "guard ", "switch ", "case ", "import ",
            "{", "}", "=>", "==", "!=", "print(", "console.", "def ",
            "public ", "private ", "async ", "await ", "@mainactor"
        ]
        return markers.contains(where: { lowered.contains($0) })
    }
}
