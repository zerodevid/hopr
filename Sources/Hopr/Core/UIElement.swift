import Cocoa
import ApplicationServices

struct UIElement: Identifiable {
    let id = UUID()
    let element: AXUIElement?
    let role: String
    let title: String
    let frame: CGRect
    let enabled: Bool
    var parentRowId: UUID? = nil
    var isSystemOverlay: Bool = false

    var label: String = ""

    /// Interactive control roles whose label may live in a child (icon buttons, cells,
    /// menu items…). Only these pay the descendant-title search; containers/text don't.
    private static let rolesNeedingChildTitle: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXMenuBarItem",
        "AXPopUpButton", "AXComboBox", "AXCell", "AXRow", "AXTab", "AXDisclosureTriangle",
    ]

    /// Attributes fetched in ONE batched IPC round-trip (was 8 separate calls per node —
    /// the dominant cost when traversing large Electron/web trees).
    private static let fromAttrs: CFArray = [
        kAXRoleAttribute as String,
        kAXTitleAttribute as String,
        kAXDescriptionAttribute as String,
        kAXValueAttribute as String,
        kAXHelpAttribute as String,
        kAXPositionAttribute as String,
        kAXSizeAttribute as String,
        kAXEnabledAttribute as String,
    ] as CFArray

    /// Same 8 attributes as `fromAttrs` plus both children lists — lets `traverse` get the
    /// element AND its children in ONE IPC instead of three.
    private static let fromWithChildrenAttrs: CFArray = [
        kAXRoleAttribute as String,
        kAXTitleAttribute as String,
        kAXDescriptionAttribute as String,
        kAXValueAttribute as String,
        kAXHelpAttribute as String,
        kAXPositionAttribute as String,
        kAXSizeAttribute as String,
        kAXEnabledAttribute as String,
        "AXChildrenInNavigationOrder",
        kAXChildrenAttribute as String,
    ] as CFArray

    static func from(_ element: AXUIElement) -> UIElement? {
        var valuesRef: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, fromAttrs, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef) == .success,
              let v = valuesRef as? [AnyObject], v.count == 8 else { return nil }
        return parse(element, v)
    }

    /// Element + children in a single batched IPC (the hot path in `traverse`). The
    /// element may be nil (no role/frame) while children are still returned, so traversal
    /// can keep descending through structural/position-less nodes like the old code did.
    static func fromWithChildren(_ element: AXUIElement) -> (element: UIElement?, children: [AXUIElement]) {
        var valuesRef: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, fromWithChildrenAttrs, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef) == .success,
              let v = valuesRef as? [AnyObject], v.count == 10 else { return (nil, []) }
        // Prefer navigation order; fall back to plain children.
        let children = (v[8] as? [AXUIElement]) ?? (v[9] as? [AXUIElement]) ?? []
        return (parse(element, v), children)
    }

    /// Build a UIElement from the first 8 batched attribute values (role, title sources,
    /// position, size, enabled).
    private static func parse(_ element: AXUIElement, _ v: [AnyObject]) -> UIElement? {
        guard let role = v[0] as? String else { return nil }

        // title: title → description → value(string) → help → (rare) children scan.
        func nonEmpty(_ i: Int) -> String? {
            guard let s = v[i] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return s
        }
        var title = nonEmpty(1) ?? nonEmpty(2) ?? nonEmpty(3) ?? nonEmpty(4) ?? ""
        // Deriving a label from descendants is only worth its cost for interactive controls
        // (an icon button whose text is a child, a list cell, etc.). For the title-less
        // AXGroup / AXStaticText divs that make up the bulk of a web tree it's pure waste —
        // running it for every such node was the O(n²) blowup. Skip them.
        if title.isEmpty && rolesNeedingChildTitle.contains(role) {
            title = findTitleInChildren(element) ?? ""
        }

        // position + size are AXValue refs (or an axError placeholder if missing).
        var point = CGPoint.zero
        var size = CGSize.zero
        let posVal = v[5] as CFTypeRef
        let sizeVal = v[6] as CFTypeRef
        guard CFGetTypeID(posVal) == AXValueGetTypeID(),
              AXValueGetValue(unsafeBitCast(posVal, to: AXValue.self), .cgPoint, &point),
              CFGetTypeID(sizeVal) == AXValueGetTypeID(),
              AXValueGetValue(unsafeBitCast(sizeVal, to: AXValue.self), .cgSize, &size) else { return nil }

        let frame = CGRect(origin: point, size: size)
        let enabled = (v[7] as? Bool) ?? true

        return UIElement(element: element, role: role, title: title, frame: frame, enabled: enabled)
    }

    /// Center point of the element in screen coordinates (AX coordinate space)
    var centerPoint: CGPoint {
        CGPoint(x: frame.origin.x + frame.size.width / 2,
                y: frame.origin.y + frame.size.height / 2)
    }

    func performAction(_ action: ClickAction = .click) {
        // Always warp the mouse cursor to the element first
        moveCursorTo()

        switch action {
        case .click:
            performDefaultClick()
        case .rightClick:
            Log.debug("Right-click on \(title) [\(role)]")
            simulateRightClick()
        case .doubleClick:
            Log.debug("Double-click on \(title) [\(role)]")
            simulateDoubleClick()
        case .hover:
            Log.debug("Hover on \(title) [\(role)]")
            // Cursor is already moved
        }
    }

    private func performDefaultClick() {
        // If it's a text entry element, focus it explicitly first
        let isTextEntry = role == (kAXTextFieldRole as String) ||
                          role == (kAXTextAreaRole as String) ||
                          role == (kAXComboBoxRole as String) ||
                          role == "AXSearchField" ||
                          role.lowercased().contains("text")
        
        if isTextEntry {
            Log.debug("Element is text entry, applying keyboard focus first")
            focus()
        }

        simulateClick()
    }

    // MARK: - Mouse Simulation

    private func simulateClick() {
        let point = centerPoint
        if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            mouseDown.post(tap: .cghidEventTap)
        }
        if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    private func simulateRightClick() {
        let point = centerPoint
        if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right) {
            mouseDown.post(tap: .cghidEventTap)
        }
        if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    private func simulateDoubleClick() {
        let point = centerPoint
        // First click
        if let down1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down1.setIntegerValueField(.mouseEventClickState, value: 1)
            down1.post(tap: .cghidEventTap)
        }
        if let up1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up1.setIntegerValueField(.mouseEventClickState, value: 1)
            up1.post(tap: .cghidEventTap)
        }
        // Second click (clickState = 2 tells the system this is a double-click)
        if let down2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down2.setIntegerValueField(.mouseEventClickState, value: 2)
            down2.post(tap: .cghidEventTap)
        }
        if let up2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up2.setIntegerValueField(.mouseEventClickState, value: 2)
            up2.post(tap: .cghidEventTap)
        }
    }

    private func moveCursorTo() {
        let point = centerPoint
        CGWarpMouseCursorPosition(point)

        // Post a mouse-moved event slightly offset, then another at the exact target location.
        // This transition delta (1 pixel) forces browsers (Chrome/Safari) and other macOS apps
        // to register a real mouse move transition and trigger CSS :hover and JS mouseover/mouseenter events.
        let offsetPoint = CGPoint(x: point.x - 1, y: point.y)
        if let moveOffset = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                    mouseCursorPosition: offsetPoint, mouseButton: .left) {
            moveOffset.post(tap: .cghidEventTap)
        }

        if let moveTarget = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                    mouseCursorPosition: point, mouseButton: .left) {
            moveTarget.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Drag Support

    /// Begin a drag operation: moves cursor to this element and holds mouseDown
    func beginDrag() {
        let point = centerPoint
        CGWarpMouseCursorPosition(point)
        if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                   mouseCursorPosition: point, mouseButton: .left) {
            mouseDown.post(tap: .cghidEventTap)
        }
    }

    /// Complete a drag: moves cursor to this element via mouseDragged then releases
    func completeDragHere(from source: CGPoint) {
        let dest = centerPoint

        // Animate drag in steps for realism
        let steps = 8
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let pt = CGPoint(x: source.x + (dest.x - source.x) * t,
                             y: source.y + (dest.y - source.y) * t)
            if let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                  mouseCursorPosition: pt, mouseButton: .left) {
                drag.post(tap: .cghidEventTap)
            }
        }

        // Release at destination
        if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                 mouseCursorPosition: dest, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    /// Cancel an in-progress drag by releasing the mouse at the given point
    static func cancelDrag(at point: CGPoint) {
        if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                 mouseCursorPosition: point, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    /// Perform a drag step: warps cursor to this point and sends leftMouseDragged event
    static func dragTo(point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        if let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                              mouseCursorPosition: point, mouseButton: .left) {
            drag.post(tap: .cghidEventTap)
        }
    }

    func focus() {
        if let element = element {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        }
    }
}

