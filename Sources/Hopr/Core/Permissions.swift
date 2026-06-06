import Cocoa
import ApplicationServices

enum Permissions {

    /// Check if accessibility permissions are granted
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant accessibility permissions
    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Check and prompt if needed, returns true if already granted
    static func ensureAccessibility() -> Bool {
        if isAccessibilityGranted() {
            return true 
        }
        promptForAccessibility()
        return false
    }
}
