import Foundation

enum OllamaError: LocalizedError {
    case unreachable
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .unreachable: return "Ollama server is not reachable on 127.0.0.1:11434 (or localhost:11434)"
        case .invalidResponse: return "Received invalid response from Ollama"
        case .apiError(let message): return message
        }
    }
}

struct OllamaModel: Codable {
    let name: String
    let modified_at: String?
    let size: Int?
}

struct GenerateRequest: Encodable {
    var model: String
    var prompt: String
    var system: String
    var stream: Bool
    var options: [String: Double]?

    init(model: String, prompt: String, system: String, stream: Bool = true, options: [String: Double]? = nil) {
        self.model = model
        self.prompt = prompt
        self.system = system
        self.stream = stream
        self.options = options
    }
}

struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatRequest: Encodable {
    var model: String
    var messages: [OllamaChatMessage]
    var stream: Bool
    var options: [String: Double]?

    init(model: String, messages: [OllamaChatMessage], stream: Bool = true, options: [String: Double]? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.options = options
    }
}

final class OllamaClient {
    private let session: URLSession
    private let candidateBaseURLs: [URL]

    init(baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared) {
        self.session = session
        self.candidateBaseURLs = Self.buildCandidateBaseURLs(from: baseURL)
    }

    func listModels() async throws -> [OllamaModel] {
        let (data, response) = try await request(path: "api/tags")
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.unreachable }
        struct TagResponse: Codable { let models: [OllamaModel] }
        let decoded = try JSONDecoder().decode(TagResponse.self, from: data)
        return decoded.models
    }

    func pullModel(named name: String) async throws {
        let body = ["name": name]
        var requestBody = try JSONSerialization.data(withJSONObject: body)
        if requestBody.isEmpty {
            requestBody = Data("{}".utf8)
        }
        let (_, response) = try await request(path: "api/pull", method: "POST", body: requestBody)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.invalidResponse }
    }

    func generate(request: GenerateRequest) async throws -> String {
        let body = try JSONEncoder().encode(request)
        let (data, response) = try await self.request(path: "api/generate", method: "POST", body: body)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.invalidResponse }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let responseText = json["response"] as? String else {
            throw OllamaError.invalidResponse
        }
        return responseText
    }

    func chat(request: ChatRequest) async throws -> String {
        let body = try JSONEncoder().encode(request)
        let (data, response) = try await self.request(path: "api/chat", method: "POST", body: body)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.invalidResponse }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OllamaError.invalidResponse
        }
        return content
    }

    func streamGenerate(request: GenerateRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    let body = try JSONEncoder().encode(request)
                    let (bytes, response) = try await self.streamRequest(path: "api/generate", body: body)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw OllamaError.invalidResponse
                    }
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8) else { continue }
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let response = json["response"] as? String {
                            continuation.yield(response)
                        }
                        if let done = json["done"] as? Bool, done {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func streamChat(request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    let body = try JSONEncoder().encode(request)
                    let (bytes, response) = try await self.streamRequest(path: "api/chat", body: body)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw OllamaError.invalidResponse
                    }
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8) else { continue }
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let message = json["message"] as? [String: Any],
                           let content = message["content"] as? String,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
                        if let done = json["done"] as? Bool, done {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func embeddings(for text: String, model: String) async throws -> [Double] {
        let body: [String: Any] = ["model": model, "prompt": text]
        var requestBody = try JSONSerialization.data(withJSONObject: body)
        if requestBody.isEmpty {
            requestBody = Data("{}".utf8)
        }
        let (data, response) = try await request(path: "api/embeddings", method: "POST", body: requestBody)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.invalidResponse }
        struct EmbeddingResponse: Codable { let embedding: [Double] }
        let decoded = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return decoded.embedding
    }

    func isReachable() async -> Bool {
        do {
            _ = try await listModels()
            return true
        } catch {
            return false
        }
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, URLResponse) {
        try await withFallback { baseURL in
            var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
            urlRequest.httpMethod = method
            urlRequest.httpBody = body
            if body != nil {
                urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            return try await session.data(for: urlRequest)
        }
    }

    private func streamRequest(path: String, body: Data) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await withFallback { baseURL in
            var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
            urlRequest.httpMethod = "POST"
            urlRequest.httpBody = body
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            return try await session.bytes(for: urlRequest)
        }
    }

    private func withFallback<T>(_ work: (URL) async throws -> T) async throws -> T {
        var lastError: Error = OllamaError.unreachable
        for (index, baseURL) in candidateBaseURLs.enumerated() {
            do {
                return try await work(baseURL)
            } catch {
                lastError = error
                let shouldTryNext = index < candidateBaseURLs.count - 1 && isConnectionError(error)
                if !shouldTryNext { break }
            }
        }
        if isConnectionError(lastError) {
            throw OllamaError.unreachable
        }
        throw lastError
    }

    private func isConnectionError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func buildCandidateBaseURLs(from preferred: URL) -> [URL] {
        guard let host = preferred.host?.lowercased(), host == "localhost" else {
            return [preferred]
        }
        var components = URLComponents(url: preferred, resolvingAgainstBaseURL: false)
        components?.host = "127.0.0.1"
        if let ipv4Loopback = components?.url {
            return [ipv4Loopback, preferred]
        }
        return [preferred]
    }
}
