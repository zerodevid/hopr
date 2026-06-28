import Cocoa

final class OverlayWindowController {

    private var mainWindow: NSWindow?
    private var scrollWindows: [NSWindow] = []
    private var modeLabelWindow: NSWindow?
    private var highlightBoxView: HighlightBoxView?
    private var focusBoxWindow: NSWindow?
    private static var hudNotificationWindow: NSWindow?

    /// Show all labels in ONE window — much faster than N windows
    func showLabels(for elements: [UIElement]) {
        dismissAll()

        guard !elements.isEmpty else { return }

        // Map elements to their screen frames to avoid repeated coordinate calculations.
        // `hasTitle` is precomputed once here rather than re-trimming the title string for
        // every (element × position × other element) inside the auto-placement penalty loop.
        let elementsWithFrames = elements.map {
            (elem: $0,
             frame: windowFrameFor($0),
             hasTitle: !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        // Calculate full screen bounds covering all elements
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = CGFloat.leastNonzeroMagnitude
        var maxY = CGFloat.leastNonzeroMagnitude

        for item in elementsWithFrames {
            let f = item.frame
            minX = min(minX, f.minX)
            minY = min(minY, f.minY)
            maxX = max(maxX, f.maxX)
            maxY = max(maxY, f.maxY)
        }

        // Create one big transparent panel covering all screens (multi-monitor support)
        var unionFrame = CGRect.null
        for screen in NSScreen.screens {
            unionFrame = unionFrame.union(screen.frame)
        }
        let screenFrame = unionFrame.isNull ? (NSScreen.main?.frame ?? NSScreen.screens[0].frame) : unionFrame
        
        let win = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false

        let container = NSView(frame: screenFrame)
        container.wantsLayer = true

        // Add all labels as subviews with smart positioning
        var placedFrames: [NSRect] = []

        for item in elementsWithFrames {
            let elem = item.elem
            let frame = item.frame

            // Find the local screen frame for correct boundary/positioning checks
            let elemCenter = CGPoint(x: frame.midX, y: frame.midY)
            let elementScreen = bestScreen(for: elemCenter) ?? NSScreen.main ?? NSScreen.screens[0]
            let localScreenFrame = elementScreen.frame
            let localMidX = localScreenFrame.midX
            let localMidY = localScreenFrame.midY
            let notch = notchRect(for: elementScreen)

            let position = determinePosition(
                for: elem,
                elemFrame: frame,
                allElementsWithFrames: elementsWithFrames,
                screenFrame: localScreenFrame,
                screenMidX: localMidX,
                screenMidY: localMidY,
                notchRect: notch
            )

            let labelView = LabelView(label: elem.label, position: position)
            let size = labelView.intrinsicContentSize

            let labelX: CGFloat
            let labelY: CGFloat

            switch position {
            case .above:
                labelX = frame.midX - size.width / 2
                labelY = frame.origin.y + frame.size.height + 1
            case .below:
                labelX = frame.midX - size.width / 2
                labelY = frame.origin.y - size.height - 1
            case .left:
                labelX = frame.origin.x - size.width - 1
                labelY = frame.midY - size.height / 2
            case .right:
                labelX = frame.origin.x + frame.size.width + 1
                labelY = frame.midY - size.height / 2
            }

            let proposedFrame = NSRect(
                x: labelX,
                y: labelY,
                width: size.width,
                height: size.height
            )

            var resolvedFrame = resolveOverlap(
                proposedFrame: proposedFrame,
                existingFrames: placedFrames,
                screenFrame: localScreenFrame,
                position: position
            )

            // Steer labels out from behind the MacBook notch (camera housing). A label
            // landing in this region is physically hidden, so drop it just below the
            // notch and re-resolve against already-placed labels.
            if let notch = notch, resolvedFrame.intersects(notch) {
                resolvedFrame.origin.y = notch.minY - resolvedFrame.size.height - 2
                resolvedFrame = resolveOverlap(
                    proposedFrame: resolvedFrame,
                    existingFrames: placedFrames,
                    screenFrame: localScreenFrame,
                    position: .below
                )
            }

            placedFrames.append(resolvedFrame)
            labelView.frame = resolvedFrame
            container.addSubview(labelView)
        }

        win.contentView = container
        
        let wasVisible = mainWindow != nil
        win.alphaValue = wasVisible ? 1.0 : 0.0
        win.orderFrontRegardless()
        mainWindow = win

        if !wasVisible {
            // Fresh open: fade window in and spring-animate each label
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().alphaValue = 1.0
            }, completionHandler: nil)
            for case let lv as LabelView in container.subviews {
                lv.animateIn()
            }
        }
        Self.bringHUDToFront()
    }

