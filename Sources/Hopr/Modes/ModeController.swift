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

/// Protocol that all modes must conform to.
protocol Mode: AnyObject {
    func activate()
    func deactivate()
    func handleKeyPress(_ key: String, keyCode: UInt16, isRepeat: Bool, modifiers: KeyModifiers) -> Bool
    func handleKeyUp(_ key: String, keyCode: UInt16)
    func handleShiftKeyChanged(isPressed: Bool)
    func handleFnKeyChanged(isPressed: Bool)
}

extension Mode {
    func handleShiftKeyChanged(isPressed: Bool) {}
    func handleFnKeyChanged(isPressed: Bool) {}
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
    private var modes: [AppMode: Mode] = [:]

    var onModeChange: ((AppMode) -> Void)?

    func registerMode(_ mode: Mode, for appMode: AppMode) {
        modes[appMode] = mode
    }

    func activateHintMode() {
        activate(.hint)
    }

    func activateScrollMode() {
        activate(.scroll)
    }

    func activateSearchMode() {
        activate(.search)
    }

    func activateMouseMode() {
        activate(.mouse)
    }

    private func activate(_ mode: AppMode) {
        if currentMode != .idle {
            deactivateCurrentMode()
        }
        guard !isCurrentAppIgnored() else {
            Log.info("\(mode) mode blocked: app is in ignored list")
            return
        }
        currentMode = mode
        Log.info("Entered \(mode) mode")
        onModeChange?(mode)
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

    func handleKeyUp(_ key: String, keyCode: UInt16) {
        modes[currentMode]?.handleKeyUp(key, keyCode: keyCode)
    }

    func handleShiftKeyChanged(isPressed: Bool) {
        modes[currentMode]?.handleShiftKeyChanged(isPressed: isPressed)
    }

    func handleFnKeyChanged(isPressed: Bool) {
        modes[currentMode]?.handleFnKeyChanged(isPressed: isPressed)
    }

    func handleKeyPress(_ key: String, keyCode: UInt16, isRepeat: Bool, modifiers: KeyModifiers) -> Bool {
        guard let mode = modes[currentMode] else { return false }
        return mode.handleKeyPress(key, keyCode: keyCode, isRepeat: isRepeat, modifiers: modifiers)
    }
}
