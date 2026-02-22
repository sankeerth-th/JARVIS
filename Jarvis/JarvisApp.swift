import SwiftUI
import AppKit
import Combine

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.environment)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        configureStatusItem()
        setupOverlay()
        PermissionsManager.shared.prepare()
        environment.startServices()
        environment.commandPaletteViewModel.$shouldShowOverlay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self else { return }
                if isVisible {
                    self.overlayController?.show()
                } else {
                    self.overlayController?.hide()
                }
            }
            .store(in: &cancellables)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.commandPaletteViewModel.showOverlay()
        return true
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "Jarvis")
        statusItem.button?.action = #selector(toggleOverlay)
        statusItem.button?.target = self
        statusItem.menu = makeMenu()
        self.statusItem = statusItem
        environment.hotKeyCenter.registerCommandJ { [weak self] in
            self?.toggleOverlay()
        }
    }

    private func setupOverlay() {
        let rootView = CommandPaletteView()
            .environmentObject(environment.commandPaletteViewModel)
            .environmentObject(environment.notificationViewModel)
            .environmentObject(environment.emailDraftViewModel)
            .environmentObject(environment.diagnosticsViewModel)
            .environmentObject(environment.settingsViewModel)
        overlayController = OverlayWindowController(rootView: rootView)
    }

    @objc private func toggleOverlay() {
        if overlayController?.isVisible == true {
            overlayController?.hide()
            environment.commandPaletteViewModel.hideOverlay()
        } else {
            overlayController?.show()
            environment.commandPaletteViewModel.showOverlay()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Jarvis", action: #selector(toggleOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Diagnostics", action: #selector(openDiagnostics), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Jarvis", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    @objc private func openDiagnostics() {
        environment.commandPaletteViewModel.selectTab(.diagnostics)
        overlayController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
