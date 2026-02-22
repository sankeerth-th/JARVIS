import SwiftUI
import AppKit

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    private static let frameDefaultsKey = "com.jarvis.overlay.frame"
    private let hostingController: NSHostingController<AnyView>
    private var escapeEventMonitor: Any?
    private var isHiding = false
    var onClose: (() -> Void)?

    init<Content: View>(rootView: Content) {
        hostingController = NSHostingController(rootView: AnyView(rootView))
        let panel = NSPanel(contentViewController: hostingController)
        panel.styleMask = [.titled, .resizable, .fullSizeContentView]
        panel.isFloatingPanel = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .normal
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.isMovableByWindowBackground = true
        super.init(window: panel)
        panel.delegate = self
        window?.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        guard let window else { return }
        if let screen = screenForCursor() {
            if let frameString = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) {
                let frame = NSRectFromString(frameString)
                if !frame.isEmpty {
                    window.setFrame(validatedFrame(frame, fallbackScreen: screen), display: true)
                } else {
                    window.setFrame(centeredFrame(on: screen), display: true)
                }
            } else {
                window.setFrame(centeredFrame(on: screen), display: true)
            }
        }
        installEscapeMonitorIfNeeded()
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let window, !isHiding else { return }
        let wasVisible = window.isVisible
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameDefaultsKey)
        removeEscapeMonitor()
        isHiding = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.11
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            window.orderOut(nil)
            window.alphaValue = 1
            self.isHiding = false
            if wasVisible {
                self.onClose?()
            }
        })
    }

    private func screenForCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSPointInRect(mouse, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func installEscapeMonitorIfNeeded() {
        guard escapeEventMonitor == nil else { return }
        escapeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeEventMonitor {
            NSEvent.removeMonitor(escapeEventMonitor)
            self.escapeEventMonitor = nil
        }
    }

    private func centeredFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let size = NSSize(width: min(1120, visible.width * 0.82), height: min(760, visible.height * 0.82))
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        return NSRect(origin: origin, size: size)
    }

    private func validatedFrame(_ frame: NSRect, fallbackScreen: NSScreen) -> NSRect {
        let isVisibleOnAnyScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard isVisibleOnAnyScreen else {
            return centeredFrame(on: fallbackScreen)
        }
        return frame
    }
}
