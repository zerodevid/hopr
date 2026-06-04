import Cocoa
import ApplicationServices

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName?.lowercased().contains("antigravity") == true
}) else { print("App not found"); exit(1) }

print("App: \(app.localizedName!) PID: \(app.processIdentifier)")
let appElement = AXUIElementCreateApplication(app.processIdentifier)

// Enable accessibility for Electron (like Hopr does)
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
_ = AXIsProcessTrustedWithOptions(options)

// Try AXEnhancedUserInterface
AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

// Get windows
var windowsRef: CFTypeRef?
AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
let windows = windowsRef as? [AXUIElement] ?? []
print("Windows: \(windows.count)")

for (i, window) in windows.enumerated() {
    // Method 1: AXPosition + AXSize
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
    var point = CGPoint.zero
    var size = CGSize.zero
    if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &point) }
    if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }
    print("\nWindow \(i) AXPosition/Size: [\(Int(point.x)),\(Int(point.y)) \(Int(size.width))x\(Int(size.height))]")

    // Method 2: accessibilityFrame (screen coordinates)
    var frameRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(window, "AXFrame" as CFString, &frameRef) == .success,
       let frameVal = frameRef {
        var frame = CGRect.zero
        AXValueGetValue(frameVal as! AXValue, .cgRect, &frame)
        print("Window \(i) AXFrame: [\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))]")
    }

    // Method 3: Check children for scroll areas
    var childrenRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
       let children = childrenRef as? [AXUIElement] {
        print("Window \(i) children: \(children.count)")

        for (j, child) in children.prefix(10).enumerated() {
            var childRoleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRoleRef)
            let childRole = childRoleRef as? String ?? "?"

            var childPosRef: CFTypeRef?
            var childSizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &childPosRef)
            AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &childSizeRef)
            var cPoint = CGPoint.zero
            var cSize = CGSize.zero
            if let p = childPosRef { AXValueGetValue(p as! AXValue, .cgPoint, &cPoint) }
            if let s = childSizeRef { AXValueGetValue(s as! AXValue, .cgSize, &cSize) }

            var childFrameRef: CFTypeRef?
            var childFrame = CGRect.zero
            if AXUIElementCopyAttributeValue(child, "AXFrame" as CFString, &childFrameRef) == .success,
               let fv = childFrameRef {
                AXValueGetValue(fv as! AXValue, .cgRect, &childFrame)
            }

            print("  Child \(j): \(childRole) AXSize=[\(Int(cSize.width))x\(Int(cSize.height))] AXFrame=[\(Int(childFrame.origin.x)),\(Int(childFrame.origin.y)) \(Int(childFrame.width))x\(Int(childFrame.height))]")
        }
    }
}
