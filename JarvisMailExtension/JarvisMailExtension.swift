import Foundation
import MailKit
import OSLog

@objc(JarvisMailExtension)
final class JarvisMailExtension: NSObject, MEExtension {
    private let logger = Logger(subsystem: "com.offline.Jarvis.MailExtension", category: "Extension")

    func handler(for session: MEComposeSession) -> any MEComposeSessionHandler {
        logger.info("handler(for:) requested. session=\(session.sessionID.uuidString, privacy: .public)")
        return JarvisComposeSessionHandler()
    }
}
