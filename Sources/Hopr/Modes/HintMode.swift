import Cocoa

final class HintMode {

    private let overlayController = OverlayWindowController()
    private var allElements: [UIElement] = []
    private var currentCandidates: [UIElement] = []
    private var typedPrefix = ""
    private var pendingTimer: Timer?
    private var isActive = false
    private var currentlyHeldKey: String? = nil
    private var isTemporarilyDisabled = false
    private var isFnPressed = false
    private var lastShiftPressTime: CFTimeInterval = 0

    var onVisibilityChange: ((Bool) -> Void)?

    /// The resolved action for the current hint session (sticky once set by modifier)
    private var pendingAction: ClickAction = .click

    /// Drag state: when non-nil, we are waiting for the drop target
    private var dragSourcePoint: CGPoint? = nil
    private var isNudgeDragging = false
    private var nudgeDragPoint = CGPoint.zero
    private var nudgeDragSize = CGSize(width: 50, height: 50)

    private let keyReturn: UInt16 = 36
    private let keyUpArrow: UInt16 = 126
    private let keyDownArrow: UInt16 = 125
    private let keyLeftArrow: UInt16 = 123
    private let keyRightArrow: UInt16 = 124
    private let keyW: UInt16 = 13
    private let keyA: UInt16 = 0
    private let keyS: UInt16 = 1
    private let keyD: UInt16 = 2

    /// Background queue for heavy AX tree scanning
    private static let scanQueue = DispatchQueue(label: "com.hopr.hint-scan", qos: .userInitiated)

    private var activePID: pid_t = 0
    private var activeBundleID: String = "unknown"

    /// Minimum time the loading indicator must remain visible (ms UX consistency)
    private static let minLoadingDisplayTime: TimeInterval = 0.35
    private var loadingStartTime: CFTimeInterval = 0

    func activate() {
        isActive = true
        isTemporarilyDisabled = false
        isFnPressed = false
        lastShiftPressTime = 0
        typedPrefix = ""
        pendingAction = .click
        dragSourcePoint = nil
        isNudgeDragging = false
        nudgeDragPoint = .zero
        nudgeDragSize = CGSize(width: 50, height: 50)
        pendingTimer?.invalidate()
        pendingTimer = nil

        let currentApp = NSWorkspace.shared.frontmostApplication
        let currentPID = currentApp?.processIdentifier ?? 0
        activePID = currentPID
        activeBundleID = currentApp?.bundleIdentifier ?? "unknown"

        // If we have valid pre-fetched elements for the current PID, show them INSTANTLY
        if let prefetched = AccessibilityService.shared.consumePrefetchedElements(for: currentPID) {
            let labeled = KeyMapper.assignLabels(to: prefetched.elements, for: prefetched.bundleID)
            self.allElements = labeled
            self.currentCandidates = labeled
            self.overlayController.showLabels(for: labeled)
            SoundManager.shared.playEnterMode()
            Log.info("Hint mode: instant show \(labeled.count) elements (prefetched for PID \(currentPID))")

            // Refresh in background to catch any changes
            self.refreshLabelsAsync(isInitialLoad: false)
        } else if let diskSnapshot = AccessibilityService.shared.loadHintSnapshot(for: activeBundleID) {
            // Disk cache hit — show instantly from last session
            SoundManager.shared.playEnterMode()
            let labeled = KeyMapper.assignLabels(to: diskSnapshot, for: activeBundleID)
            self.allElements = labeled
            self.currentCandidates = labeled
            self.overlayController.showLabels(for: labeled)
            Log.info("Hint mode: disk cache show \(labeled.count) elements (bundleID=\(activeBundleID))")
            // Refresh in background to catch any changes
            self.refreshLabelsAsync(isInitialLoad: false)
        } else {
            // No data available — show loading while scanning
            SoundManager.shared.playEnterMode()
            loadingStartTime = CACurrentMediaTime()
            NotificationCenter.default.post(name: .hintModeLoadingDidStart, object: nil)
            refreshLabelsAsync(isInitialLoad: true)
        }
    }

    func deactivate() {
        isActive = false
        isTemporarilyDisabled = false
        isFnPressed = false
        lastShiftPressTime = 0
        pendingTimer?.invalidate()
        pendingTimer = nil
        overlayController.dismissAll()

        // Cancel any in-progress drag (release mouse button)
        if let dragPoint = dragSourcePoint {
            UIElement.cancelDrag(at: dragPoint)
            dragSourcePoint = nil
            Log.info("Drag cancelled")
        }

        isNudgeDragging = false
        nudgeDragPoint = .zero
        overlayController.hideDragHighlight()

        allElements = []
        currentCandidates = []
        typedPrefix = ""
        pendingAction = .click
        currentlyHeldKey = nil
    }

