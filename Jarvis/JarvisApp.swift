import SwiftUI
import AppKit
import Combine

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.environment.settingsViewModel)
                .environmentObject(appDelegate.environment.notificationViewModel)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        setupOverlay()
        PermissionsManager.shared.prepare()
        environment.startServices()
        environment.commandPaletteViewModel.$shouldShowOverlay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self else { return }
                if isVisible {
                    NSApp.setActivationPolicy(.regular)
                    self.overlayController?.show()
                } else {
                    self.overlayController?.hide()
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.commandPaletteViewModel.showOverlay()
        return true
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        handleIncomingURL(url)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "Jarvis")
        statusItem.button?.action = #selector(toggleOverlay)
        statusItem.button?.target = self
        statusItem.menu = makeMenu()
        self.statusItem = statusItem
        environment.hotKeyCenter.registerCommandJ { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay()
            }
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
        overlayController?.onClose = { [weak self] in
            guard let self else { return }
            if self.environment.commandPaletteViewModel.shouldShowOverlay {
                self.environment.commandPaletteViewModel.hideOverlay()
            }
        }
    }

    @MainActor
    @objc private func toggleOverlay() {
        if environment.commandPaletteViewModel.shouldShowOverlay {
            environment.commandPaletteViewModel.hideOverlay()
        } else {
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

    @MainActor
    @objc private func openDiagnostics() {
        environment.commandPaletteViewModel.selectTab(.diagnostics)
        environment.commandPaletteViewModel.showOverlay()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "jarvis" else { return }
        let host = url.host?.lowercased()
        let target = ((host?.isEmpty == false) ? host : nil) ?? url.path.replacingOccurrences(of: "/", with: "").lowercased()
        guard target == "mail-compose" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryMap = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let splitEmails: (String?) -> [String] = { raw in
            guard let raw else { return [] }
            return raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        environment.emailDraftViewModel.loadMailContext(
            subject: queryMap["subject"],
            to: splitEmails(queryMap["to"]),
            cc: splitEmails(queryMap["cc"]),
            bcc: splitEmails(queryMap["bcc"]),
            thread: queryMap["thread"]
        )
        environment.commandPaletteViewModel.selectTab(.email)
        environment.commandPaletteViewModel.showOverlay()
        if queryMap["autoDraft"] == "1" {
            environment.emailDraftViewModel.draftReply()
        }
    }
}