    /// Incremental filter for hint typing: keep the existing overlay and just hide the
    /// labels that no longer match, instead of tearing down and rebuilding every label
    /// view (and recomputing O(n²) placement + text measurement) on each keystroke.
    /// Matching labels keep their original positions, so hints don't jitter as you type.
    /// Falls back to a full rebuild if there's no overlay yet, or if a requested label
    /// isn't already on screen (e.g. the candidate set grew after a background refresh).
    func filterLabels(matching elements: [UIElement], typedPrefix: String = "") {
        guard let container = mainWindow?.contentView else {
            showLabels(for: elements)
            applyTypedPrefix(typedPrefix)
            return
        }
        let keep = Set(elements.map { $0.label })
        var present = Set<String>()
        for case let lv as LabelView in container.subviews {
            present.insert(lv.label)
            lv.isHidden = !keep.contains(lv.label)
        }
        if !keep.isSubset(of: present) {
            showLabels(for: elements)
        }
        applyTypedPrefix(typedPrefix)
    }

    private func applyTypedPrefix(_ prefix: String) {
        guard let container = mainWindow?.contentView else { return }
        for case let lv as LabelView in container.subviews where !lv.isHidden {
            let prevCount = lv.typedPrefix.count
            lv.typedPrefix = prefix
            // Pulse when a new char is added (label survived the filter)
            if !prefix.isEmpty && prefix.count > prevCount {
                lv.animatePulse()
            }
        }
    }

