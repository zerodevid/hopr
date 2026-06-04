import Cocoa
import ApplicationServices

let actionableRoles: Set<String> = [
    kAXButtonRole as String,
    kAXCheckBoxRole as String,
    kAXRadioButtonRole as String,
    kAXPopUpButtonRole as String,
    kAXMenuItemRole as String,
    "AXLink",
    kAXTextFieldRole as String,
    kAXTextAreaRole as String,
    kAXComboBoxRole as String,
    "AXTab",
    kAXMenuBarItemRole as String,
    "AXToolbar",
]

struct UIElement: Identifiable {
    let id = UUID()
    let element: AXUIElement
    let role: String
    let title: String
    let frame: CGRect
    let enabled: Bool
    var parentRowId: UUID? = nil

    static func from(_ element: AXUIElement) -> UIElement? {
        guard let role = getStringAttribute(element, kAXRoleAttribute) else { return nil }

        var t = getStringAttribute(element, kAXTitleAttribute) ?? ""
        if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            t = getStringAttribute(element, kAXDescriptionAttribute) ?? ""
        }
        if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            t = getStringAttribute(element, kAXValueAttribute) ?? ""
        }
        let title = t

        guard let position = getPointAttribute(element, kAXPositionAttribute),
              let size = getSizeAttribute(element, kAXSizeAttribute) else { return nil }

        let frame = CGRect(origin: position, size: size)
        let enabled = true

        return UIElement(element: element, role: role, title: title, frame: frame, enabled: enabled)
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

let runningApps = NSWorkspace.shared.runningApplications
guard let app = runningApps.first(where: {
    $0.bundleIdentifier?.contains("antigravity") == true ||
    $0.bundleIdentifier?.contains("VSCode") == true ||
    $0.localizedName?.lowercased().contains("antigravity") == true ||
    $0.localizedName?.lowercased().contains("visual studio code") == true
}) else {
    print("Error: Could not find Antigravity IDE or VS Code running.")
    exit(1)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)

var windowsRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
      let windows = windowsRef as? [AXUIElement],
      let window = windows.first else {
    print("No windows found")
    exit(1)
}

func shouldInclude(_ elem: UIElement, _ rawElement: AXUIElement) -> Bool {
    if actionableRoles.contains(elem.role) { return true }
    if !elem.title.isEmpty {
        if elem.role == "AXGroup" || elem.role == "AXWebArea" {
            return false
        }
        // Filter out non-alphanumeric static text / icon labels
        if elem.role == "AXStaticText" {
            let trimmed = elem.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasLetterOrDigit = trimmed.rangeOfCharacter(from: .alphanumerics) != nil
            if !hasLetterOrDigit {
                return false
            }
        }
        return true
    }
    return false
}

func traverse(element: AXUIElement, depth: Int, parentRowId: UUID?, elements: inout [UIElement]) {
    guard depth < 45 else { return }

    var currentParentRowId = parentRowId
    if var uiElement = UIElement.from(element) {
        uiElement.parentRowId = parentRowId
        if uiElement.role == "AXRow" || uiElement.role == "AXOutlineRow" {
            currentParentRowId = uiElement.id
        }
        if shouldInclude(uiElement, element) {
            elements.append(uiElement)
        }
    }

    var children: [AXUIElement] = []

    var navRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &navRef) == .success,
       let navChildren = navRef as? [AXUIElement] {
        children.append(contentsOf: navChildren)
    }

    var normalRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &normalRef) == .success,
       let normalChildren = normalRef as? [AXUIElement] {
        children.append(contentsOf: normalChildren)
    }

    var uniqueChildren: [AXUIElement] = []
    var seenHashes = Set<CFHashCode>()
    for child in children {
        let hash = CFHash(child)
        if !seenHashes.contains(hash) {
            seenHashes.insert(hash)
            uniqueChildren.append(child)
        }
    }

    for child in uniqueChildren {
        traverse(element: child, depth: depth + 1, parentRowId: currentParentRowId, elements: &elements)
    }
}

