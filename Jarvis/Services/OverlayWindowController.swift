import SwiftUI
import AppKit

final class OverlayWindowController: NSWindowController {
    private static let frameDefaultsKey = "com.jarvis.overlay.frame"
    private let hostingController: NSHostingController<AnyView>

    init<Content: View>(rootView: Content) {
        hostingController = NSHostingController(rootView: AnyView(rootView))
        let panel = NSPanel(contentViewController: hostingController)
        panel.styleMask = [.nonactivatingPanel, .fullSizeContentView, .titled]
        panel.isFloatingPanel = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        window?.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        guard let window else { return }
        if let frameString = UserDefaults.standard.string(forKey: Self.frameDefaultsKey), let frame = NSCoder.cgRect(for: frameString) {
            window.setFrame(frame, display: true)
        } else if let screen = screenForCursor() {
            let size = NSSize(width: min(700, screen.frame.width * 0.5), height: min(600, screen.frame.height * 0.6))
            let origin = NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        guard let window else { return }
        UserDefaults.standard.set(NSCoder.string(for: window.frame), forKey: Self.frameDefaultsKey)
        window.orderOut(nil)
    }

    private func screenForCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSPointInRect(mouse, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}
