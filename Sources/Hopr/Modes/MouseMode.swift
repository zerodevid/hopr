import Cocoa
import Carbon.HIToolbox

final class MouseMode: Mode {
    private var mouseTimer: Timer?
    private var pressedKeys = Set<UInt16>()
    private var velocity = CGPoint.zero
    private var isActive = false

    private var settings: AppSettings { AppSettings.shared }
    private var keyW: UInt16 { UInt16(settings.mouseKeyUp) }
    private var keyA: UInt16 { UInt16(settings.mouseKeyLeft) }
    private var keyS: UInt16 { UInt16(settings.mouseKeyDown) }
    private var keyD: UInt16 { UInt16(settings.mouseKeyRight) }

    // Key mappings
    private let keyLeft = UInt16(kVK_ANSI_Q)
    private let keyRight = UInt16(kVK_ANSI_E)

    // Scroll key mappings (arrow keys)
    private let keyUpArrow: UInt16 = UInt16(kVK_UpArrow)
    private let keyDownArrow: UInt16 = UInt16(kVK_DownArrow)
    private let keyLeftArrow: UInt16 = UInt16(kVK_LeftArrow)
    private let keyRightArrow: UInt16 = UInt16(kVK_RightArrow)
    private var scrollVelocity = CGPoint.zero

    // Drag-and-drop state
    private var isDragging = false
    private var dragTimer: Timer?
    private var leftPressPoint = CGPoint.zero
    private var movementFramesHeld = 0

    func activate() {
        isActive = true
        pressedKeys = []
        velocity = .zero
        scrollVelocity = .zero
        isDragging = false
        dragTimer?.invalidate()
        dragTimer = nil
        movementFramesHeld = 0
        startMovementLoop()
        SoundManager.shared.playEnterMode()
        Log.info("Mouse mode activated")
    }

    func deactivate() {
        isActive = false
        stopMovementLoop()
        dragTimer?.invalidate()
        dragTimer = nil

        if isDragging {
            let currentPoint = CGEvent(source: nil)?.location ?? .zero
            if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: currentPoint, mouseButton: .left) {
                mouseUp.post(tap: .cghidEventTap)
            }
            NotificationCenter.default.post(name: .mouseDragDidEnd, object: nil)
            isDragging = false
        }