func deduplicateOverlapping(_ elements: [UIElement]) -> [UIElement] {
    guard elements.count > 1 else { return elements }

    let rolePriority: [String: Int] = [
        kAXButtonRole as String: 0,
        "AXCheckBox": 0,
        "AXRadioButton": 0,
        "AXPopUpButton": 0,
        "AXMenuItem": 1,
        "AXLink": 2,
        "AXTextField": 3,
        "AXTextArea": 3,
        "AXTab": 4,
        "AXMenuBarItem": 1,
    ]

    let containerRoles: Set<String> = [
        "AXGroup",
        "AXScrollArea",
        "AXOutline",
        "AXList",
        "AXTable",
        "AXRow",
        "AXOutlineRow",
        "AXWindow",
        "AXWebArea",
        "AXToolbar",
        "AXSplitView",
        "AXScrollbar",
        "AXSheet"
    ]

    var kept: [UIElement] = []

    for elem in elements.sorted(by: { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }) {
        var isOverlap = false
        for existing in kept {
            if containerRoles.contains(existing.role) {
                continue
            }

            let intersection = elem.frame.intersection(existing.frame)
            if intersection.width > 0 && intersection.height > 0 {
                let overlapArea = intersection.width * intersection.height
                let elemArea = elem.frame.width * elem.frame.height
                let existingArea = existing.frame.width * existing.frame.height
                let smallerArea = min(elemArea, existingArea)

                if smallerArea > 0 && (overlapArea / smallerArea) > 0.4 {
                    let elemPriority = rolePriority[elem.role] ?? 99
                    let existingPriority = rolePriority[existing.role] ?? 99
                    if elemPriority < existingPriority {
                        if let idx = kept.firstIndex(where: { $0.id == existing.id }) {
                            kept[idx] = elem
                        }
                    }
                    isOverlap = true
                    break
                }
            }
        }
        if !isOverlap {
            kept.append(elem)
        }
    }

    return kept
}

var allElements: [UIElement] = []
traverse(element: window, depth: 0, parentRowId: nil, elements: &allElements)
print("Total traversed: \(allElements.count)")

// Post-processing
var toRemove = Set<UUID>()
let rows = allElements.filter { $0.role == "AXRow" || $0.role == "AXOutlineRow" }
print("Found \(rows.count) rows to optimize.")

for row in rows {
    let descendants = allElements.filter { $0.parentRowId == row.id }
    let textDescendants = descendants.filter {
        $0.role == "AXStaticText" || $0.role == "AXTextField" || $0.role == "AXTextArea" || $0.role == "AXLink"
    }
    
    if !textDescendants.isEmpty {
        if let primaryLabel = textDescendants.first {
            toRemove.insert(row.id)
            for desc in textDescendants {
                if desc.id != primaryLabel.id {
                    toRemove.insert(desc.id)
                }
            }
        }
    } else {
        // If there's no text-like descendant, keep the row itself.
    }
    
    let buttonDescendants = descendants.filter { $0.role == "AXButton" }
    for btn in buttonDescendants {
        let lowerTitle = btn.title.lowercased()
        if lowerTitle.contains("expand") || lowerTitle.contains("collapse") ||
           lowerTitle.contains("chevron") || lowerTitle.contains("arrow") ||
           btn.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toRemove.insert(btn.id)
        }
    }
}

let visible = allElements.filter { elem in
    !toRemove.contains(elem.id)
    && elem.frame.width > 5 && elem.frame.height > 5
    && elem.frame.origin.x > -200 && elem.frame.origin.y > -200
}
print("Total visible after row optimizations: \(visible.count)")

let deduplicated = deduplicateOverlapping(visible)
print("Total after deduplication: \(deduplicated.count)")

print("\n--- PRINTING REMAINING OUTLINE/ROW RELATED ELEMENTS ---")
for elem in deduplicated {
    if elem.role == "AXRow" || elem.role == "AXStaticText" || elem.role == "AXButton" {
        print("Role: \(elem.role) | Title: \"\(elem.title)\" | Frame: \(elem.frame)")
    }
}
