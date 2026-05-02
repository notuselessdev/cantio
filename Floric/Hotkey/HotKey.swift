import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut consisting of a virtual key code and Carbon modifier
/// flags. Stored in `Preferences` and registered with the system via
/// `HotKeyManager`.
struct HotKey: Equatable {
    /// Virtual key code (e.g. `kVK_ANSI_L`).
    var keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    var modifiers: UInt32

    /// Default toggle: ⌥⌘L.
    static let defaultToggle = HotKey(
        keyCode: UInt32(kVK_ANSI_L),
        modifiers: UInt32(cmdKey | optionKey)
    )

    /// Build from a SwiftUI/NSEvent modifier set + keyCode.
    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: UInt16, eventModifiers: NSEvent.ModifierFlags) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = HotKey.carbonModifiers(from: eventModifiers)
    }

    /// Convert `NSEvent.ModifierFlags` (device-independent) to Carbon flags.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        return result
    }

    /// Human-readable display, e.g. "⌥⌘L".
    var displayString: String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { parts += "⌘" }
        parts += HotKey.keyName(for: keyCode)
        return parts
    }

    /// Best-effort symbolic name for a virtual key code.
    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Return:        return "↩"
        case kVK_Tab:           return "⇥"
        case kVK_Space:         return "Space"
        case kVK_Delete:        return "⌫"
        case kVK_Escape:        return "⎋"
        case kVK_LeftArrow:     return "←"
        case kVK_RightArrow:    return "→"
        case kVK_DownArrow:     return "↓"
        case kVK_UpArrow:       return "↑"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: break
        }

        guard let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayoutPtr = CFDataGetBytePtr(dataRef)
        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(keyLayoutPtr))

        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var actualLength: Int = 0
        var unicodeString = [UniChar](repeating: 0, count: maxLength)
        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &actualLength,
            &unicodeString
        )
        if status == noErr, actualLength > 0 {
            return String(utf16CodeUnits: unicodeString, count: actualLength).uppercased()
        }
        return "?"
    }
}
