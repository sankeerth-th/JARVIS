import Foundation
import MailKit
import OSLog

@MainActor
final class JarvisComposeSessionHandler: NSObject, MEComposeSessionHandler {
    private static var activeSessionIDs: Set<UUID> = []
    private let logger = Logger(subsystem: "com.offline.Jarvis.MailExtension", category: "ComposeSession")

    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        Self.activeSessionIDs.insert(session.sessionID)
        logger.info("mailComposeSessionDidBegin. session=\(session.sessionID.uuidString, privacy: .public)")
    }

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {
        Self.activeSessionIDs.remove(session.sessionID)
        logger.info("mailComposeSessionDidEnd. session=\(session.sessionID.uuidString, privacy: .public)")
    }

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        let hasBegun = Self.activeSessionIDs.contains(session.sessionID)
        logger.info("viewController(for:) requested. session=\(session.sessionID.uuidString, privacy: .public) began=\(hasBegun, privacy: .public)")
        return JarvisMailViewController(session: session, sessionBegan: hasBegun)
    }
}