    /// Pre-fetch elements in background so next activation is instant.
    /// Call this when the frontmost app changes or periodically.
    func prefetch(for app: NSRunningApplication? = nil) {
        AccessibilityService.shared.prefetch(for: app)
    }

    func setTemporarilyDisabled(_ disabled: Bool) {
        guard isActive else { return }
        guard isTemporarilyDisabled != disabled else { return }
        isTemporarilyDisabled = disabled
        updateOverlayVisibility()
    }

    func handleFnKeyChanged(isPressed: Bool) {
        guard isActive else { return }
        Log.info("[Fn] handleFnKeyChanged: isPressed=\(isPressed), isTemporarilyDisabled=\(isTemporarilyDisabled)")
        guard isFnPressed != isPressed else { return }
        isFnPressed = isPressed
        updateOverlayVisibility()
    }

    private func updateOverlayVisibility() {
        let isVisible = !isTemporarilyDisabled && !isFnPressed
        overlayController.setOverlayVisible(isVisible)
        onVisibilityChange?(isVisible)
    }

    func handleShiftKeyChanged(isPressed: Bool) {
        guard isActive else { return }
        Log.info("[Shift] handleShiftKeyChanged: isPressed=\(isPressed), isTemporarilyDisabled=\(isTemporarilyDisabled)")
        if isPressed {
            let now = CACurrentMediaTime()
            let diff = now - lastShiftPressTime
            Log.info("[Shift] diff=\(diff)")
            if diff < 0.5 {
                Log.info("[Shift] Double tap detected! Toggle to \(!isTemporarilyDisabled)")
                setTemporarilyDisabled(!isTemporarilyDisabled)
                lastShiftPressTime = 0
            } else {
                lastShiftPressTime = now
            }
        }
    }

    func handleKeyPress(_ key: String, keyCode: UInt16, isRepeat: Bool, modifiers: KeyModifiers) -> Bool {
        guard isActive else { return false }
        
        // Reset shift tap history on any keypress to avoid interference
        lastShiftPressTime = 0
        
        guard !isTemporarilyDisabled && !isFnPressed else { return false }

        // If we are in nudge-drag mode, we capture WASD, Arrow keys, and Enter
        if isNudgeDragging {
            if handleNudgeKeyPress(keyCode: keyCode, modifiers: modifiers) {
                return true
            }
            // Ignore other key presses while nudge dragging
            return true
        }

        guard !key.isEmpty else { return false }

        // If it's a repeated keyDown (held down), ignore it
        if isRepeat {
            return true
        }

        // Determine action from modifiers (sticky: once set, stays for this activation)
        // Only update if not already in a drag sequence (waiting for target)
        if dragSourcePoint == nil {
            if modifiers.option {
                pendingAction = .click // drag is handled specially, pendingAction stays .click
                // We'll detect drag via modifiers at activation time
            }
            if modifiers.command {
                pendingAction = .doubleClick
            } else if modifiers.control {
                pendingAction = .hover
            } else if modifiers.shift {
                pendingAction = .rightClick
            }
        }

        let isDragIntent = modifiers.option && dragSourcePoint == nil

        currentlyHeldKey = key.uppercased()

        pendingTimer?.invalidate()
        pendingTimer = nil

        typedPrefix += key.uppercased()

        let matches = currentCandidates.filter { $0.label.hasPrefix(typedPrefix) }

        let exactMatch = matches.first { $0.label == typedPrefix }
        let longerMatches = matches.filter { $0.label.count > typedPrefix.count }

        // Case 1: Exact match and NO longer labels share this prefix → activate now
        if let exactMatch, longerMatches.isEmpty {
            if isDragIntent {
                beginNudgeDragFrom(exactMatch)
            } else {
                activateElement(exactMatch, action: pendingAction)
            }
            return true
        }

        // Case 2: Only one match left → activate it (if autoClick is enabled)
        if matches.count == 1, let only = matches.first {
            if AppSettings.shared.autoClick {
                if isDragIntent {
                    beginNudgeDragFrom(only)
                } else {
                    activateElement(only, action: pendingAction)
                }
                return true
            } else {
                // autoClick disabled: show the single remaining label, let user confirm
                currentCandidates = matches
                overlayController.showLabels(for: matches)
                SoundManager.shared.playKeyPress()
                return true
            }
        }

        // Case 3: Exact match exists but longer matches also exist
        // Show filtered labels, but do NOT start the auto-activate timer yet (wait for key release).
        if exactMatch != nil, !longerMatches.isEmpty {
            currentCandidates = matches
            overlayController.showLabels(for: matches)
            SoundManager.shared.playKeyPress()
            return true
        }

        // Case 4: No exact match, multiple prefix matches → filter and wait
        if !matches.isEmpty {
            currentCandidates = matches
            overlayController.showLabels(for: matches)
            SoundManager.shared.playKeyPress()
            return true
        }

        // Case 5: No match at all → reset
        typedPrefix = ""
        currentCandidates = allElements
        overlayController.showLabels(for: allElements)
        SoundManager.shared.playKeyMiss()
        return true
    }

