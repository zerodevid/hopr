import Cocoa
import ApplicationServices

// Find Antigravity IDE / VS Code
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier?.hasPrefix("com.google") == true ||
    $0.bundleIdentifier?.hasPrefix("com.microsoft.VSCode") == true
}) else {
    print("VS Code / Antigravity IDE not running")
    exit(1)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)

var windowsRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
      let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
    print("No windows found")
    exit(1)
}

func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let str = value as? String else { return nil }
    return str
}

func getPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return point
}

func getIntAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    var val: Int = 0
    CFNumberGetValue(value as! CFNumber, .intType, &val)
    return val
}

func traverse(element: AXUIElement, depth: Int) {
    guard depth < 25 else { return }
    
    if let role = getStringAttribute(element, kAXRoleAttribute) {
        let title = getStringAttribute(element, kAXTitleAttribute)
            ?? getStringAttribute(element, kAXDescriptionAttribute)
            ?? getStringAttribute(element, kAXValueAttribute)
            ?? ""
        
        let subrole = getStringAttribute(element, kAXSubroleAttribute) ?? ""
        
        // Print tree nodes that contain Swift or md filenames to see their roles/properties
        if title.contains(".swift") || title.contains(".md") || title.contains("decompile") || title.contains("Sources") {
            print(String(repeating: "  ", count: depth) + "- \(role) [Sub: \(subrole)] Title: '\(title)'")
        }
    }
    
    var childrenRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &childrenRef) != .success {
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    }
    if let children = childrenRef as? [AXUIElement] {
        for child in children {
            traverse(element: child, depth: depth + 1)
        }
    }
}

for (i, win) in windows.enumerated() {
    print("Window \(i):")
    traverse(element: win, depth: 0)
}
