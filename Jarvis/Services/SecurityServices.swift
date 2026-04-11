import CryptoKit
import Foundation
import Security

enum JarvisPersistedValueSecurityClass {
    case `public`
    case `internal`
    case sensitive
    case secret

    var allowsUserDefaultsStorage: Bool {
        switch self {
        case .public, .internal:
            return true
        case .sensitive, .secret:
            return false
        }
    }
}

struct JarvisSecurityRedactor {
    private static let rules: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, options: [.caseInsensitive]), "<redacted-email>"),
        (try! NSRegularExpression(pattern: #"\b(?:\+?1[-.\s]?)?(?:\(?\d{3}\)?[-.\s]?){2}\d{4}\b"#), "<redacted-phone>"),
        (try! NSRegularExpression(pattern: #"(?i)\b(?:bearer|token|api[_-]?key|authorization)\s*[:=]\s*["']?[A-Z0-9._\-+/=]{8,}"#, options: [.caseInsensitive]), "<redacted-secret>"),
        (try! NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,19}\b"#), "<redacted-card>"),
        (try! NSRegularExpression(pattern: #"/Users/[^/\s]+(?:/[^\s]*)?"#), "/Users/<redacted-user>"),
        (try! NSRegularExpression(pattern: #"https?://(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?[^\s]*"#, options: [.caseInsensitive]), "<redacted-loopback-url>")
    ]

    static func redact(_ value: String) -> String {
        var result = value
        for (regex, replacement) in rules {
            let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: fullRange, withTemplate: replacement)
        }
        return result
    }

    static func redact(metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [String: String]()) { partial, entry in
            partial[redact(entry.key)] = redact(entry.value)
        }
    }
}

final class JarvisSecureStore {
    static let shared = JarvisSecureStore(service: Bundle.main.bundleIdentifier ?? "com.offline.Jarvis.secure")

    private let service: String

    init(service: String) {
        self.service = service
    }

    func data(for account: String) -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    func set(_ data: Data, for account: String) {
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemDelete(query as CFDictionary)
        SecItemAdd(newItem as CFDictionary, nil)
    }

    func remove(account: String) {
        SecItemDelete(baseQuery(for: account) as CFDictionary)
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class JarvisSecurityEnvelope {
    static let shared = JarvisSecurityEnvelope()

    private let keyAccount = "jarvis.security.masterkey.v1"
    private let secureStore: JarvisSecureStore

    init(secureStore: JarvisSecureStore = .shared) {
        self.secureStore = secureStore
    }

    func seal(_ plaintext: Data, purpose: String) throws -> Data {
        let key = try loadOrCreateKey()
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: Data(purpose.utf8))
        guard let combined = box.combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return combined
    }

    func open(_ ciphertext: Data, purpose: String) throws -> Data {
        let key = try loadOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: key, authenticating: Data(purpose.utf8))
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = secureStore.data(for: keyAccount) {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        secureStore.set(keyData, for: keyAccount)
        return key
    }
}

enum JarvisLoopbackSecurityError: LocalizedError {
    case unsupportedHost
    case insecureLoopbackDisabled
    case bodyTooLarge
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedHost:
            return "Only authenticated loopback inference hosts are allowed."
        case .insecureLoopbackDisabled:
            return "Local network inference is disabled in production builds."
        case .bodyTooLarge:
            return "The local inference request exceeded the allowed size."
        case .responseTooLarge:
            return "The local inference response exceeded the allowed size."
        }
    }
}

struct JarvisLoopbackSecurityPolicy {
    static let allowedHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
    static let maxRequestBodyBytes = 512_000
    static let maxResponseBodyBytes = 4_000_000
    static let tokenHeaderName = "X-Jarvis-Local-Auth"
    static let storeAccount = "jarvis.loopback.token.v1"

    static var allowsLocalInference: Bool {
        true
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    static func validate(url: URL, body: Data?) throws {
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            throw JarvisLoopbackSecurityError.unsupportedHost
        }
        guard allowsLocalInference else {
            throw JarvisLoopbackSecurityError.insecureLoopbackDisabled
        }
        if let body, body.count > maxRequestBodyBytes {
            throw JarvisLoopbackSecurityError.bodyTooLarge
        }
    }

    static func authenticatedRequest(url: URL, method: String, body: Data?) throws -> URLRequest {
        try validate(url: url, body: body)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(loopbackToken(), forHTTPHeaderField: tokenHeaderName)
        request.timeoutInterval = 20
        return request
    }

    static func enforceResponseLimit(on data: Data) throws {
        if data.count > maxResponseBodyBytes {
            throw JarvisLoopbackSecurityError.responseTooLarge
        }
    }

    static func loopbackToken() -> String {
        if let existing = JarvisSecureStore.shared.data(for: storeAccount),
           let token = String(data: existing, encoding: .utf8),
           !token.isEmpty {
            return token
        }

        let token = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        JarvisSecureStore.shared.set(Data(token.utf8), for: storeAccount)
        return token
    }
}
