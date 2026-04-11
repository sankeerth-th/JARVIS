import Foundation

struct JarvisMailPanelDraftState: Codable, Equatable {
    var modelName: String
    var userInstruction: String
    var extractedThreadPreview: String
    var outputText: String
    var updatedAt: Date
}

enum JarvisMailPanelDraftStore {
    static let keyPrefix = "jarvis_mail_session_"
    static let staleInterval: TimeInterval = 7 * 24 * 3600

    static func save(
        _ state: JarvisMailPanelDraftState,
        sessionID: UUID,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: keyPrefix + sessionID.uuidString)
        prune(defaults: defaults)
    }

    static func load(
        sessionID: UUID,
        defaults: UserDefaults = .standard
    ) -> JarvisMailPanelDraftState? {
        guard let data = defaults.data(forKey: keyPrefix + sessionID.uuidString),
              let state = try? JSONDecoder().decode(JarvisMailPanelDraftState.self, from: data) else {
            return nil
        }
        return state
    }

    static func remove(
        sessionID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: keyPrefix + sessionID.uuidString)
    }

    static func prune(defaults: UserDefaults = .standard, now: Date = Date()) {
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(keyPrefix) {
            guard let data = value as? Data,
                  let state = try? JSONDecoder().decode(JarvisMailPanelDraftState.self, from: data) else {
                defaults.removeObject(forKey: key)
                continue
            }
            if now.timeIntervalSince(state.updatedAt) > staleInterval {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
