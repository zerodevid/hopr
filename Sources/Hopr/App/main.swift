import Cocoa
import ApplicationServices

// Diagnostic: dump AX tree (container nodes) + scroll areas the real detector finds.
// Usage: swift run Hopr --ax-dump [bundleID]   (default: com.google.Chrome)
if CommandLine.arguments.contains("--ax-dump") {
    AXDump.run()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Run in background, no dock icon initially

let delegate = AppDelegate()
app.delegate = delegate
app.run()

enum AXDump {
    static func axPoint(_ r: CFTypeRef?) -> CGPoint? {
        guard let r else { return nil }; var p = CGPoint.zero
        return AXValueGetValue(unsafeBitCast(r, to: AXValue.self), .cgPoint, &p) ? p : nil
    }
    static func axSize(_ r: CFTypeRef?) -> CGSize? {
        guard let r else { return nil }; var s = CGSize.zero
        return AXValueGetValue(unsafeBitCast(r, to: AXValue.self), .cgSize, &s) ? s : nil
    }
    static func attr(_ el: AXUIElement, _ n: String) -> CFTypeRef? {
        var r: CFTypeRef?; return AXUIElementCopyAttributeValue(el, n as CFString, &r) == .success ? r : nil
    }
    static func children(_ el: AXUIElement) -> [AXUIElement] {
        if let n = attr(el, "AXChildrenInNavigationOrder") as? [AXUIElement], !n.isEmpty { return n }
        return (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    static func run() {
        let bundleID = CommandLine.arguments.last.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "com.google.Chrome"
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            print("No running app with bundle id \(bundleID)"); return
        }
        let appEl = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, true as CFTypeRef)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
        Thread.sleep(forTimeInterval: 0.8)

        var windows: [AXUIElement] = []
        if let w = attr(appEl, "AXFrontmostWindow") { windows = [unsafeBitCast(w, to: AXUIElement.self)] }
        else if let m = attr(appEl, kAXMainWindowAttribute as String) { windows = [unsafeBitCast(m, to: AXUIElement.self)] }
        else if let ws = attr(appEl, kAXWindowsAttribute as String) as? [AXUIElement] { windows = ws }

        let containerRoles: Set<String> = ["AXGroup","AXScrollArea","AXWebArea","AXList","AXTable","AXOutline","AXGenericElement","AXSplitGroup"]
        var printed = 0
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth < 45, printed < 200 else { return }
            let role = (attr(el, kAXRoleAttribute as String) as? String) ?? "?"
            let size = axSize(attr(el, kAXSizeAttribute as String)) ?? .zero
            let pos = axPoint(attr(el, kAXPositionAttribute as String)) ?? .zero
            // Only print sizeable container nodes (skip tiny leaves/noise).
            if containerRoles.contains(role), size.width > 60, size.height > 150 {
                print("\(String(repeating: "  ", count: min(depth, 22)))\(role) \(Int(size.width))×\(Int(size.height))@(\(Int(pos.x)),\(Int(pos.y)))")
                printed += 1
            }
            for c in children(el) { walk(c, depth + 1) }
        }
        print("=== \(bundleID) tree (container nodes >60×150) ===")
        for w in windows { walk(w, 0) }

        print("\n=== getAllScrollAreas(for:) — numbered left-to-right ===")
        // Time a cold scan and a warm (cached) scan.
        let t0 = CACurrentMediaTime()
        let detected = AccessibilityService.shared.getAllScrollAreas(for: running).sorted { a, b in
            if abs(a.frame.minX - b.frame.minX) > 30 { return a.frame.minX < b.frame.minX }
            return a.frame.minY < b.frame.minY
        }
        let cold = (CACurrentMediaTime() - t0) * 1000
        let t1 = CACurrentMediaTime()
        _ = AccessibilityService.shared.getAllScrollAreas(for: running)
        let warm = (CACurrentMediaTime() - t1) * 1000
        print(String(format: "cold scan: %.1f ms   warm (cached): %.2f ms", cold, warm))
        print("detected \(detected.count) scroll areas:")
        for (i, a) in detected.enumerated() {
            print("  #\(i + 1): \(Int(a.frame.width))×\(Int(a.frame.height))@(\(Int(a.frame.origin.x)),\(Int(a.frame.origin.y)))")
        }
    }
}
