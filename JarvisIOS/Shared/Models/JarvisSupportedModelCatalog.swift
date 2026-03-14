import Foundation

public enum JarvisSupportedModelProfileID: String, Codable, CaseIterable, Identifiable {
    case gemma3_4b_it_q4_0
    case llama32_1b_instruct_4bit

    public var id: String { rawValue }
}

public struct JarvisSupportedModelProfile: Equatable, Sendable, Identifiable {
    public var id: JarvisSupportedModelProfileID
    public var displayName: String
    public var shortDescription: String
    public var importGuidance: String
    public var activationGuidance: String
    public var allowedQuantizationTokens: [String]
    public var requiredFilenameGroups: [[String]]
    public var minimumFileSizeBytes: Int64
    public var maximumFileSizeBytes: Int64
    public var supportsVision: Bool
    public var recommendedRuntimeConfiguration: JarvisRuntimeConfiguration

    public init(
        id: JarvisSupportedModelProfileID,
        displayName: String,
        shortDescription: String,
        importGuidance: String,
        activationGuidance: String,
        allowedQuantizationTokens: [String],
        requiredFilenameGroups: [[String]],
        minimumFileSizeBytes: Int64,
        maximumFileSizeBytes: Int64,
        supportsVision: Bool,
        recommendedRuntimeConfiguration: JarvisRuntimeConfiguration
    ) {
        self.id = id
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.importGuidance = importGuidance
        self.activationGuidance = activationGuidance
        self.allowedQuantizationTokens = allowedQuantizationTokens
        self.requiredFilenameGroups = requiredFilenameGroups
        self.minimumFileSizeBytes = minimumFileSizeBytes
        self.maximumFileSizeBytes = maximumFileSizeBytes
        self.supportsVision = supportsVision
        self.recommendedRuntimeConfiguration = recommendedRuntimeConfiguration
    }

    public func matches(filename: String, fileSizeBytes: Int64) -> Bool {
        let normalized = Self.normalize(filename: filename)
        guard fileSizeBytes >= minimumFileSizeBytes, fileSizeBytes <= maximumFileSizeBytes else {
            return false
        }

        let hasRequiredTokens = requiredFilenameGroups.allSatisfy { group in
            group.contains { normalized.contains($0) }
        }
        guard hasRequiredTokens else { return false }

        return allowedQuantizationTokens.contains { normalized.contains($0) }
    }

    public func almostMatches(filename: String, fileSizeBytes: Int64) -> Bool {
        let normalized = Self.normalize(filename: filename)
        let hasRequiredTokens = requiredFilenameGroups.allSatisfy { group in
            group.contains { normalized.contains($0) }
        }
        return hasRequiredTokens && fileSizeBytes >= minimumFileSizeBytes / 2 && fileSizeBytes <= maximumFileSizeBytes * 2
    }

    private static func normalize(filename: String) -> String {
        filename
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}

public struct JarvisModelCompatibilityAssessment: Equatable, Sendable {
    public var status: JarvisModelRecordStatus
    public var supportedProfileID: JarvisSupportedModelProfileID?
    public var displayMessage: String
    public var developerNotes: [String]

    public init(
        status: JarvisModelRecordStatus,
        supportedProfileID: JarvisSupportedModelProfileID?,
        displayMessage: String,
        developerNotes: [String] = []
    ) {
        self.status = status
        self.supportedProfileID = supportedProfileID
        self.displayMessage = displayMessage
        self.developerNotes = developerNotes
    }
}

public enum JarvisSupportedModelCatalog {
    public static let goldPath = JarvisSupportedModelProfile(
        id: .gemma3_4b_it_q4_0,
        displayName: "Gemma 3 4B IT (Q4_0 GGUF)",
        shortDescription: "The serious iPhone foundation path: a bookmark-backed 4B Gemma model with future projector-based multimodal support.",
        importGuidance: "Import gemma-3-4b-it-q4_0.gguf for text use. Attach mmproj-model-f16-4B.gguf later to prepare for future visual input support.",
        activationGuidance: "After import, activate the model explicitly from Model Library. Warm it before the first heavy session or let Jarvis auto-warm on first send.",
        allowedQuantizationTokens: ["q40"],
        requiredFilenameGroups: [
            ["gemma"],
            ["3"],
            ["4b"],
            ["it", "instruct"]
        ],
        minimumFileSizeBytes: 2_800_000_000,
        maximumFileSizeBytes: 4_300_000_000,
        supportsVision: true,
        recommendedRuntimeConfiguration: JarvisRuntimeConfiguration(
            performanceProfile: .balanced,
            contextWindow: .compact,
            responseStyle: .balanced,
            temperature: 0.7,
            batterySaverMode: false
        )
    )

