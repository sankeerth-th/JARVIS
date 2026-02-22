import Foundation
import MailKit

@objc(JarvisMailExtension)
final class JarvisMailExtension: NSObject, MEExtension {
    func handler(for session: MEComposeSession) -> any MEComposeSessionHandler {
        JarvisComposeSessionHandler()
    }
}
