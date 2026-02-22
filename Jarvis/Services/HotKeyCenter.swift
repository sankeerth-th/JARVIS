import Foundation
import Carbon

final class HotKeyCenter {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    func registerCommandJ(_ handler: @escaping () -> Void) {
        register(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey), handler: handler)
    }

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister()
        self.handler = handler
        var hotKeyID = EventHotKeyID(signature: OSType("JARS".fourCharCodeValue), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let hotKeyCenter = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            hotKeyCenter.handler?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        handler = nil
    }

    deinit {
        unregister()
    }
}

private extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for character in utf16.prefix(4) {
            result = (result << 8) + FourCharCode(character)
        }
        return result
    }
}
