import Carbon
import AppKit

/// Registers a global keyboard shortcut (⌃⌥Space) via the Carbon hotkey API —
/// works without accessibility permissions.
final class HotKeyManager {
    var onPress: () -> Void = {}

    private var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?

    /// keyCode/modifiers in Carbon terms. Default: Ctrl+Option+Space.
    func register(keyCode: UInt32 = UInt32(kVK_Space),
                  modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, ctx -> OSStatus in
                guard let ctx else { return OSStatus(noErr) }
                Unmanaged<HotKeyManager>.fromOpaque(ctx)
                    .takeUnretainedValue().onPress()
                return OSStatus(noErr)
            },
            1, &spec, selfPtr, &HotKeyManager.handlerRef
        )

        // 'MSWC'
        let id = EventHotKeyID(signature: OSType(bitPattern: 0x4D535743), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
