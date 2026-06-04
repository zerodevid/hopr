import Cocoa
import ApplicationServices

// Copy of minimal Log implementation to avoid compiling too many files
struct Log {
    static func info(_ msg: String) { print("INFO: \(msg)") }
    static func debug(_ msg: String) { print("DEBUG: \(msg)") }
    static func error(_ msg: String) { print("ERROR: \(msg)") }
}

// Copy of UIElement
struct UIElement: Identifiable {
    let id = UUID()
    let element: AXUIElement
    let role: String
    let title: String
    let frame: CGRect
    let enabled: Bool
    var label: String = ""

    static func from(_ element: AXUIElement) -> UIElement? {
        guard let role = getStringAttribute(element, kAXRoleAttribute) else { return nil }
        let title = getStringAttribute(element, kAXTitleAttribute)
            ?? getStringAttribute(element, kAXDescriptionAttribute)
            ?? getStringAttribute(element, kAXValueAttribute)
            ?? ""
        guard let position = getPointAttribute(element, kAXPositionAttribute),
              let size = getSizeAttribute(element, kAXSizeAttribute) else { return nil }
        let frame = CGRect(origin: position, size: size)
        return UIElement(element: element, role: role, title: title, frame: frame, enabled: true)
    }
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

func getSizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return size
}

var allElements: [UIElement] = []

func getFrontmostWindow(from appElement: AXUIElement) -> AXUIElement? {
    var windowRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, "AXFrontmostWindow" as CFString, &windowRef) == .success {
        return (windowRef as! AXUIElement)
    }
    var windowsRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        return windows.first
    }
    return nil
}

func traverse(element: AXUIElement, depth: Int) {
    if depth > 45 { return }
    
    if let uiElement = UIElement.from(element) {
        if shouldInclude(uiElement, element) {
            allElements.append(uiElement)
        }
    }
    
    var childrenRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &childrenRef) != .success {
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    }
    guard let children = childrenRef as? [AXUIElement] else { return }
    for child in children {
        traverse(element: child, depth: depth + 1)
    }
}

func shouldInclude(_ elem: UIElement, _ rawElement: AXUIElement) -> Bool {
    let actionableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuItem", "AXLink",
        "AXTextField", "AXTextArea", "AXComboBox", "AXTab", "AXMenuBarItem", "AXToolbar"
    ]
    if actionableRoles.contains(elem.role) { return true }
    if !elem.title.isEmpty {
        if elem.role == "AXGroup" || elem.role == "AXWebArea" { return false }
        return true
    }
    return false
}

// Target main window of Antigravity IDE (PID 91356)
let appElement = AXUIElementCreateApplication(91356)
AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)

if let window = getFrontmostWindow(from: appElement) {
    print("Found frontmost window, traversing...")
    traverse(element: window, depth: 0)
}

print("Total elements before deduplication: \(allElements.count)")
for elem in allElements {
    if elem.title.contains("swift") || elem.title.contains("decompile") || elem.title.contains("scratch") {
        print("  Role: \(elem.role), Title: \"\(elem.title)\", Frame: \(elem.frame)")
    }
}
