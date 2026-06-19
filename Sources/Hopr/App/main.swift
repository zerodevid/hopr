import Cocoa
import ApplicationServices

// Diagnostic: print scroll areas the real detector finds for an app.
// Usage: swift run Hopr --ax-dump [bundleID]   (default: com.google.Chrome)
if CommandLine.arguments.contains("--ax-dump") {
    let bundleID = CommandLine.arguments.last.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "com.google.Chrome"
    guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
        print("No running app with bundle id \(bundleID)"); exit(0)
    }
    let appEl = AXUIElementCreateApplication(running.processIdentifier)
    AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, true as CFTypeRef)
    AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
    Thread.sleep(forTimeInterval: 0.8)
    let detected = AccessibilityService.shared.getAllScrollAreas(for: running)
    print("\(bundleID): detected \(detected.count) scroll areas:")
    for (i, a) in detected.enumerated() {
        print("  #\(i + 1): \(Int(a.frame.width))×\(Int(a.frame.height))@(\(Int(a.frame.origin.x)),\(Int(a.frame.origin.y)))")
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Run in background, no dock icon initially

let delegate = AppDelegate()
app.delegate = delegate
app.run()
