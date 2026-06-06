import Cocoa
import Carbon.HIToolbox

final class ScrollMode {

    private let overlayController = OverlayWindowController()
    private var scrollAreas: [ScrollableArea] = []
    private var selectedArea: ScrollableArea?
    private var phase: ScrollPhase = .selecting
    private var scrollTimer: Timer?
    private var pressedKeys = Set<UInt16>()
    private var velocity = CGPoint.zero
    private var settings: AppSettings { AppSettings.shared }
    private var originalMousePosition: CGPoint?

    private enum ScrollPhase {
        case selecting
        case scrolling
    }

    func activate() {
        // Save current mouse position
        originalMousePosition = CGEvent(source: nil)?.location

        scrollAreas = AccessibilityService.shared.getAllScrollAreas()
        let showNumbers = AppSettings.shared.showScrollAreaNumbers
        for i in 0..<scrollAreas.count {
            // Display number only when setting is on; key selection uses position index internally
            scrollAreas[i].number = showNumbers ? "\(i + 1)" : ""
        }

        phase = .selecting
        pressedKeys = []
        velocity = .zero
        overlayController.showScrollAreaOverlays(for: scrollAreas)
        Log.info("Scroll mode: found \(scrollAreas.count) scroll areas — press 1-\(scrollAreas.count) to select")
        
        startPhysicsLoop()
        SoundManager.shared.playEnterMode()
    }

    func deactivate() {
        stopPhysicsLoop()
        overlayController.dismissAll()
        scrollAreas = []
        selectedArea = nil
        phase = .selecting
        pressedKeys = []
        velocity = .zero

        // Restore original mouse position
        if let original = originalMousePosition {
            CGWarpMouseCursorPosition(original)
            originalMousePosition = nil
        }

        Log.info("Scroll mode deactivated")
    }

    func handleKeyPress(keyCode: UInt16, isRepeat: Bool) -> Bool {
        switch phase {
        case .selecting:
            let validSelectKeys: Set<UInt16> = [
                UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3),
                UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6),
                UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9)
            ]
            if validSelectKeys.contains(keyCode) {
                return handleAreaSelection(keyCode: keyCode, isRepeat: isRepeat)
            }
            // Invalid key → auto exit
            if !isRepeat {
                NotificationCenter.default.post(name: .scrollModeDidExit, object: nil)
                SoundManager.shared.playKeyMiss()
            }
            return true
        case .scrolling:
            let scrollKeys: Set<UInt16> = [
                UInt16(kVK_ANSI_J),
                UInt16(kVK_ANSI_K),
                UInt16(kVK_ANSI_H),
                UInt16(kVK_ANSI_L)
            ]
            if scrollKeys.contains(keyCode) {
                let isNew = !pressedKeys.contains(keyCode)
                pressedKeys.insert(keyCode)
                if isNew && !isRepeat {
                    SoundManager.shared.playKeyPress()
                }
                return true
            }

            // Allow switching to a different scroll area by typing a digit key
            let digitKeys: Set<UInt16> = [
                UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3),
                UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6),
                UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9)
            ]
            if digitKeys.contains(keyCode) {
                pressedKeys.removeAll()
                velocity = .zero
                return handleAreaSelection(keyCode: keyCode, isRepeat: isRepeat)
            }

            // Invalid key → auto exit
            if !isRepeat {
                NotificationCenter.default.post(name: .scrollModeDidExit, object: nil)
                SoundManager.shared.playKeyMiss()
            }
            return true
        }
    }

    func handleKeyUp(keyCode: UInt16) {
        pressedKeys.remove(keyCode)
    }

    // MARK: - Area Selection

    private func handleAreaSelection(keyCode: UInt16, isRepeat: Bool) -> Bool {
        let digit = keyCodeToDigit(keyCode)
        if let digit, digit >= 1, digit <= scrollAreas.count {
            let area = scrollAreas[digit - 1]
            selectedArea = area
            phase = .scrolling
            overlayController.showSelectedScrollArea(area, allAreas: scrollAreas)
            Log.info("Selected scroll area #\(digit)")
            
            // Move cursor to selected area center once upon selection
            let center = CGPoint(
                x: area.frame.midX,
                y: area.frame.midY
            )
            if let moveEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: center,
                mouseButton: .left
            ) {
                moveEvent.post(tap: .cghidEventTap)
            }
            
            if !isRepeat {
                SoundManager.shared.playActivate()
            }
            return true
        }
        if !isRepeat {
            SoundManager.shared.playKeyMiss()
        }
        return false
    }

    // MARK: - Physics Loop

    private func startPhysicsLoop() {
        stopPhysicsLoop()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updatePhysics()
        }
    }

    private func stopPhysicsLoop() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func updatePhysics() {
        guard let _ = selectedArea else { return }

        let flags = NSEvent.modifierFlags
        let isFast = flags.contains(.shift)
        
        let baseSpeed = isFast ? settings.dashSpeed : settings.scrollSpeed
        
        // Calculate force direction from currently pressed keys
        var forceY: CGFloat = 0
        if pressedKeys.contains(UInt16(kVK_ANSI_J)) {
            forceY += 1.0  // scroll up (naik)
        }
        if pressedKeys.contains(UInt16(kVK_ANSI_K)) {
            forceY -= 1.0  // scroll down (turun)
        }

        var forceX: CGFloat = 0
        if pressedKeys.contains(UInt16(kVK_ANSI_H)) {
            forceX += 1.0  // scroll left (content right)
        }
        if pressedKeys.contains(UInt16(kVK_ANSI_L)) {
            forceX -= 1.0  // scroll right (content left)
        }

        // Physics parameters
        let friction: CGFloat = 0.85
        let maxVelocity = baseSpeed * 2.5
        let accelRate: CGFloat = 0.20 // reached in 5 frames
        
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

        // Perform the scroll if there is velocity
        if velocity.x != 0 || velocity.y != 0 {
            scroll(vertical: velocity.y, horizontal: velocity.x)
        }
    }

    private func scroll(vertical: CGFloat, horizontal: CGFloat) {
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

    private func keyCodeToDigit(_ keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 1
        case kVK_ANSI_2: return 2
        case kVK_ANSI_3: return 3
        case kVK_ANSI_4: return 4
        case kVK_ANSI_5: return 5
        case kVK_ANSI_6: return 6
        case kVK_ANSI_7: return 7
        case kVK_ANSI_8: return 8
        case kVK_ANSI_9: return 9
        default: return nil
        }
    }
}
