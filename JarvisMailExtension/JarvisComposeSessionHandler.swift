import Foundation
import MailKit

final class JarvisComposeSessionHandler: NSObject, MEComposeSessionHandler {
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        // Mail owns the compose lifecycle; no setup required here.
    }

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {
        // Keep implementation lightweight; no retained resources.
    }

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        JarvisMailViewController(session: session)
    }
}