    func handleKeyUp(_ key: String, keyCode: UInt16) {
        guard !isTemporarilyDisabled && !isFnPressed else { return }
        let upperKey = key.uppercased()
        guard upperKey == currentlyHeldKey else { return }
        currentlyHeldKey = nil

        // When the held key is released, if there is an exact match for typedPrefix,
        // and there are still longer matches, we start the 400ms auto-activation timer.
        let matches = currentCandidates.filter { $0.label.hasPrefix(typedPrefix) }
        let exactMatch = matches.first { $0.label == typedPrefix }
        let longerMatches = matches.filter { $0.label.count > typedPrefix.count }

        if exactMatch != nil, !longerMatches.isEmpty {
            let prefixCopy = typedPrefix
            let action = pendingAction
            pendingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if let elem = self.currentCandidates.first(where: { $0.label == prefixCopy }) {
                    self.activateElement(elem, action: action)
                }
            }
        }
    }

    // MARK: - Element Activation

    private func activateElement(_ element: UIElement, action: ClickAction = .click) {
        let actionName: String
        switch action {
        case .click: actionName = "Click"
        case .rightClick: actionName = "Right-click"
        case .doubleClick: actionName = "Double-click"
        case .hover: actionName = "Hover"
        }
        Log.info("\(actionName): \(element.title) [\(element.label)]")

        overlayController.animateActivation(of: element.label) { [weak self] in
            guard let self = self else { return }
            element.performAction(action)

            // Reset typing state
            self.typedPrefix = ""
            self.pendingAction = .click

            if AppSettings.shared.chainClicks {
                // Chain mode: stay in hint mode, refresh labels
                self.currentCandidates = self.allElements
                self.overlayController.showLabels(for: self.allElements)

                // Refresh the labels after a short delay to allow target app to update its AX tree
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self = self, self.isActive else { return }
                    AccessibilityService.shared.clearCache(for: self.activePID)
                    self.refreshLabelsAsync(isInitialLoad: false)
                }
            } else {
                // Normal: exit to idle after action
                NotificationCenter.default.post(name: .hintModeDidClick, object: nil)
            }
        }
    }

    // MARK: - Nudge Drag Mode

    private func beginNudgeDragFrom(_ element: UIElement) {
        Log.info("Nudge drag start: \(element.title) [\(element.label)]")

        overlayController.animateActivation(of: element.label) { [weak self] in
            guard let self = self else { return }

            self.overlayController.dismissAll()

            // Begin the drag (mouseDown at source)
            element.beginDrag()
            self.dragSourcePoint = element.centerPoint
            self.nudgeDragPoint = element.centerPoint
            self.isNudgeDragging = true
            SoundManager.shared.playActivate()

            let frameSize = element.frame.size
            self.nudgeDragSize = CGSize(width: max(40, frameSize.width), height: max(40, frameSize.height))
            self.overlayController.showDragHighlight(at: self.nudgeDragPoint, size: self.nudgeDragSize)
            
            // Post notification to update global ModeIndicator
            NotificationCenter.default.post(name: .nudgeDragDidStart, object: nil)

            Log.info("Nudge drag: start nudging with Arrow keys/WASD and Enter to drop...")
        }
    }

    private func completeNudgeDrag() {
        guard let _ = dragSourcePoint else { return }
        Log.info("Nudge drag end at point: \(nudgeDragPoint)")

        // Complete the drag (mouseUp at current location)
        if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                 mouseCursorPosition: nudgeDragPoint, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
        
        self.dragSourcePoint = nil
        self.isNudgeDragging = false
        SoundManager.shared.playActivate()

        // Clean up visual overlay
        overlayController.hideDragHighlight()

        // Reset and exit
        self.typedPrefix = ""
        self.pendingAction = .click
        self.currentCandidates = self.allElements
        NotificationCenter.default.post(name: .hintModeDidClick, object: nil)
    }

    private func handleNudgeKeyPress(keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        
        let step: CGFloat = modifiers.shift ? 60.0 : 15.0
        
        switch keyCode {
        case keyUpArrow, keyW:
            dy = -step
        case keyDownArrow, keyS:
            dy = step
        case keyLeftArrow, keyA:
            dx = -step
        case keyRightArrow, keyD:
            dx = step
        case keyReturn:
            completeNudgeDrag()
            return true
        default:
            return false
        }
        
        if dx != 0 || dy != 0 {
            nudgeDragPoint.x += dx
            nudgeDragPoint.y += dy
            
            nudgeDragPoint = clampToScreen(nudgeDragPoint)
            
            UIElement.dragTo(point: nudgeDragPoint)
            
            overlayController.showDragHighlight(at: nudgeDragPoint, size: nudgeDragSize)
            return true
        }
        
        return false
    }

    private func clampToScreen(_ point: CGPoint) -> CGPoint {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let clampedX = max(screen.minX, min(screen.maxX, point.x))
        let clampedY = max(0, min(screen.height, point.y))
        return CGPoint(x: clampedX, y: clampedY)
    }

    /// Dismiss loading indicator, respecting minimum display time for UX consistency.
    /// If loading completed in < minLoadingDisplayTime, delay the dismissal so the
    /// indicator doesn't flash on screen too briefly (which looks glitchy).
    private func finishLoadingIfNeeded() {
        let elapsed = CACurrentMediaTime() - loadingStartTime
        let remaining = HintMode.minLoadingDisplayTime - elapsed

        if remaining > 0 {
            // Loading was too fast — keep indicator visible for minimum time
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                guard let self = self, self.isActive else { return }
                NotificationCenter.default.post(name: .hintModeLoadingDidEnd, object: nil)
            }
        } else {
            // Loading took long enough — dismiss immediately
            NotificationCenter.default.post(name: .hintModeLoadingDidEnd, object: nil)
        }
    }

    // MARK: - Background Refresh

    /// Scan AX tree on background thread, then show labels on main thread
    private func refreshLabelsAsync(isInitialLoad: Bool) {
        HintMode.scanQueue.async { [weak self] in
            guard let self = self, self.isActive else { return }

            // Phase 1: fast scan — frontmost app window only (~30-50ms)
            let appElements = AccessibilityService.shared.getActionableElements()

            DispatchQueue.main.async {
                guard self.isActive else { return }

                let labeled = KeyMapper.assignLabels(to: appElements, for: self.activeBundleID)
                self.allElements = labeled
                
                if self.typedPrefix.isEmpty {
                    self.currentCandidates = labeled
                    self.overlayController.showLabels(for: labeled)
                } else {
                    let matches = labeled.filter { $0.label.hasPrefix(self.typedPrefix) }
                    self.currentCandidates = matches
                    self.overlayController.showLabels(for: matches)
                }
                Log.info("Hint mode: refreshed \(labeled.count) elements")

                AccessibilityService.shared.saveHintSnapshot(
                    elements: appElements,
                    bundleID: self.activeBundleID
                )

                if isInitialLoad {
                    self.finishLoadingIfNeeded()
                }
            }

            // Phase 2: slow scan — Dock + status bar overlays, merged after fast scan shows (~100-200ms)
            let overlays = AccessibilityService.shared.getSystemOverlayElements()
            guard !overlays.isEmpty else { return }

            DispatchQueue.main.async {
                guard self.isActive else { return }
                let merged = self.allElements + KeyMapper.assignLabels(to: overlays, for: self.activeBundleID)
                self.allElements = merged
                
                if self.typedPrefix.isEmpty {
                    self.currentCandidates = merged
                    self.overlayController.showLabels(for: merged)
                } else {
                    let matches = merged.filter { $0.label.hasPrefix(self.typedPrefix) }
                    self.currentCandidates = matches
                    self.overlayController.showLabels(for: matches)
                }
            }
        }
    }
}