    func setOverlayVisible(_ visible: Bool) {
        guard let win = mainWindow else { return }
        if visible {
            win.alphaValue = 0.0
            win.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().alphaValue = 1.0
            }, completionHandler: nil)
            Self.bringHUDToFront()
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                win.animator().alphaValue = 0.0
            }) {
                win.orderOut(nil)
            }
        }
    }

    func animateActivation(of labelText: String, completion: @escaping () -> Void) {
        guard let container = mainWindow?.contentView else {
            completion()
            return
        }

        guard let targetLabelView = container.subviews.first(where: { ($0 as? LabelView)?.label == labelText }) as? LabelView else {
            completion()
            return
        }

        // Fade out all OTHER label views quickly
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            for subview in container.subviews {
                if subview !== targetLabelView {
                    subview.animator().alphaValue = 0.0
                }
            }
        }, completionHandler: nil)

        // Animate target
        targetLabelView.animateHit {
            completion()
        }
    }

    /// Show labels with highlighted boxes around text input fields (Focus Text mode)
    func showFocusModeOverlays(for elements: [UIElement]) {
        showLabels(for: elements)
        guard !elements.isEmpty else { return }

        let elementsWithFrames = elements.map { (elem: $0, frame: windowFrameFor($0)) }

        // Create one window for all boxes
        var unionFrame = CGRect.null
        for screen in NSScreen.screens {
            unionFrame = unionFrame.union(screen.frame)
        }
        let screenFrame = unionFrame.isNull ? (NSScreen.main?.frame ?? NSScreen.screens[0].frame) : unionFrame

        let win = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false

        let container = NSView(frame: screenFrame)
        container.wantsLayer = true

        for item in elementsWithFrames {
            let boxView = TextInputBoxView(frame: item.frame)
            boxView.alphaValue = 0.0
            container.addSubview(boxView)

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                boxView.animator().alphaValue = 1.0
            }, completionHandler: nil)
        }

        win.contentView = container
        win.alphaValue = 1.0
        win.orderFrontRegardless()
        focusBoxWindow = win
    }

    func dismissFocusBoxes() {
        guard let win = focusBoxWindow else { return }
        focusBoxWindow = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0.0
        }) {
            win.orderOut(nil)
        }
    }

    func dismissAll() {
        dismissFocusBoxes()
        if let mainWin = mainWindow {
            mainWindow = nil
            highlightBoxView = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                mainWin.animator().alphaValue = 0.0
            }) {
                mainWin.orderOut(nil)
            }
        }
        
        let oldScrollWindows = scrollWindows
        scrollWindows.removeAll()
        for win in oldScrollWindows {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                win.animator().alphaValue = 0.0
            }) {
                win.orderOut(nil)
            }
        }
        
        if let modeWin = modeLabelWindow {
            modeLabelWindow = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                modeWin.animator().alphaValue = 0.0
            }) {
                modeWin.orderOut(nil)
            }
        }
    }

    // MARK: - Scroll Area Overlays

    func showScrollAreaOverlays(for areas: [ScrollableArea]) {
        dismissAll()
        for area in areas {
            let boxView = ScrollAreaBoxView(number: area.number)
            let window = createOverlayWindow(frame: area.screenFrame)
            window.contentView = boxView
            window.alphaValue = 0.0
            window.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
            }, completionHandler: nil)
            
            scrollWindows.append(window)
        }
        Self.bringHUDToFront()
    }

    func showSelectedScrollArea(_ selected: ScrollableArea, allAreas: [ScrollableArea]) {
        for win in scrollWindows {
            guard let boxView = win.contentView as? ScrollAreaBoxView else { continue }
            
            let isSelected = (boxView.number == selected.number)
            boxView.setHighlighted(isSelected)
            
            let targetAlpha: CGFloat = isSelected ? 1.0 : 0.25
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().alphaValue = targetAlpha
            }, completionHandler: nil)
        }
        
        if let mainWin = mainWindow {
            mainWindow = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                mainWin.animator().alphaValue = 0.0
            }) {
                mainWin.orderOut(nil)
            }
        }
    }

    // MARK: - Mode Label

    func showModeLabel(_ text: String, color: NSColor = .systemGreen) {
        let view = NSTextField(frame: .zero)
        view.stringValue = text
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        view.textColor = .white
        view.isEditable = false
        view.isBezeled = false
        view.drawsBackground = false
        view.sizeToFit()

        let padding: CGFloat = 20
        let panelWidth = view.frame.width + padding * 2
        let panelHeight: CGFloat = 32

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = color.withAlphaComponent(0.85)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 8

        view.frame.origin = NSPoint(x: padding, y: (panelHeight - view.frame.height) / 2)
        panel.contentView?.addSubview(view)

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: sf.midX - panelWidth / 2,
                y: sf.maxY - 42
            ))
        }

        panel.orderFrontRegardless()
        modeLabelWindow = panel
    }

    static func showHUDNotification(mode: AppMode) {
        dismissHUDNotification()
        
        guard AppSettings.shared.showModeNotification else { return }
        
        let title: String
        let subtitle: String
        let iconName: String
        let accentColor: NSColor
        
        switch mode {
        case .idle:
            return
        case .hint:
            title = "Hint Mode"
            subtitle = AppSettings.shared.hintShortcut.displayString
            iconName = "keyboard"
            accentColor = NSColor(hex: AppSettings.shared.labelBgColorHex) ?? .systemYellow
        case .scroll:
            title = "Scroll Mode"
            subtitle = AppSettings.shared.scrollShortcut.displayString
            iconName = "arrow.up.and.down"
            accentColor = .systemGreen
        case .mouse:
            title = "Mouse Mode"
            subtitle = AppSettings.shared.mouseShortcut.displayString
            iconName = "computermouse"
            accentColor = .systemBlue
        case .search:
            title = "Search Mode"
            subtitle = AppSettings.shared.searchShortcut.displayString
            iconName = "magnifyingglass"
            accentColor = .systemPurple
        case .focusText:
            title = "Focus Text"
            subtitle = AppSettings.shared.focusTextShortcut.displayString
            iconName = "text.cursor"
            accentColor = .systemCyan
        }
        
        let panelWidth: CGFloat = 280
        let panelHeight: CGFloat = 76
        
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        
        let targetFrame = NSRect(
            x: sf.midX - panelWidth / 2,
            y: sf.minY + 28, // Just above the Dock top boundary
            width: panelWidth,
            height: panelHeight
        )
        
        let panel = NSPanel(
            contentRect: targetFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        
        let contentView = NSView(frame: NSRect(origin: .zero, size: targetFrame.size))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 16
        contentView.layer?.masksToBounds = true
        
        let ve = NSVisualEffectView(frame: contentView.bounds)
        ve.autoresizingMask = [.width, .height]
        ve.material = .hudWindow
        ve.state = .active
        ve.blendingMode = .behindWindow
        contentView.addSubview(ve)
        
        // Dynamic border outline
        let borderView = NSView(frame: contentView.bounds)
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 16
        borderView.layer?.borderWidth = 1.5
        borderView.layer?.borderColor = accentColor.withAlphaComponent(0.45).cgColor
        contentView.addSubview(borderView)
        
        // Large SF Symbol icon
        let iconView = NSImageView(frame: NSRect(x: 18, y: (panelHeight - 32) / 2, width: 32, height: 32))
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(config)
            iconView.contentTintColor = accentColor
        }
        contentView.addSubview(iconView)
        
        // Title Text
        let textX = iconView.frame.maxX + 14
        let titleField = NSTextField(frame: NSRect(x: textX, y: 36, width: panelWidth - textX - 18, height: 22))
        titleField.stringValue = title
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleField.textColor = .white
        titleField.isEditable = false
        titleField.isBezeled = false
        titleField.drawsBackground = false
        contentView.addSubview(titleField)
        
        // Shortcut Subtitle
        let subField = NSTextField(frame: NSRect(x: textX, y: 16, width: panelWidth - textX - 18, height: 18))
        subField.stringValue = subtitle
        subField.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        subField.textColor = NSColor.secondaryLabelColor
        subField.isEditable = false
        subField.isBezeled = false
        subField.drawsBackground = false
        contentView.addSubview(subField)
        
        panel.contentView = contentView
        
        // Animate Fade-In
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }, completionHandler: nil)
        
        hudNotificationWindow = panel
        
        // Auto dismiss after 1.0 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak panel] in
            guard let panel = panel, hudNotificationWindow === panel else { return }
            dismissHUDNotification()
        }
    }

    static func dismissHUDNotification() {
        guard let panel = hudNotificationWindow else { return }
        hudNotificationWindow = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }) {
            panel.orderOut(nil)
        }
    }

    static func bringHUDToFront() {
        if let panel = hudNotificationWindow, panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func highlightElement(_ element: UIElement?) {
        guard let container = mainWindow?.contentView else { return }
        
        guard let element = element else {
            if let box = highlightBoxView {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.12
                    box.animator().alphaValue = 0.0
                }) {
                    box.removeFromSuperview()
                }
                highlightBoxView = nil
            }
            return
        }
        
        let targetFrame = windowFrameFor(element)
        
        if let box = highlightBoxView {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                box.animator().frame = targetFrame
            }, completionHandler: nil)
        } else {
            let box = HighlightBoxView(frame: targetFrame)
            box.alphaValue = 0.0
            container.addSubview(box)
            highlightBoxView = box
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                box.animator().alphaValue = 1.0
            }, completionHandler: nil)
        }
    }

    func showDragHighlight(at point: CGPoint, size: CGSize) {
        guard let container = mainWindow?.contentView else { return }
        
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
        
        let frameX = point.x - size.width / 2
        let flippedY = primaryHeight - point.y - size.height / 2
        let targetFrame = NSRect(x: frameX, y: flippedY, width: size.width, height: size.height)
        
        if let box = highlightBoxView {
            box.showBadge = true
            box.badgeText = "WASD"
            box.frame = targetFrame
            box.alphaValue = 1.0
        } else {
            let box = HighlightBoxView(frame: targetFrame, showBadge: true, badgeText: "WASD")
            box.alphaValue = 0.0
            container.addSubview(box)
            highlightBoxView = box
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.08
                box.animator().alphaValue = 1.0
            }, completionHandler: nil)
        }
    }

    func hideDragHighlight() {
        if let box = highlightBoxView {
            box.removeFromSuperview()
            highlightBoxView = nil
        }
    }


    // MARK: - Helpers

    private func determinePosition(
        for elem: UIElement,
        elemFrame: NSRect,
        allElementsWithFrames: [(elem: UIElement, frame: NSRect, hasTitle: Bool)],
        screenFrame: NSRect,
        screenMidX: CGFloat,
        screenMidY: CGFloat,
        notchRect: NSRect?
    ) -> LabelPosition {
        let placement = AppSettings.shared.hintPlacement
        
        switch placement {
        case "left":
            return .left
        case "right":
            return .right
        case "leftRight":
            return elemFrame.midX < screenMidX ? .left : .right
        case "aboveBelow":
            return elemFrame.midY > screenMidY ? .below : .above
        case "auto":
            // Smart Auto: Calculate collision penalties for all 4 positions and pick the best one.
            let positions: [LabelPosition] = [.above, .below, .left, .right]
            var bestPosition: LabelPosition = .above
            var minPenalty: CGFloat = CGFloat.greatestFiniteMagnitude
            
            for pos in positions {
                let size = LabelMetrics.labelSize(for: elem.label, position: pos)
                
                // Calculate proposed frame
                let labelX: CGFloat
                let labelY: CGFloat
                switch pos {
                case .above:
                    labelX = elemFrame.midX - size.width / 2
                    labelY = elemFrame.origin.y + elemFrame.size.height + 1
                case .below:
                    labelX = elemFrame.midX - size.width / 2
                    labelY = elemFrame.origin.y - size.height - 1
                case .left:
                    labelX = elemFrame.origin.x - size.width - 1
                    labelY = elemFrame.midY - size.height / 2
                case .right:
                    labelX = elemFrame.origin.x + elemFrame.size.width + 1
                    labelY = elemFrame.midY - size.height / 2
                }
                
                let proposed = NSRect(x: labelX, y: labelY, width: size.width, height: size.height)
                var penalty: CGFloat = 0.0
                
                // 1. Boundary penalty
                if proposed.minX < screenFrame.minX {
                    penalty += 1000 + (screenFrame.minX - proposed.minX) * 10
                }
                if proposed.maxX > screenFrame.maxX {
                    penalty += 1000 + (proposed.maxX - screenFrame.maxX) * 10
                }
                if proposed.minY < screenFrame.minY {
                    penalty += 1000 + (screenFrame.minY - proposed.minY) * 10
                }
                if proposed.maxY > screenFrame.maxY {
                    penalty += 1000 + (proposed.maxY - screenFrame.maxY) * 10
                }
                
                // 1b. Notch penalty: a label drawn behind the camera housing is hidden.
                if let notch = notchRect, proposed.intersects(notch) {
                    penalty += 5000
                }

                // 2. Overlap penalty with other elements' bounding boxes (especially text/titles)
                for other in allElementsWithFrames {
                    if other.elem.id == elem.id { continue }
                    let otherFrame = other.frame
                    
                    if proposed.intersects(otherFrame) {
                        if other.hasTitle {
                            // Heavy penalty for covering text
                            penalty += 3000
                        } else {
                            // Medium penalty for covering icons/buttons
                            penalty += 300
                        }
                    }
                }
                
                // 3. Size/Aspect ratio bias
                let isWide = elemFrame.size.width > elemFrame.size.height * 1.4
                if isWide {
                    // Bias towards left/right for wide elements
                    if pos == .above || pos == .below {
                        penalty += 150
                    }
                } else {
                    // Bias towards above/below for square/tall elements
                    if pos == .left || pos == .right {
                        penalty += 150
                    }
                }
                
                // 4. Subtle placement preferences as tie-breakers
                switch pos {
                case .above:
                    break // most preferred
                case .below:
                    penalty += 5
                case .right:
                    penalty += 10 // prioritized over left
                case .left:
                    penalty += 15
                }
                
                if penalty < minPenalty {
                    minPenalty = penalty
                    bestPosition = pos
                }
            }
            return bestPosition
            
        default:
            return elemFrame.midY > screenMidY ? .below : .above
        }
    }

    private func createOverlayWindow(frame: NSRect) -> NSWindow {
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        return window
    }

    private func windowFrameFor(_ element: UIElement) -> NSRect {
        let axFrame = element.frame
        // AX coordinates always use the primary screen's height as the Y-axis reference.
        // Using a secondary screen's height here produces wrong label positions when
        // monitors have different resolutions (e.g. primary 1080p + secondary 1440p).
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
        let flippedY = primaryHeight - axFrame.origin.y - axFrame.size.height
        return NSRect(
            x: axFrame.origin.x,
            y: flippedY,
            width: axFrame.size.width,
            height: axFrame.size.height
        )
    }

    /// The rectangle occupied by the camera housing ("notch") on screens that have one,
    /// in global (bottom-left origin) coordinates matching `screen.frame`. Returns nil
    /// for screens without a notch. Labels overlapping this region are physically hidden.
    private func notchRect(for screen: NSScreen) -> NSRect? {
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        let notchWidth = right.minX - left.maxX
        guard notchWidth > 0 else { return nil }
        return NSRect(
            x: left.maxX,
            y: screen.frame.maxY - inset,
            width: notchWidth,
            height: inset
        )
    }

    private func bestScreen(for point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return NSScreen.screens.min(by: { s1, s2 in
            let d1 = hypot(s1.frame.midX - point.x, s1.frame.midY - point.y)
            let d2 = hypot(s2.frame.midX - point.x, s2.frame.midY - point.y)
            return d1 < d2
        })
    }

    /// Resolve overlapping label views by shifting them horizontally or vertically
    private func resolveOverlap(
        proposedFrame: NSRect,
        existingFrames: [NSRect],
        screenFrame: NSRect,
        position: LabelPosition
    ) -> NSRect {
        var resolved = proposedFrame
        let gap: CGFloat = 2.0
        
        // Loop up to 10 times to resolve multi-way overlaps
        for _ in 0..<10 {
            var overlapFound = false
            for existing in existingFrames {
                if resolved.intersects(existing) {
                    if position == .above || position == .below {
                        // Try to shift right
                        let shiftRight = NSRect(
                            x: existing.maxX + gap,
                            y: resolved.origin.y,
                            width: resolved.size.width,
                            height: resolved.size.height
                        )
                        
                        if shiftRight.maxX <= screenFrame.maxX {
                            resolved = shiftRight
                            overlapFound = true
                            break
                        }
                        
                        // Try to shift left
                        let shiftLeft = NSRect(
                            x: existing.minX - resolved.size.width - gap,
                            y: resolved.origin.y,
                            width: resolved.size.width,
                            height: resolved.size.height
                        )
                        if shiftLeft.minX >= screenFrame.minX {
                            resolved = shiftLeft
                            overlapFound = true
                            break
                        }
                        
                        // Try to shift vertically (further away from the element)
                        let shiftVertical: NSRect
                        if position == .above {
                            shiftVertical = NSRect(
                                x: resolved.origin.x,
                                y: existing.maxY + gap,
                                width: resolved.size.width,
                                height: resolved.size.height
                            )
                        } else {
                            shiftVertical = NSRect(
                                x: resolved.origin.x,
                                y: existing.minY - resolved.size.height - gap,
                                width: resolved.size.width,
                                height: resolved.size.height
                            )
                        }
                        resolved = shiftVertical
                        overlapFound = true
                        break
                    } else {
                        // For .left and .right, try vertical shifts first to preserve horizontal layout
                        // Try to shift up
                        let shiftUp = NSRect(
                            x: resolved.origin.x,
                            y: existing.maxY + gap,
                            width: resolved.size.width,
                            height: resolved.size.height
                        )
                        if shiftUp.maxY <= screenFrame.maxY {
                            resolved = shiftUp
                            overlapFound = true
                            break
                        }
                        
                        // Try to shift down
                        let shiftDown = NSRect(
                            x: resolved.origin.x,
                            y: existing.minY - resolved.size.height - gap,
                            width: resolved.size.width,
                            height: resolved.size.height
                        )
                        if shiftDown.minY >= screenFrame.minY {
                            resolved = shiftDown
                            overlapFound = true
                            break
                        }
                        
                        // Try to shift horizontally (further away from the element)
                        let shiftHorizontal: NSRect
                        if position == .left {
                            shiftHorizontal = NSRect(
                                x: existing.minX - resolved.size.width - gap,
                                y: resolved.origin.y,
                                width: resolved.size.width,
                                height: resolved.size.height
                            )
                        } else {
                            shiftHorizontal = NSRect(
                                x: existing.maxX + gap,
                                y: resolved.origin.y,
                                width: resolved.size.width,
                                height: resolved.size.height
                            )
                        }
                        resolved = shiftHorizontal
                        overlapFound = true
                        break
                    }
                }
            }
            if !overlapFound {
                break
            }
        }
        
        // Final screen bounds clamping
        resolved.origin.x = max(screenFrame.minX, min(screenFrame.maxX - resolved.size.width, resolved.origin.x))
        resolved.origin.y = max(screenFrame.minY, min(screenFrame.maxY - resolved.size.height, resolved.origin.y))
        
        return resolved
    }
}

