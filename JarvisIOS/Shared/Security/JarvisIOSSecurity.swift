import CryptoKit
import Foundation
import Security

public enum JarvisIOSPersistedValueSecurityClass {
    case `public`
    case `internal`
    case sensitive
    case secret

    public var allowsPlainPersistence: Bool {
        switch self {
        case .public, .internal:
            return true
        case .sensitive, .secret:
            return false
        }
    }
}

public struct JarvisIOSSecurityRedactor {
    private static let rules: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, options: [.caseInsensitive]), "<redacted-email>"),
        (try! NSRegularExpression(pattern: #"\b(?:\+?1[-.\s]?)?(?:\(?\d{3}\)?[-.\s]?){2}\d{4}\b"#), "<redacted-phone>"),
        (try! NSRegularExpression(pattern: #"(?i)\b(?:bearer|token|api[_-]?key|authorization)\s*[:=]\s*["']?[A-Z0-9._\-+/=]{8,}"#, options: [.caseInsensitive]), "<redacted-secret>"),
        (try! NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,19}\b"#), "<redacted-card>")
    ]

    public static func redact(_ value: String) -> String {
        var result = value
        for (regex, replacement) in rules {
            let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: fullRange, withTemplate: replacement)
        }
        return result
    }
}

public final class JarvisIOSSecureStore {
    public static let shared = JarvisIOSSecureStore(service: Bundle.main.bundleIdentifier ?? "com.offline.JarvisIOS.secure")

    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func data(for account: String) -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    public func set(_ data: Data, for account: String) {
        let query = baseQuery(for: account)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemDelete(query as CFDictionary)
        SecItemAdd(newItem as CFDictionary, nil)
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public final class JarvisIOSSecurityEnvelope {
    public static let shared = JarvisIOSSecurityEnvelope()

    private let keyAccount = "jarvis.ios.security.masterkey.v1"
    private let secureStore: JarvisIOSSecureStore

    public init(secureStore: JarvisIOSSecureStore = .shared) {
        self.secureStore = secureStore
    }

    public func seal(_ plaintext: Data, purpose: String) throws -> Data {
        let key = try loadOrCreateKey()
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: Data(purpose.utf8))
        guard let combined = box.combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return combined
    }

    public func open(_ ciphertext: Data, purpose: String) throws -> Data {
        let key = try loadOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key, authenticating: Data(purpose.utf8))
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

public enum JarvisIOSStorageProtection {
    public static func prepareSensitiveDirectory(_ url: URL) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    public static func protectSensitiveFile(at url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
