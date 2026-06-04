import Cocoa
import ApplicationServices

// Find VSCode process
guard let vscode = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName?.lowercased().contains("antigravity") == true ||
    $0.localizedName?.lowercased().contains("vscode") == true ||
    $0.localizedName?.lowercased().contains("visual studio") == true
}) else {
    print("VSCode not found. Running apps:")
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        print("  \(app.localizedName ?? "?") — \(app.bundleIdentifier ?? "?")")
    }
    exit(1)
}

print("Found: \(vscode.localizedName ?? "?") PID: \(vscode.processIdentifier)")

let appElement = AXUIElementCreateApplication(vscode.processIdentifier)

func dump(element: AXUIElement, depth: Int, maxDepth: Int) {
    guard depth < maxDepth else { return }

    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    let role = roleRef as? String ?? "?"

    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    let title = titleRef as? String

    var valueRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)

    // Check for scroll-related attributes
    var scrollAttrs: [String] = []
    for attr in ["AXHasScrollBar", "AXScrollVisible", "AXIsScrollable", "AXOverflow"] {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success {
            scrollAttrs.append("\(attr)=\(ref!)")
        }
    }

    // Get frame
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
    var point = CGPoint.zero
    var size = CGSize.zero
    if let posVal = posRef { AXValueGetValue(posVal as! AXValue, .cgPoint, &point) }
    if let sizeVal = sizeRef { AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) }

    let indent = String(repeating: "  ", count: depth)
    var line = "\(indent)\(role)"
    if let t = title, !t.isEmpty { line += " \"\(t)\"" }
    line += " [\(Int(point.x)),\(Int(point.y)) \(Int(size.width))x\(Int(size.height))]"
    if !scrollAttrs.isEmpty { line += " SCROLL: \(scrollAttrs.joined(separator: ", "))" }

    // Only print interesting elements
    if role.contains("Scroll") || role.contains("Group") || role.contains("Area") ||
       role.contains("Text") || role.contains("Web") || !scrollAttrs.isEmpty ||
       (size.width > 200 && size.height > 200) {
        print(line)
    }

    var childrenRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return }

    for child in children {
        dump(element: child, depth: depth + 1, maxDepth: maxDepth)
    }
}

print("\n--- VSCode AX Tree (scrollable/large elements) ---")
dump(element: appElement, depth: 0, maxDepth: 8)
