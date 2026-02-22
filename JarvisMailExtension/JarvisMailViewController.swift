import AppKit
import MailKit

final class JarvisMailViewController: MEExtensionViewController {
    private let session: MEComposeSession
    private let statusLabel = NSTextField(labelWithString: "")

    init(session: MEComposeSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))

        let titleLabel = NSTextField(labelWithString: "Jarvis Draft Assistant")
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)

        let subtitleLabel = NSTextField(wrappingLabelWithString: "Send the current compose context to Jarvis, then generate your reply in the Jarvis Email tab.")
        subtitleLabel.textColor = .secondaryLabelColor

        let sendButton = NSButton(title: "Send Context to Jarvis", target: self, action: #selector(sendToJarvis))
        sendButton.bezelStyle = .rounded

        let openButton = NSButton(title: "Open Jarvis", target: self, action: #selector(openJarvisOnly))
        openButton.bezelStyle = .rounded

        statusLabel.textColor = .secondaryLabelColor

        let row = NSStackView(views: [sendButton, openButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .leading

        let stack = NSStackView(views: [titleLabel, subtitleLabel, row, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14)
        ])

        self.view = root
    }

    @objc
    private func openJarvisOnly() {
        guard let url = URL(string: "jarvis://mail-compose") else { return }
        if NSWorkspace.shared.open(url) {
            statusLabel.stringValue = "Opened Jarvis"
        } else {
            statusLabel.stringValue = "Could not open Jarvis"
        }
    }

    @objc
    private func sendToJarvis() {
        let message = session.mailMessage
        let subject = message.subject
        let to = message.toAddresses.map(emailString)
        let cc = message.ccAddresses.map(emailString)
        let bcc = message.bccAddresses.map(emailString)
        let context = composeContextPreview()

        var components = URLComponents()
        components.scheme = "jarvis"
        components.host = "mail-compose"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "to", value: to.joined(separator: ",")),
            URLQueryItem(name: "cc", value: cc.joined(separator: ",")),
            URLQueryItem(name: "bcc", value: bcc.joined(separator: ",")),
            URLQueryItem(name: "thread", value: context),
            URLQueryItem(name: "autoDraft", value: "1")
        ]

        guard let url = components.url else {
            statusLabel.stringValue = "Failed to build Jarvis payload"
            return
        }

        if NSWorkspace.shared.open(url) {
            statusLabel.stringValue = "Sent context to Jarvis"
        } else {
            statusLabel.stringValue = "Could not open Jarvis"
        }
    }

    private func composeContextPreview() -> String {
        let compose = session.composeContext
        let original = compose.originalMessage

        var lines: [String] = []
        switch compose.action {
        case .newMessage:
            lines.append("Action: New message")
        case .reply:
            lines.append("Action: Reply")
        case .replyAll:
            lines.append("Action: Reply all")
        case .forward:
            lines.append("Action: Forward")
        @unknown default:
            lines.append("Action: Unknown")
        }

        if let original {
            lines.append("Original subject: \(original.subject)")
            lines.append("Original from: \(emailString(original.fromAddress))")
            if let body = decodedBodySnippet(from: original.rawData) {
                lines.append("Original thread:\n\(body)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func decodedBodySnippet(from rawData: Data?) -> String? {
        guard let rawData else { return nil }
        let text = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .isoLatin1)
        guard let text else { return nil }
        return String(text.prefix(6000))
    }

    private func emailString(_ address: MEEmailAddress) -> String {
        address.addressString ?? address.rawString
    }
}
