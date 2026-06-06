import Cocoa
import Carbon.HIToolbox

public struct KeyCombo: Codable, Equatable {
    public var keyCode: UInt16
    public var modifiers: UInt // RawValue of NSEvent.ModifierFlags

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: modifiers)
    }

    public var displayString: String {
        if keyCode == 0 && modifiers == 0 {
            return "None"
        }
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option) { parts.append("Opt") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Cmd") }

        parts.append(KeyCombo.keyName(keyCode: keyCode))
        return parts.joined(separator: " + ")
    }

    public static func keyName(keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "FwdDelete"
        case kVK_Escape: return "Esc"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_Keypad0: return "Num0"
        case kVK_ANSI_Keypad1: return "Num1"
        case kVK_ANSI_Keypad2: return "Num2"
        case kVK_ANSI_Keypad3: return "Num3"
        case kVK_ANSI_Keypad4: return "Num4"
        case kVK_ANSI_Keypad5: return "Num5"
        case kVK_ANSI_Keypad6: return "Num6"
        case kVK_ANSI_Keypad7: return "Num7"
        case kVK_ANSI_Keypad8: return "Num8"
        case kVK_ANSI_Keypad9: return "Num9"
        default:
            // Dynamic translation based on current keyboard layout
            if let keyboardSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
                let layoutData = TISGetInputSourceProperty(keyboardSource, kTISPropertyUnicodeKeyLayoutData)
                let layoutDataRef = unsafeBitCast(layoutData, to: CFData.self)
                let layoutDataPointer = CFDataGetBytePtr(layoutDataRef)
                
                var keysDown: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var actualLength = 0
                
                let result = UCKeyTranslate(
                    unsafeBitCast(layoutDataPointer, to: UnsafePointer<UCKeyboardLayout>.self),
                    keyCode,
                    UInt16(kUCKeyActionDown),
                    0, // No modifiers for base key name
                    0, // Default keyboard type
                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                    &keysDown,
                    4,
                    &actualLength,
                    &chars
                )
                
                if result == noErr && actualLength > 0 {
                    let keyStr = String(utf16CodeUnits: chars, count: actualLength).uppercased()
                    if !keyStr.isEmpty {
                        return keyStr
                    }
                }
            }
            return "Key \(keyCode)"
        }
    }
}
