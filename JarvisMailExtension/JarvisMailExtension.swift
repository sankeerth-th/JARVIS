import Foundation
import MailKit
import OSLog

final class JarvisMailExtension: NSObject, MEExtension {
    private let logger = Logger(subsystem: "com.offline.Jarvis.MailExtension", category: "Extension")
    private let composeHandler = JarvisComposeSessionHandler()

    override init() {
        super.init()
        logger.info("JarvisMailExtension initialized")
    }

    func handler(for session: MEComposeSession) -> MEComposeSessionHandler {
        logger.info("handler(for:) requested. session=\(session.sessionID.uuidString, privacy: .public)")
        return composeHandler
    }
}