// MARK: - Click Action Types

enum ClickAction {
    case click
    case rightClick
    case doubleClick
    case hover
}

// MARK: - Element Snapshot (Disk Cache)

/// Serializable snapshot of UIElements for disk persistence.
/// Used to provide instant hint labels on app restart before live AX scan completes.
struct ElementSnapshot: Codable {
    let role: String
    let title: String
    let frameX: CGFloat
    let frameY: CGFloat
    let frameW: CGFloat
    let frameH: CGFloat
    let isSystemOverlay: Bool

    init(_ element: UIElement) {
        self.role = element.role
        self.title = element.title
        self.frameX = element.frame.origin.x
        self.frameY = element.frame.origin.y
        self.frameW = element.frame.width
        self.frameH = element.frame.height
        self.isSystemOverlay = element.isSystemOverlay
    }

    func toUIElement() -> UIElement {
        let frame = CGRect(
            origin: CGPoint(x: frameX, y: frameY),
            size: CGSize(width: frameW, height: frameH)
        )
        var elem = UIElement(element: nil, role: role, title: title, frame: frame, enabled: true)
        elem.isSystemOverlay = isSystemOverlay
        return elem
    }
}

// MARK: - AX Attribute Helpers

private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let str = value as? String else { return nil }
    return str
}

