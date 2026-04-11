import Foundation

public final class JarvisOllamaRemoteEngine: JarvisGGUFEngine {
    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Codable {
        struct Options: Codable {
            let temperature: Double
            let numCtx: Int
            let numPredict: Int

            enum CodingKeys: String, CodingKey {
                case temperature
                case numCtx = "num_ctx"
                case numPredict = "num_predict"
            }
        }

        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let options: Options
    }

    private struct ChatStreamChunk: Decodable {
        struct ResponseMessage: Decodable {
            let role: String?
            let content: String?
        }

        let message: ResponseMessage?
        let done: Bool?
        let error: String?
    }

    private struct ShowRequest: Codable {
        let name: String
    }

    private struct ShowResponse: Decodable {
        let error: String?
    }

    private let session: URLSession
    private let lock = NSLock()
    private var configuration = JarvisRuntimeConfiguration()
    private var requestTuning: JarvisGenerationTuning?
    private var cancelRequested = false
    private var activeModelName: String?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public var name: String { "Ollama Remote" }
    public var isInstalled: Bool { true }
    public var capability: JarvisGGUFEngineCapability { .fullInference }
    public var supportsVisualInputs: Bool { false }

    public func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        withLock {
            self.configuration = configuration
        }
    }

    public func updateGenerationTuning(_ tuning: JarvisGenerationTuning?) {
        withLock {
            self.requestTuning = tuning
        }
    }

    public func loadModel(at path: String, projectorPath: String?) async throws {
        _ = projectorPath
        let config = withLock { configuration }
        guard let baseURL = config.ollama.normalizedBaseURL else {
            throw JarvisModelError.unavailable("Ollama server URL is missing or invalid.")
        }

        let modelName = config.ollama.modelName.isEmpty ? path : config.ollama.modelName
        guard !modelName.isEmpty else {
            throw JarvisModelError.unavailable("Ollama model name is missing.")
        }

        let requestURL = baseURL.appending(path: "api/show")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = config.ollama.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ShowRequest(name: modelName))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JarvisModelError.runtimeFailure("Ollama server returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw JarvisModelError.runtimeFailure("Ollama model check failed: \(message)")
        }

        if let show = try? JSONDecoder().decode(ShowResponse.self, from: data),
           let error = show.error,
           !error.isEmpty {
            throw JarvisModelError.runtimeFailure("Ollama model check failed: \(error)")
        }

        withLock {
            activeModelName = modelName
            cancelRequested = false
        }
    }

    public func unloadModel() async {
        withLock {
            activeModelName = nil
            cancelRequested = false
        }
    }

    public func generate(
        request: JarvisAssistantRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> JarvisRuntimeGenerationOutcome {
        let config = withLock { configuration }
        guard let baseURL = config.ollama.normalizedBaseURL else {
            throw JarvisModelError.unavailable("Ollama server URL is missing or invalid.")
        }

        let modelName = withLock { activeModelName } ?? config.ollama.modelName
        guard !modelName.isEmpty else {
            throw JarvisModelError.unavailable("Ollama model name is missing.")
        }

        withLock {
            cancelRequested = false
        }

        let requestURL = baseURL.appending(path: "api/chat")
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = config.ollama.requestTimeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = mappedMessages(for: request)
        let payload = ChatRequest(
            model: modelName,
            messages: messages,
            stream: true,
            options: .init(
                temperature: request.tuning.temperature,
                numCtx: request.tuning.maxContextTokens,
                numPredict: request.tuning.maxOutputTokens
            )
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let promptCharacterEstimate = messages.reduce(0) { partial, message in
            partial + message.content.count + message.role.count
        }
        let promptTokenEstimate = max(1, Int((Double(promptCharacterEstimate) / 4.0).rounded(.up)))

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw JarvisModelError.runtimeFailure("Ollama server returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw JarvisModelError.runtimeFailure("Ollama request failed with HTTP \(http.statusCode).")
        }

        var emittedAnyContent = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if withLock({ cancelRequested }) {
                throw JarvisModelError.cancelled
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let chunk = try JSONDecoder().decode(ChatStreamChunk.self, from: Data(trimmed.utf8))
            if let error = chunk.error, !error.isEmpty {
                throw JarvisModelError.runtimeFailure("Ollama error: \(error)")
            }

            if let content = chunk.message?.content, !content.isEmpty {
                emittedAnyContent = true
                onToken(content)
            }

            if chunk.done == true {
                break
            }
        }

        if !emittedAnyContent {
            throw JarvisModelError.runtimeFailure("Ollama returned no content for this request.")
        }

        return JarvisRuntimeGenerationOutcome(
            stopReason: .eos,
            requestedContextTokenLimit: request.tuning.maxContextTokens,
            effectiveContextTokenLimit: request.tuning.maxContextTokens,
            effectiveOutputTokenLimit: request.tuning.maxOutputTokens,
            promptTokenEstimate: promptTokenEstimate,
            availableMemoryBytesAtStart: nil,
            memoryFallbackTriggered: false,
            thermalFallbackTriggered: false,
            speculativeDecodingRequested: false,
            speculativeDecodingEligible: false,
            gpuOffloadEnabled: false,
            requestedGPULayerCount: 0,
            flashAttentionEnabled: false,
            estimatedKVCacheBytes: 0
        )
    }

    public func cancelGeneration() {
        withLock {
            cancelRequested = true
        }
    }

    private func mappedMessages(for request: JarvisAssistantRequest) -> [ChatMessage] {
        let blueprint = request.promptBlueprint
        let combinedSystemInstruction = [
            blueprint.systemInstruction,
            blueprint.assistantRole,
            blueprint.taskTypeInstruction,
            blueprint.responseInstruction
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        var messages: [ChatMessage] = []
        if !combinedSystemInstruction.isEmpty {
            messages.append(ChatMessage(role: "system", content: combinedSystemInstruction))
        }

        for block in blueprint.contextBlocks where !block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let content = block.title.isEmpty ? block.content : "\(block.title):\n\(block.content)"
            messages.append(ChatMessage(role: "system", content: content))
        }

        if blueprint.contextBlocks.isEmpty {
            if let replyTargetText = request.replyTargetText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !replyTargetText.isEmpty {
                messages.append(ChatMessage(role: "system", content: "Draft reply target context:\n\(replyTargetText)"))
            }

            if !request.groundedResults.isEmpty {
                let grounding = request.groundedResults.prefix(request.task.groundingLimit).map { result in
                    "\(result.item.title): \(result.snippet)"
                }.joined(separator: "\n")
                messages.append(ChatMessage(role: "system", content: "Local knowledge context:\n\(grounding)"))
            }
        }

        let normalizedCurrentPrompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in request.history {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if item.role == .user, text == normalizedCurrentPrompt {
                continue
            }

            switch item.role {
            case .system:
                messages.append(ChatMessage(role: "system", content: text))
            case .user:
                messages.append(ChatMessage(role: "user", content: text))
            case .assistant:
                messages.append(ChatMessage(role: "assistant", content: text))
            }
        }

        messages.append(ChatMessage(role: "user", content: request.prompt))
        return messages
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
