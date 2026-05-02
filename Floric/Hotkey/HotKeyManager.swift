import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via the Carbon HotKey API.
///
/// macOS still supports `RegisterEventHotKey` and it requires no
/// entitlements, unlike `CGEvent`-based interception. The handler fires on
/// the main run loop regardless of which app is frontmost.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var current: HotKey?

    /// Closure invoked on the main thread when the hotkey fires.
    var onPress: (() -> Void)?

    private static let signature: OSType = {
        // Four-char code 'FLrc' (Floric).
        let chars: [UInt8] = [0x46, 0x4C, 0x72, 0x63]
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }()
    private static let id: UInt32 = 1

    private init() {}

    /// Replace the registered hotkey. Pass `nil` to unregister.
    func register(_ hotKey: HotKey?) {
        unregister()
        guard let hotKey, hotKey.modifiers != 0 else { return }

        installHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        _ = hotKeyID
        if status == noErr {
            hotKeyRef = ref
            current = hotKey
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return err }
                let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    mgr.onPress?()
                }
                return noErr
            },
            1,
            &spec,
            userData,
            &handlerRef
        )
    }
}
