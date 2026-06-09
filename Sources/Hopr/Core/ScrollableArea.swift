import Cocoa
import ApplicationServices

struct ScrollableArea: Identifiable {
    let id = UUID()
    let element: AXUIElement
    let frame: CGRect           // AX coordinates (top-left origin)
    let screenFrame: CGRect     // Screen coordinates (bottom-left origin, ready for NSWindow)
    var number: String = ""

    init(element: AXUIElement, frame: CGRect, screenFrame: CGRect? = nil) {
        self.element = element
        self.frame = frame
        if let sf = screenFrame {
            self.screenFrame = sf
        } else {
            // Convert AX → screen
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
            self.screenFrame = CGRect(
                origin: CGPoint(x: frame.origin.x, y: primaryHeight - frame.origin.y - frame.height),
                size: frame.size
            )
        }
    }

    static func from(_ element: AXUIElement) -> ScrollableArea? {
        guard let position = getPointAttribute(element, kAXPositionAttribute),
              let size = getSizeAttribute(element, kAXSizeAttribute) else { return nil }
        let frame = CGRect(origin: position, size: size)
        return ScrollableArea(element: element, frame: frame)
    }
}

private func getPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let ref = value else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(unsafeBitCast(ref, to: AXValue.self), .cgPoint, &point) else { return nil }
    return point
}

private func getSizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let ref = value else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(ref, to: AXValue.self), .cgSize, &size) else { return nil }
    return size
}
