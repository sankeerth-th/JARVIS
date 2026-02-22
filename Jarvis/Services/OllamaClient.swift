import Foundation

enum OllamaError: LocalizedError {
    case unreachable
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .unreachable: return "Ollama server is not running on localhost:11434"
        case .invalidResponse: return "Received invalid response from Ollama"
        case .apiError(let message): return message
        }
    }
}

struct OllamaModel: Codable {
    let name: String
    let modified_at: Date?
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

final class OllamaClient {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func listModels() async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("/api/tags")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.unreachable }
        struct TagResponse: Codable { let models: [OllamaModel] }
        let decoded = try JSONDecoder().decode(TagResponse.self, from: data)
        return decoded.models
    }

    func pullModel(named name: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/pull"))
        request.httpMethod = "POST"
        let body = ["name": name]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.invalidResponse }
    }

    func generate(request: GenerateRequest) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/generate"))
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(request)
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.invalidResponse }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let responseText = json["response"] as? String else {
            throw OllamaError.invalidResponse
        }
        return responseText
    }

    func streamGenerate(request: GenerateRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("/api/generate"))
                    req.httpMethod = "POST"
                    req.httpBody = try JSONEncoder().encode(request)
                    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    let (bytes, response) = try await self.session.bytes(for: req)
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

    func embeddings(for text: String, model: String) async throws -> [Double] {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/embeddings"))
        request.httpMethod = "POST"
        let body = ["model": model, "prompt": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
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
}
