import AppKit
import Carbon.HIToolbox

final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        let hotKeyID = EventHotKeyID(signature: OSType(0x42544D52) /* 'BTMR' */, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().handler()
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &eventHandler)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }
    deinit { unregister() }
}
