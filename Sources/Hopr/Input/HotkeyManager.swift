import Cocoa
import Carbon.HIToolbox

final class HotkeyManager {

    private var eventTap: CFMachPort?
    private var unmanagedSelf: Unmanaged<HotkeyManager>?
    private weak var modeController: ModeDelegate?

    init(modeController: ModeDelegate) {
        self.modeController = modeController
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        // We need to pass self to the callback via Unmanaged
        let unmanagedManager = Unmanaged.passRetained(self)
        let selfPtr = unmanagedManager.toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            Log.error("Failed to create event tap. Check accessibility permissions.")
            unmanagedManager.release()
            return false
        }

        self.eventTap = tap
        self.unmanagedSelf = unmanagedManager

        // Enable the tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.info("HotkeyManager started")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let unmanaged = unmanagedSelf {
            unmanaged.release()
            unmanagedSelf = nil
        }
    }

    // MARK: - Event Handling

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it gets disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == 56 || keyCode == 60 { // Left Shift (56) or Right Shift (60)
                let isShiftPressed = event.flags.contains(.maskShift)
                modeController?.handleShiftKeyChanged(isPressed: isShiftPressed)
            } else if keyCode == 63 { // Fn key (63)
                let isFnPressed = event.flags.contains(.maskSecondaryFn)
                modeController?.handleFnKeyChanged(isPressed: isFnPressed)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // Handle key up
        if type == .keyUp {
            let keyCodeUp = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let charUp = characterFromKeyCode(keyCodeUp, shift: event.flags.contains(.maskShift))
            modeController?.handleKeyUp(charUp, keyCode: keyCodeUp)
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let shiftPressed = flags.contains(.maskShift)
        let ctrlPressed = flags.contains(.maskControl)
        let cmdPressed = flags.contains(.maskCommand)
        let optionPressed = flags.contains(.maskAlternate)

        let settings = AppSettings.shared

        // Match Hint Shortcut
        if eventMatchesKeyCombo(event, combo: settings.hintShortcut) {
            if isScreenCaptureActive() {
                return Unmanaged.passUnretained(event)
            }
            if modeController?.currentMode == .hint {
                modeController?.deactivateCurrentMode()
            } else {
                modeController?.activateHintMode()
            }
            return nil
        }

        // Match Scroll Shortcut
        if eventMatchesKeyCombo(event, combo: settings.scrollShortcut) {
            if modeController?.currentMode == .scroll {
                modeController?.deactivateCurrentMode()
            } else {
                modeController?.activateScrollMode()
            }
            return nil
        }

        // Match Mouse Shortcut
        if eventMatchesKeyCombo(event, combo: settings.mouseShortcut) {
            if modeController?.currentMode == .mouse {
                modeController?.deactivateCurrentMode()
            } else {
                modeController?.activateMouseMode()
            }
            return nil
        }

        // Match Search Shortcut
        if eventMatchesKeyCombo(event, combo: settings.searchShortcut) {
            if modeController?.currentMode == .search {
                modeController?.deactivateCurrentMode()
            } else {
                modeController?.activateSearchMode()
            }
            return nil
        }

        // Match Focus Text Shortcut
        if eventMatchesKeyCombo(event, combo: settings.focusTextShortcut) {
            if modeController?.currentMode == .focusText {
                modeController?.deactivateCurrentMode()
            } else {
                modeController?.activateFocusTextMode()
            }
            return nil
        }

        // If in idle mode, we don't handle any other shortcuts, just pass them through
        if modeController?.currentMode == .idle {
            return Unmanaged.passUnretained(event)
        }

        // Pass through any events with Command or Control modifiers to let system/app shortcuts (like Cmd+Shift+4) work
        if cmdPressed || ctrlPressed {
            return Unmanaged.passUnretained(event)
        }

        // Escape → back to idle
        if keyCode == kVK_Escape {
            modeController?.deactivateCurrentMode()
            return nil
        }

        // Route to active mode
        let char = characterFromKeyCode(keyCode, shift: shiftPressed)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let modifiers = KeyModifiers(shift: shiftPressed, command: cmdPressed,
                                     control: ctrlPressed, option: optionPressed)
        let consumed = modeController?.handleKeyPress(char, keyCode: keyCode, isRepeat: isRepeat, modifiers: modifiers) ?? false
        return consumed ? nil : Unmanaged.passUnretained(event)
    }

    private func characterFromKeyCode(_ keyCode: UInt16, shift: Bool) -> String {
        // Try dynamic translation using UCKeyTranslate (handles all keyboard layouts, symbols, numbers, shift, etc.)
        if let keyboardSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
            let layoutData = TISGetInputSourceProperty(keyboardSource, kTISPropertyUnicodeKeyLayoutData)
            let layoutDataRef = unsafeBitCast(layoutData, to: CFData.self)
            let layoutDataPointer = CFDataGetBytePtr(layoutDataRef)
            
            var keysDown: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var actualLength = 0
            
            let modifierState = shift ? (0x0200 >> 8) : 0 // shiftKey >> 8
            
            let result = UCKeyTranslate(
                unsafeBitCast(layoutDataPointer, to: UnsafePointer<UCKeyboardLayout>.self),
                keyCode,
                UInt16(kUCKeyActionDown),
                UInt32(modifierState),
                0, // Default keyboard type
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &keysDown,
                4,
                &actualLength,
                &chars
            )
            
            if result == noErr && actualLength > 0 {
                return String(utf16CodeUnits: chars, count: actualLength)
            }
        }

        // Fallback: Map common key codes to characters
        let keyMap: [(Int, String, String)] = [
            (kVK_ANSI_A, "a", "A"), (kVK_ANSI_B, "b", "B"), (kVK_ANSI_C, "c", "C"),
            (kVK_ANSI_D, "d", "D"), (kVK_ANSI_E, "e", "E"), (kVK_ANSI_F, "f", "F"),
            (kVK_ANSI_G, "g", "G"), (kVK_ANSI_H, "h", "H"), (kVK_ANSI_I, "i", "I"),
            (kVK_ANSI_J, "j", "J"), (kVK_ANSI_K, "k", "K"), (kVK_ANSI_L, "l", "L"),
            (kVK_ANSI_M, "m", "M"), (kVK_ANSI_N, "n", "N"), (kVK_ANSI_O, "o", "O"),
            (kVK_ANSI_P, "p", "P"), (kVK_ANSI_Q, "q", "Q"), (kVK_ANSI_R, "r", "R"),
            (kVK_ANSI_S, "s", "S"), (kVK_ANSI_T, "t", "T"), (kVK_ANSI_U, "u", "U"),
            (kVK_ANSI_V, "v", "V"), (kVK_ANSI_W, "w", "W"), (kVK_ANSI_X, "x", "X"),
            (kVK_ANSI_Y, "y", "Y"), (kVK_ANSI_Z, "z", "Z"),
            (kVK_Space, " ", " "),
        ]

        guard let (_, lower, upper) = keyMap.first(where: { $0.0 == Int(keyCode) }) else { return "" }
        return shift ? upper : lower
    }

    private func eventMatchesKeyCombo(_ event: CGEvent, combo: KeyCombo) -> Bool {
        guard combo.keyCode != 0 else { return false }
        
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == combo.keyCode else { return false }
        
        let flags = event.flags
        let comboFlags = combo.modifierFlags
        
        let shiftPressed = flags.contains(.maskShift)
        let ctrlPressed = flags.contains(.maskControl)
        let cmdPressed = flags.contains(.maskCommand)
        let optionPressed = flags.contains(.maskAlternate)
        
        let shiftExpected = comboFlags.contains(.shift)
        let ctrlExpected = comboFlags.contains(.control)
        let cmdExpected = comboFlags.contains(.command)
        let optionExpected = comboFlags.contains(.option)
        
        return shiftPressed == shiftExpected &&
               ctrlPressed == ctrlExpected &&
               cmdPressed == cmdExpected &&
               optionPressed == optionExpected
    }

    private func isScreenCaptureActive() -> Bool {
        let targetBundleIDs: Set<String> = [
            "com.apple.screencapture",
            "com.apple.screencaptureui"
        ]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return targetBundleIDs.contains(bundleID)
        }
    }
}