    public static let llamaFallback = JarvisSupportedModelProfile(
        id: .llama32_1b_instruct_4bit,
        displayName: "Llama 3.2 1B Instruct (4-bit GGUF)",
        shortDescription: "The first iPhone-supported gold path: small, text-only, and realistic for on-device local chat.",
        importGuidance: "Import a Llama 3.2 1B Instruct GGUF file quantized for 4-bit use, such as Q4_K_M, Q4_0, or IQ4_XS.",
        activationGuidance: "Once imported, activate it from Model Library and warm it before the first heavy session for best responsiveness.",
        allowedQuantizationTokens: ["q4km", "q40", "iq4xs"],
        requiredFilenameGroups: [
            ["llama"],
            ["32", "3.2"],
            ["1b"],
            ["instruct", "it"]
        ],
        minimumFileSizeBytes: 350_000_000,
        maximumFileSizeBytes: 1_800_000_000,
        supportsVision: false,
        recommendedRuntimeConfiguration: JarvisRuntimeConfiguration(
            performanceProfile: .balanced,
            contextWindow: .compact,
            responseStyle: .balanced,
            temperature: 0.7,
            batterySaverMode: false
        )
    )

    public static let allProfiles: [JarvisSupportedModelProfile] = [
        goldPath,
        llamaFallback
    ]

    public static func profile(for id: JarvisSupportedModelProfileID?) -> JarvisSupportedModelProfile? {
        guard let id else { return nil }
        return allProfiles.first(where: { $0.id == id })
    }

    public static func matchedProfile(
        filename: String,
        fileSizeBytes: Int64,
        format: JarvisModelFormat
    ) -> JarvisSupportedModelProfile? {
        guard format == .gguf else { return nil }
        return allProfiles.first(where: { $0.matches(filename: filename, fileSizeBytes: fileSizeBytes) })
    }

    public static func assess(filename: String, fileSizeBytes: Int64, format: JarvisModelFormat) -> JarvisModelCompatibilityAssessment {
        guard format == .gguf else {
            return JarvisModelCompatibilityAssessment(
                status: .unsupported,
                supportedProfileID: nil,
                displayMessage: "Only GGUF files are supported for the iPhone local model path."
            )
        }

        guard fileSizeBytes > 0 else {
            return JarvisModelCompatibilityAssessment(
                status: .invalid,
                supportedProfileID: nil,
                displayMessage: "Model file appears empty."
            )
        }

        if let matchedProfile = allProfiles.first(where: { $0.matches(filename: filename, fileSizeBytes: fileSizeBytes) }) {
            return JarvisModelCompatibilityAssessment(
                status: .ready,
                supportedProfileID: matchedProfile.id,
                displayMessage: "Supported iPhone profile. Safe to activate on a physical device.",
                developerNotes: [matchedProfile.shortDescription]
            )
        }

        if let nearMatch = allProfiles.first(where: { $0.almostMatches(filename: filename, fileSizeBytes: fileSizeBytes) }) {
            return JarvisModelCompatibilityAssessment(
                status: .unsupported,
                supportedProfileID: nil,
                displayMessage: "Imported, but not activatable on iPhone in this build. Jarvis currently supports \(nearMatch.displayName) only.",
                developerNotes: [
                    "Expected quantization tokens: \(nearMatch.allowedQuantizationTokens.joined(separator: ", "))",
                    "Expected size range: \(ByteCountFormatter.string(fromByteCount: nearMatch.minimumFileSizeBytes, countStyle: .file)) - \(ByteCountFormatter.string(fromByteCount: nearMatch.maximumFileSizeBytes, countStyle: .file))"
                ]
            )
        }

        return JarvisModelCompatibilityAssessment(
            status: .unsupported,
            supportedProfileID: nil,
            displayMessage: "Imported for inspection only. This iPhone build is optimized for \(goldPath.displayName), not generic GGUF activation.",
            developerNotes: [goldPath.importGuidance]
        )
    }
}