private func getPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }

    var point = CGPoint.zero
    guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point) else { return nil }
    return point
}

private func getSizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }

    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size) else { return nil }
    return size
}

private func getBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? Bool
}

private func getChildren(_ element: AXUIElement) -> [AXUIElement] {
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
    return uniqueChildren
}

private func findTitleInChildren(_ element: AXUIElement) -> String? {
    // 1. Try Title UI Element associated label on root first
    var titleUIElementRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute as CFString, &titleUIElementRef) == .success,
       let titleRef = titleUIElementRef {
        let labelElem = unsafeBitCast(titleRef, to: AXUIElement.self)
        var title = getStringAttribute(labelElem, kAXTitleAttribute) ?? ""
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = getStringAttribute(labelElem, kAXValueAttribute) ?? ""
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = getStringAttribute(labelElem, kAXDescriptionAttribute) ?? ""
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }

    // 2. Breadth-First Search (BFS) to find the closest descendant with a name/title.
    // A label always lives a level or two down, so keep this shallow and bounded — an
    // unbounded depth-15 BFS run for every empty-title node turns traversal into an
    // O(n²) blowup on large web/Electron trees (seconds for VSCode).
    var queueWithDepth: [(element: AXUIElement, depth: Int)] = [(element, 0)]
    var visited = Set<CFHashCode>()
    var index = 0
    let maxDepth = 3
    let maxVisited = 24

    while index < queueWithDepth.count && visited.count < maxVisited {
        let current = queueWithDepth[index]
        index += 1

        if current.depth > maxDepth { continue }

        let hash = CFHash(current.element)
        if visited.contains(hash) { continue }
        visited.insert(hash)

        if current.element != element {
            // Try Title UI Element on descendant
            var childTitleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current.element, kAXTitleUIElementAttribute as CFString, &childTitleRef) == .success,
               let titleRef = childTitleRef {
                let labelElem = unsafeBitCast(titleRef, to: AXUIElement.self)
                var title = getStringAttribute(labelElem, kAXTitleAttribute) ?? ""
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = getStringAttribute(labelElem, kAXValueAttribute) ?? ""
                }
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = getStringAttribute(labelElem, kAXDescriptionAttribute) ?? ""
                }
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let title = getStringAttribute(current.element, kAXTitleAttribute),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let desc = getStringAttribute(current.element, kAXDescriptionAttribute),
               !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return desc.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let val = getStringAttribute(current.element, kAXValueAttribute),
               !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let help = getStringAttribute(current.element, kAXHelpAttribute),
               !help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return help.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let children = getChildren(current.element)
        for child in children {
            queueWithDepth.append((child, current.depth + 1))
        }
    }

    return nil
}