        pressedKeys = []
        velocity = .zero
        scrollVelocity = .zero
        movementFramesHeld = 0
        Log.info("Mouse mode deactivated")
    }

    func handleKeyPress(_ key: String, keyCode: UInt16, isRepeat: Bool, modifiers: KeyModifiers) -> Bool {
        guard isActive else { return false }

        let movementKeys: Set<UInt16> = [keyW, keyA, keyS, keyD]
        if movementKeys.contains(keyCode) {
            let isNew = !pressedKeys.contains(keyCode)
            pressedKeys.insert(keyCode)
            if isNew && !isRepeat {
                SoundManager.shared.playKeyPress()
            }
            return true
        }

        // Arrow keys for scrolling
        let scrollKeys: Set<UInt16> = [keyUpArrow, keyDownArrow, keyLeftArrow, keyRightArrow]
        if scrollKeys.contains(keyCode) {
            let isNew = !pressedKeys.contains(keyCode)
            pressedKeys.insert(keyCode)
            if isNew && !isRepeat {
                SoundManager.shared.playKeyPress()
            }
            return true
        }

        // Left Click & Drag-and-Drop (Q held down)
        if keyCode == keyLeft {
            if !isRepeat {
                pressedKeys.insert(keyCode)
                let currentPoint = CGEvent(source: nil)?.location ?? .zero
                leftPressPoint = currentPoint

                // Start a timer to detect long press for drag initiation
                dragTimer?.invalidate()
                dragTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.shared.mouseDragDelay, repeats: false) { [weak self] _ in
                    guard let self = self, self.isActive else { return }
                    if self.pressedKeys.contains(self.keyLeft) {
                        self.isDragging = true
                        // Simulate leftMouseDown to start the drag sequence
                        if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: self.leftPressPoint, mouseButton: .left) {
                            mouseDown.post(tap: .cghidEventTap)
                        }
                        SoundManager.shared.playActivate()
                        NotificationCenter.default.post(name: .mouseDragDidStart, object: nil)
                        Log.info("Mouse drag started at \(self.leftPressPoint)")
                    }
                }
            }
            return true
        }

        // Right Click (E) - Triggers instantly on down for immediate response
        if keyCode == keyRight {
            if !isRepeat {
                pressedKeys.insert(keyCode)
                let currentPoint = CGEvent(source: nil)?.location ?? .zero
                performRightClick(at: currentPoint)
                SoundManager.shared.playActivate()
            }
            return true
        }

        return false
    }

    func handleKeyUp(_ key: String, keyCode: UInt16) {
        pressedKeys.remove(keyCode)

        // Left Click release (Q)
        if keyCode == keyLeft {
            dragTimer?.invalidate()
            dragTimer = nil

            let currentPoint = CGEvent(source: nil)?.location ?? .zero

            if isDragging {
                // Complete the drag: simulate leftMouseUp
                if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: currentPoint, mouseButton: .left) {
                    mouseUp.post(tap: .cghidEventTap)
                }
                isDragging = false
                SoundManager.shared.playActivate()
                NotificationCenter.default.post(name: .mouseDragDidEnd, object: nil)
                Log.info("Mouse drag completed at \(currentPoint)")
            } else {
                // Short press: perform normal left-click
                performLeftClick(at: currentPoint)
                SoundManager.shared.playActivate()
            }
        }
    }

    // MARK: - Click Actions

    private func performLeftClick(at point: CGPoint) {
        Log.info("Mouse left click at \(point)")
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    private func performRightClick(at point: CGPoint) {
        Log.info("Mouse right click at \(point)")
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Movement Loop

    private func startMovementLoop() {
        stopMovementLoop()
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateMovement()
        }
    }

    private func stopMovementLoop() {
        mouseTimer?.invalidate()
        mouseTimer = nil
    }

    private func updateMovement() {
        let flags = NSEvent.modifierFlags
        let isFast = flags.contains(.shift)

        var forceY: CGFloat = 0
        if pressedKeys.contains(keyW) {
            forceY -= 1.0
        }
        if pressedKeys.contains(keyS) {
            forceY += 1.0
        }

        var forceX: CGFloat = 0
        if pressedKeys.contains(keyA) {
            forceX -= 1.0
        }
        if pressedKeys.contains(keyD) {
            forceX += 1.0
        }

        let isMoving = forceX != 0 || forceY != 0
        if isMoving {
            movementFramesHeld += 1
        } else {
            movementFramesHeld = 0
        }

        // Linear acceleration ramp to support fast snappiness
        let rampDuration: CGFloat = 18.0 // ~300ms to reach max speed
        let t = min(1.0, CGFloat(movementFramesHeld) / rampDuration)
        let interpolation = t // Linear ramp

        let minSpeed: CGFloat = isFast ? CGFloat(AppSettings.shared.mouseFastSpeed) * 0.125 : CGFloat(AppSettings.shared.mouseSpeed) * 0.125
        let maxSpeed: CGFloat = isFast ? CGFloat(AppSettings.shared.mouseFastSpeed) : CGFloat(AppSettings.shared.mouseSpeed)
        let targetSpeed = minSpeed + (maxSpeed - minSpeed) * interpolation

        let friction: CGFloat = 0.82
        let maxVelocity = targetSpeed
        let accelRate: CGFloat = 0.20

        // Update Y velocity
        if forceY != 0 {
            velocity.y += forceY * (maxVelocity * accelRate)
            if velocity.y > maxVelocity { velocity.y = maxVelocity }
            if velocity.y < -maxVelocity { velocity.y = -maxVelocity }
        } else {
            velocity.y *= friction
            if abs(velocity.y) < 0.1 {
                velocity.y = 0
            }
        }

        // Update X velocity
        if forceX != 0 {
            velocity.x += forceX * (maxVelocity * accelRate)
            if velocity.x > maxVelocity { velocity.x = maxVelocity }
            if velocity.x < -maxVelocity { velocity.x = -maxVelocity }
        } else {
            velocity.x *= friction
            if abs(velocity.x) < 0.1 {
                velocity.x = 0
            }
        }

        if velocity.x != 0 || velocity.y != 0 {
            let currentLoc = CGEvent(source: nil)?.location ?? .zero
            var targetLoc = CGPoint(x: currentLoc.x + velocity.x, y: currentLoc.y + velocity.y)
            targetLoc = clampToScreen(targetLoc)

            if isDragging {
                // Dragging: send leftMouseDragged event
                if let dragEvent = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseDragged,
                    mouseCursorPosition: targetLoc,
                    mouseButton: .left
                ) {
                    dragEvent.post(tap: .cghidEventTap)
                }
            } else {
                // Normal move: send mouseMoved event
                if let moveEvent = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: targetLoc,
                    mouseButton: .left
                ) {
                    moveEvent.post(tap: .cghidEventTap)
                }
            }
        }

        // --- Scroll physics (arrow keys) ---
        let scrollSpeed = isFast ? CGFloat(AppSettings.shared.dashSpeed) : CGFloat(AppSettings.shared.scrollSpeed)

        var scrollForceY: CGFloat = 0
        if pressedKeys.contains(keyUpArrow) {
            scrollForceY += 1.0   // scroll up
        }
        if pressedKeys.contains(keyDownArrow) {
            scrollForceY -= 1.0   // scroll down
        }

        var scrollForceX: CGFloat = 0
        if pressedKeys.contains(keyLeftArrow) {
            scrollForceX += 1.0   // scroll left
        }
        if pressedKeys.contains(keyRightArrow) {
            scrollForceX -= 1.0   // scroll right
        }

        let scrollFriction: CGFloat = 0.85
        let scrollMaxVelocity = scrollSpeed * 2.5
        let scrollAccelRate: CGFloat = 0.20

        if scrollForceY != 0 {
            scrollVelocity.y += scrollForceY * (scrollMaxVelocity * scrollAccelRate)
            if scrollVelocity.y > scrollMaxVelocity { scrollVelocity.y = scrollMaxVelocity }
            if scrollVelocity.y < -scrollMaxVelocity { scrollVelocity.y = -scrollMaxVelocity }
        } else {
            scrollVelocity.y *= scrollFriction
            if abs(scrollVelocity.y) < 0.1 { scrollVelocity.y = 0 }
        }

        if scrollForceX != 0 {
            scrollVelocity.x += scrollForceX * (scrollMaxVelocity * scrollAccelRate)
            if scrollVelocity.x > scrollMaxVelocity { scrollVelocity.x = scrollMaxVelocity }
            if scrollVelocity.x < -scrollMaxVelocity { scrollVelocity.x = -scrollMaxVelocity }
        } else {
            scrollVelocity.x *= scrollFriction
            if abs(scrollVelocity.x) < 0.1 { scrollVelocity.x = 0 }
        }

        if scrollVelocity.x != 0 || scrollVelocity.y != 0 {
            sendScrollEvent(vertical: scrollVelocity.y, horizontal: scrollVelocity.x)
        }
    }

    private func clampToScreen(_ point: CGPoint) -> CGPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return point }

        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        let primaryHeight = screens[0].frame.height

        for screen in screens {
            let f = screen.frame
            minX = min(minX, f.minX)
            maxX = max(maxX, f.maxX)

            // Convert Cocoa Y to Quartz Y
            let cgTop = primaryHeight - (f.origin.y + f.size.height)
            let cgBottom = primaryHeight - f.origin.y
            minY = min(minY, cgTop)
            maxY = max(maxY, cgBottom)
        }

        let clampedX = max(minX, min(maxX - 1, point.x))
        let clampedY = max(minY, min(maxY - 1, point.y))
        return CGPoint(x: clampedX, y: clampedY)
    }

    // MARK: - Scroll

    private func sendScrollEvent(vertical: CGFloat, horizontal: CGFloat) {
        if let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(vertical),
            wheel2: Int32(horizontal),
            wheel3: 0
        ) {
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(vertical))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(vertical))
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(horizontal))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(horizontal))
            event.post(tap: .cghidEventTap)
        }
    }
}
