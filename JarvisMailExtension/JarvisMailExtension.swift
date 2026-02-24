import Foundation
import MailKit
import OSLog

@objc(JarvisMailExtension)
final class JarvisMailExtension: NSObject, MEExtension {
    private let logger = Logger(subsystem: "com.offline.Jarvis.MailExtension", category: "Extension")
    private let composeHandler = JarvisComposeSessionHandler()

    func handler(for session: MEComposeSession) -> MEComposeSessionHandler {
        logger.info("handler(for:) requested. session=\(session.sessionID.uuidString, privacy: .public)")
        return composeHandler
    }
}
