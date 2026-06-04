import Cocoa
import ApplicationServices

// Find Antigravity IDE / VS Code by bundle ID (not by frontmost — terminal steals focus)
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier?.hasPrefix("com.google.antigravity-ide") == true ||
    $0.bundleIdentifier?.hasPrefix("com.microsoft.VSCode") == true ||
    $0.localizedName?.lowercased().contains("antigravity") == true ||
    $0.localizedName?.lowercased().contains("vscode") == true
}) else {
    print("VSCode/Antigravity not found. Running apps:")
    for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular {
        print("  \(a.localizedName ?? "?") — \(a.bundleIdentifier ?? "?")")
    }
    exit(1)
}

let electronPrefixes = ["com.microsoft.VSCode", "com.google.antigravity-ide", "com.todesktop", "com.electron."]
let isElectron: Bool = {
    if let bundle = app.bundleIdentifier {
        return electronPrefixes.contains(where: { bundle.hasPrefix($0) })
    }
    return true
}()

print("App: \(app.localizedName ?? "?") PID: \(app.processIdentifier)")
print("Bundle: \(app.bundleIdentifier ?? "?")")
print("Is Electron: \(isElectron)")

let appElement = AXUIElementCreateApplication(app.processIdentifier)

if isElectron {
    AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
    print("Set AXManualAccessibility")
} else {
    AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
    print("Set AXEnhancedUserInterface")
}

// Get windows
var windowsRef: CFTypeRef?
let winResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
print("AXWindows result: \(winResult.rawValue)")
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
    let windowFrame = CGRect(origin: point, size: size)

    print("\nWindow \(i): \"\(title)\" [\(Int(point.x)),\(Int(point.y)) \(Int(size.width))x\(Int(size.height))]")

    // Simulate findElectronScrollPanels
    var panels: [(String, CGRect, Int)] = []
    findPanels(in: window, windowFrame: windowFrame, depth: 0, results: &panels)

    print("  Found \(panels.count) panels:")
    for (info, _, depth) in panels {
        print("    [depth \(depth)] \(info)")
    }

    // Also dump first 3 levels to see structure
    print("\n  --- Tree structure (first window only, max depth 18) ---")
    if i == 0 {
        dumpTree(element: window, depth: 0, maxDepth: 18, prefix: "  ")
    }
}

// MARK: - Helpers

func findPanels(in element: AXUIElement, windowFrame: CGRect, depth: Int, results: inout [(String, CGRect, Int)]) {
    guard depth < 20 else { return }

    var roleRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
          let role = roleRef as? String else { return }

    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
    var point = CGPoint.zero
    var size = CGSize.zero
    if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &point) }
    if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }
    let frame = CGRect(origin: point, size: size)

    let panelRoles: Set<String> = ["AXGroup", "AXScrollArea", "AXTextArea", "AXWebArea", "AXList", "AXTable", "AXOutline"]

    let widthSmaller = size.width < windowFrame.width * 0.95
    let heightSmaller = size.height < windowFrame.height * 0.85
    let isPanel = panelRoles.contains(role)
        && size.width > 80 && size.height > 80
        && (widthSmaller || heightSmaller)

    if isPanel {
        let info = "\(role) [\(Int(point.x)),\(Int(point.y)) \(Int(size.width))x\(Int(size.height))] w<95%=\(widthSmaller) h<85%=\(heightSmaller)"
        results.append((info, frame, depth))
        return
    }

    var childrenRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &childrenRef) != .success {
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    }
    guard let children = childrenRef as? [AXUIElement] else { return }

    for child in children {
        findPanels(in: child, windowFrame: windowFrame, depth: depth + 1, results: &results)
    }
}

func dumpTree(element: AXUIElement, depth: Int, maxDepth: Int, prefix: String) {
    guard depth < maxDepth else { return }

    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    let role = roleRef as? String ?? "?"

    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
    var point = CGPoint.zero
    var size = CGSize.zero
    if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &point) }
    if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }

    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    let title = titleRef as? String

    var subroleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
    let subrole = subroleRef as? String

    var line = "\(prefix)\(role) [\(Int(point.x)),\(Int(point.y)) \(Int(size.width))x\(Int(size.height))]"
    if let title, !title.isEmpty { line += " \"\(String(title.prefix(50)))\"" }
    if let subrole { line += " (\(subrole))" }

    // Only print elements with reasonable size (skip tiny/zero elements) unless shallow
    if size.width > 5 || size.height > 5 || depth < 3 {
        print(line)
    }

    var childrenRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &childrenRef) != .success {
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    }
    guard let children = childrenRef as? [AXUIElement] else { return }

    let maxChildren = depth < 8 ? 30 : 10
    for child in children.prefix(maxChildren) {
        dumpTree(element: child, depth: depth + 1, maxDepth: maxDepth, prefix: prefix + "  ")
    }
    if children.count > maxChildren {
        print("\(prefix)  ... (\(children.count - maxChildren) more children)")
    }
}
