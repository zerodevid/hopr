import Cocoa

enum AppMode {
    case idle
    case hint
    case scroll
    case search
    case mouse
}

struct KeyModifiers {
    let shift: Bool
    let command: Bool
    let control: Bool
    let option: Bool

    static let none = KeyModifiers(shift: false, command: false, control: false, option: false)
}

protocol ModeDelegate: AnyObject {
    var currentMode: AppMode { get }
    func activateHintMode()
    func activateScrollMode()
    func activateSearchMode()
    func activateMouseMode()
    func deactivateCurrentMode()
    func handleKeyPress(_ key: String, keyCode: UInt16, isRepeat: Bool, modifiers: KeyModifiers) -> Bool
    func handleKeyUp(_ key: String, keyCode: UInt16)
    func handleShiftKeyChanged(isPressed: Bool)
    func handleFnKeyChanged(isPressed: Bool)
}

final class ModeController: ModeDelegate {

    private(set) var currentMode: AppMode = .idle

    var onModeChange: ((AppMode) -> Void)?
    var onHintKeyPress: ((String, UInt16, Bool, KeyModifiers) -> Bool)?
    var onHintKeyUp: ((String, UInt16) -> Void)?
    var onHintShiftKeyChanged: ((Bool) -> Void)?
    var onHintFnKeyChanged: ((Bool) -> Void)?
    var onScrollKeyPress: ((UInt16, Bool) -> Bool)?
    var onScrollKeyUp: ((UInt16) -> Void)?
    var onSearchKeyPress: ((String, UInt16, Bool) -> Bool)?
    var onMouseKeyPress: ((String, UInt16, Bool, KeyModifiers) -> Bool)?
    var onMouseKeyUp: ((UInt16) -> Void)?

    func activateHintMode() {
        if currentMode != .idle {
            deactivateCurrentMode()
        }
        guard !isCurrentAppIgnored() else {
            Log.info("Hint mode blocked: app is in ignored list")
            return
        }
        currentMode = .hint
        Log.info("Entered hint mode")
        onModeChange?(.hint)
    }

    func activateScrollMode() {
        if currentMode != .idle {
            deactivateCurrentMode()
        }
        guard !isCurrentAppIgnored() else {
            Log.info("Scroll mode blocked: app is in ignored list")
            return
        }
        currentMode = .scroll
        Log.info("Entered scroll mode")
        onModeChange?(.scroll)
    }

    func activateSearchMode() {
        if currentMode != .idle {
            deactivateCurrentMode()
        }
        guard !isCurrentAppIgnored() else {
            Log.info("Search mode blocked: app is in ignored list")
            return
        }
        currentMode = .search
        Log.info("Entered search mode")
        onModeChange?(.search)
    }

    func activateMouseMode() {
        if currentMode != .idle {
            deactivateCurrentMode()
        }
        guard !isCurrentAppIgnored() else {
            Log.info("Mouse mode blocked: app is in ignored list")
            return
        }
        currentMode = .mouse
        Log.info("Entered mouse mode")
        onModeChange?(.mouse)
    }

    private func isCurrentAppIgnored() -> Bool {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return AppSettings.shared.isAppIgnored(bundleID)
    }

    func deactivateCurrentMode() {
        let prev = currentMode
        currentMode = .idle
        Log.info("Exited \(prev) mode")
        onModeChange?(.idle)
    }

    /// Handle key up events
    func handleKeyUp(_ key: String, keyCode: UInt16) {
        switch currentMode {
        case .scroll:
            onScrollKeyUp?(keyCode)
        case .hint:
            onHintKeyUp?(key, keyCode)
        case .mouse:
            onMouseKeyUp?(keyCode)
        default:
            break
        }
    }

    func handleShiftKeyChanged(isPressed: Bool) {
        if currentMode == .hint {
            onHintShiftKeyChanged?(isPressed)
        }
    }

    func handleFnKeyChanged(isPressed: Bool) {
        if currentMode == .hint {
            onHintFnKeyChanged?(isPressed)
        }
    }

    /// Returns true if the key was consumed (should suppress the event)
    func handleKeyPress(_ key: String, keyCode: UInt16, isRepeat: Bool, modifiers: KeyModifiers) -> Bool {
        switch currentMode {
        case .idle:
            return false
        case .hint:
            return onHintKeyPress?(key, keyCode, isRepeat, modifiers) ?? false
        case .scroll:
            return onScrollKeyPress?(keyCode, isRepeat) ?? false
        case .search:
            return onSearchKeyPress?(key, keyCode, isRepeat) ?? false
        case .mouse:
            return onMouseKeyPress?(key, keyCode, isRepeat, modifiers) ?? false
        }
    }
}
