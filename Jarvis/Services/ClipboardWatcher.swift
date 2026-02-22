import Foundation
import AppKit

final class ClipboardWatcher {
    private var timer: DispatchSourceTimer?
    private var changeCount: Int = NSPasteboard.general.changeCount
    var onTextChange: ((String) -> Void)?

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.pollClipboard()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func pollClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        if let string = pasteboard.string(forType: .string) {
            onTextChange?(string)
        }
    }
}