// MARK: - HighlightBoxView

class HighlightBoxView: NSView {
    var showBadge: Bool = false {
        didSet { needsDisplay = true }
    }
    var badgeText: String = "WASD" {
        didSet { needsDisplay = true }
    }

    init(frame frameRect: NSRect, showBadge: Bool = false, badgeText: String = "WASD") {
        self.showBadge = showBadge
        self.badgeText = badgeText
        super.init(frame: frameRect)
        wantsLayer = true
        
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.6)
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 8.0
        self.shadow = shadow
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let borderRect = bounds.insetBy(dx: 1, dy: 1)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 6, yRadius: 6)
        
        let accentColor = NSColor.controlAccentColor
        
        // Subtle fill when badge is shown (like scrollmode highlighted)
        if showBadge {
            accentColor.withAlphaComponent(0.08).setFill()
            borderPath.fill()
        }
        
        // Border
        accentColor.withAlphaComponent(0.85).setStroke()
        borderPath.lineWidth = showBadge ? 2.5 : 3.0
        borderPath.stroke()
        
        // Draw native pill badge exactly like ScrollAreaBoxView
        if showBadge {
            let badgeFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            let badgeTextSize = (badgeText as NSString).size(withAttributes: [.font: badgeFont])
            let badgeW = badgeTextSize.width + 12
            let badgeH: CGFloat = 16
            
            // Native pill coordinates in top-left
            let badgeRect = NSRect(x: 6, y: bounds.height - badgeH - 6, width: badgeW, height: badgeH)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2)
            
            accentColor.setFill()
            badgePath.fill()
            
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor.white,
            ]
            let textPoint = NSPoint(
                x: badgeRect.midX - badgeTextSize.width / 2,
                y: badgeRect.midY - badgeTextSize.height / 2 - 0.5
            )
            (badgeText as NSString).draw(at: textPoint, withAttributes: textAttrs)
        }
    }
}

// MARK: - TextInputBoxView

/// Rounded box drawn around text input fields in Focus Text mode.
/// Cyan border + subtle background fill to make fields visually obvious.
class TextInputBoxView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.systemCyan.withAlphaComponent(0.5)
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 10.0
        self.shadow = shadow
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderRect = bounds.insetBy(dx: 1, dy: 1)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 6, yRadius: 6)

        let cyan = NSColor.systemCyan

        // Subtle background fill
        cyan.withAlphaComponent(0.06).setFill()
        borderPath.fill()

        // Border
        cyan.withAlphaComponent(0.75).setStroke()
        borderPath.lineWidth = 2.0
        borderPath.stroke()
    }
}

