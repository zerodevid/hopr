import Cocoa
import ApplicationServices

// Find VSCode / Antigravity IDE
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName?.lowercased().contains("antigravity") == true ||
    $0.localizedName?.lowercased().contains("vscode") == true ||
    $0.localizedName?.lowercased().contains("visual studio") == true
}) else {
    print("VSCode not found. Available apps:")
    for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular {
        print("  \(a.localizedName ?? "?") — \(a.bundleIdentifier ?? "?")")
    }
    exit(1)
}

print("App: \(app.localizedName ?? "?") PID: \(app.processIdentifier)")
let appElement = AXUIElementCreateApplication(app.processIdentifier)

// Get ALL windows
var windowsRef: CFTypeRef?
AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
let windows = windowsRef as? [AXUIElement] ?? []
print("\n=== WINDOWS: \(windows.count) ===")

for (i, window) in windows.enumerated() {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

    var point = CGPoint.zero
    var size = CGSize.zero
    if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &point) }
    if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }
    let title = titleRef as? String ?? "?"

    print("\nWindow \(i): \"\(title)\" [\(Int(point.x)),\(Int(point.y)) \(Int(size.width))x\(Int(size.height))]")
}

// Method 1: Check kAXWindowsAttribute children (panels, groups)
print("\n=== SCROLL DETECTION ===")

func inspectElement(_ element: AXUIElement, depth: Int, maxDepth: Int) -> [(String, CGRect)] {
    guard depth < maxDepth else { return [] }
    var results: [(String, CGRect)] = []

    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    let role = roleRef as? String ?? ""

    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
    var point = CGPoint.zero
    var size = CGSize.zero
    if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &point) }
    if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }
    let frame = CGRect(origin: point, size: size)

    // Check scroll indicators
    var hasScroll = false
    for attr in ["AXHasScrollBar", "AXScrollVisible", "AXIsScrollable"] {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success {
            hasScroll = true
        }
    }

    // Check role
    let isScrollRole = role == "AXScrollArea" || role.contains("Scroll")
    let isLargeGroup = role == "AXGroup" && size.width > 100 && size.height > 100

    if isScrollRole || hasScroll || isLargeGroup {
        var info = "\(role) [\(Int(point.x)),\(Int(point.y)) \(Int(size.width))x\(Int(size.height))]"
        if hasScroll { info += " SCROLL_ATTRS" }
        results.append((info, frame))
    }

    // Recurse children
    var childrenRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
       let children = childrenRef as? [AXUIElement] {
        for child in children {
            results.append(contentsOf: inspectElement(child, depth: depth + 1, maxDepth: maxDepth))
        }
    }

    return results
}

// Check each window's children
for (i, window) in windows.enumerated() {
    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
    let title = titleRef as? String ?? "?"

    let results = inspectElement(window, depth: 0, maxDepth: 8)
    print("\nWindow \(i) \"\(title)\": \(results.count) potential scroll areas")
    for (info, _) in results {
        print("  \(info)")
    }
}

// Also check NSWindow frames for comparison
print("\n=== NSApplication WINDOWS ===")
for (i, nsWindow) in NSApplication.shared.windows.enumerated() where nsWindow.isVisible {
    let f = nsWindow.frame
    print("Window \(i): \"\(nsWindow.title)\" [\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height))]")
}
