import Cocoa
import Carbon.HIToolbox

final class SearchMode: NSObject, NSTextFieldDelegate {

    private let overlayController = OverlayWindowController()
    private var searchPanel: NSPanel?
    private var searchField: NSTextField?
    private var countLabel: NSTextField?
    private var rowContainer: NSView?
    private var allElements: [UIElement] = []
    private var filteredElements: [UIElement] = []
    private var selectedIndex = 0
    private var firstVisibleIndex = 0
    private var previouslyActiveApp: NSRunningApplication?

    func activate() {
        let currentApp = NSWorkspace.shared.frontmostApplication
        previouslyActiveApp = currentApp
        let currentPID = currentApp?.processIdentifier ?? 0
        let currentBundleID = currentApp?.bundleIdentifier ?? "unknown"

        selectedIndex = 0
        firstVisibleIndex = 0

        // Show search bar immediately to the user
        showSearchBar()
        SoundManager.shared.playEnterMode()

        if let prefetched = AccessibilityService.shared.consumePrefetchedElements(for: currentPID) {
            allElements = KeyMapper.assignLabels(to: prefetched.elements, for: prefetched.bundleID)
            filteredElements = allElements
            countLabel?.stringValue = "\(allElements.count) items"
            overlayController.showLabels(for: filteredElements)
            updateSelection()
            Log.info("Search mode: instant show \(allElements.count) elements (prefetched)")
            
            refreshElementsAsync(currentApp: currentApp, currentBundleID: currentBundleID)
        } else if let diskSnapshot = AccessibilityService.shared.loadHintSnapshot(for: currentBundleID) {
            allElements = KeyMapper.assignLabels(to: diskSnapshot, for: currentBundleID)
            filteredElements = allElements
            countLabel?.stringValue = "\(allElements.count) items (cached)"
            overlayController.showLabels(for: filteredElements)
            updateSelection()
            Log.info("Search mode: disk cache show \(allElements.count) elements (bundleID=\(currentBundleID))")
            
            refreshElementsAsync(currentApp: currentApp, currentBundleID: currentBundleID)
        } else {
            allElements = []
            filteredElements = []
            countLabel?.stringValue = "Scanning..."

            refreshElementsAsync(currentApp: currentApp, currentBundleID: currentBundleID)
        }
    }

    private func refreshElementsAsync(currentApp: NSRunningApplication?, currentBundleID: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.searchPanel != nil else { return }

            // Phase 1: fast scan — frontmost app only
            let elements = AccessibilityService.shared.getActionableElements(for: currentApp)
            let labeled = KeyMapper.assignLabels(to: elements, for: currentBundleID)

            DispatchQueue.main.async {
                guard self.searchPanel != nil else { return }
                self.allElements = labeled
                let currentQuery = self.searchField?.stringValue ?? ""
                self.filterElements(query: currentQuery)
                Log.info("Search mode: fast scan finished, found \(labeled.count) elements")
                
                // Save elements to disk cache so subsequent startups use them immediately
                AccessibilityService.shared.saveHintSnapshot(elements: elements, bundleID: currentBundleID)
            }

            // Phase 2: slow scan — system overlays, merge
            if elements.count > 2 {
                let overlays = AccessibilityService.shared.getSystemOverlayElements()
                if !overlays.isEmpty {
                    let overlayLabels = KeyMapper.assignLabels(to: overlays, for: currentBundleID)
                    DispatchQueue.main.async {
                        guard self.searchPanel != nil else { return }
                        // Filter out elements that are already present to prevent duplicates
                        var uniqueNew: [UIElement] = []
                        let existingIDs = Set(self.allElements.map { $0.id })
                        for item in overlayLabels {
                            if !existingIDs.contains(item.id) {
                                uniqueNew.append(item)
                            }
                        }
                        self.allElements.append(contentsOf: uniqueNew)
                        let currentQuery = self.searchField?.stringValue ?? ""
                        self.filterElements(query: currentQuery)
                    }
                }
            }
        }
    }

    func deactivate() {
        if let panel = searchPanel {
            self.searchPanel = nil
            self.searchField = nil
            self.countLabel = nil
            self.rowContainer = nil
            
            let currentFrame = panel.frame
            let targetFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + 15,
                width: currentFrame.size.width,
                height: currentFrame.size.height
            )
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
                panel.animator().setFrame(targetFrame, display: true)
            }) {
                panel.orderOut(nil)
            }
        }
        overlayController.dismissAll()
        allElements = []
        filteredElements = []
        selectedIndex = 0
        
        // Restore focus to the previously active app
        if let app = previouslyActiveApp {
            app.activate(options: [.activateIgnoringOtherApps])
            previouslyActiveApp = nil
        }
    }

    /// Handle key press in search mode. Returns true if key was consumed.
    func handleKeyPress(_ key: String, keyCode: UInt16, isRepeat: Bool) -> Bool {
        // Enter → activate selected element
        if keyCode == kVK_Return {
            if !filteredElements.isEmpty {
                let element = filteredElements[selectedIndex]
                Log.info("Activating: \(element.title)")
                
                // Hide search panel immediately so it doesn't block
                searchPanel?.orderOut(nil)
                searchPanel = nil
                
                overlayController.animateActivation(of: element.label) {
                    element.performAction()
                    NotificationCenter.default.post(name: .hintModeDidClick, object: nil)
                }
            } else {
                if !isRepeat {
                    SoundManager.shared.playKeyMiss()
                }
            }
            return true
        }

        // Arrow keys for selection
        if keyCode == kVK_DownArrow {
            if !filteredElements.isEmpty {
                selectedIndex = min(selectedIndex + 1, filteredElements.count - 1)
                updateSelection()
                if !isRepeat {
                    SoundManager.shared.playKeyPress()
                }
            } else {
                if !isRepeat {
                    SoundManager.shared.playKeyMiss()
                }
            }
            return true
        }
        if keyCode == kVK_UpArrow {
            if !filteredElements.isEmpty {
                selectedIndex = max(selectedIndex - 1, 0)
                updateSelection()
                if !isRepeat {
                    SoundManager.shared.playKeyPress()
                }
            } else {
                if !isRepeat {
                    SoundManager.shared.playKeyMiss()
                }
            }
            return true
        }

        // Let all other keys (typing, delete, shortcuts like Cmd+A, copy/paste, arrow left/right) pass through to the native text field
        return false
    }

    // MARK: - Private

    private func showSearchBar() {
        let panelWidth: CGFloat = 600
        let panelHeight: CGFloat = 60

        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bgView = SearchPanelContentView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))

        // Center on screen
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: sf.midX - panelWidth / 2,
                y: sf.midY + 80
            ))
        }

        // SF Symbol magnifier icon
        let iconView = NSImageView(frame: .zero)
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            iconView.image = img.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor.secondaryLabelColor
        }
        bgView.addSubview(iconView)
        bgView.searchIconView = iconView

        // Text field
        let field = NSTextField(frame: .zero)
        let customCell = CenteredTextFieldCell()
        customCell.isScrollable = true
        customCell.placeholderAttributedString = NSAttributedString(
            string: "Spotlight Search elements...",
            attributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .light),
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.6),
            ]
        )
        field.cell = customCell
        field.font = NSFont.systemFont(ofSize: 20, weight: .light)
        field.isBezeled = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = false
        field.textColor = NSColor.labelColor
        field.stringValue = ""
        field.delegate = self
        bgView.addSubview(field)
        bgView.searchField = field

        // Result count label
        let countLabel = NSTextField(frame: .zero)
        countLabel.stringValue = "\(allElements.count) items"
        countLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        countLabel.textColor = NSColor.tertiaryLabelColor
        countLabel.alignment = .right
        countLabel.isEditable = false
        countLabel.isBezeled = false
        countLabel.drawsBackground = false
        bgView.addSubview(countLabel)
        bgView.countLabel = countLabel

        // Separator
        let separator = NSView(frame: .zero)
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        separator.isHidden = true
        bgView.addSubview(separator)
        bgView.separatorView = separator

        // Row container
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.isHidden = true
        bgView.addSubview(container)
        bgView.rowContainer = container

        panel.contentView = bgView
        
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let targetFrame = NSRect(
                x: sf.midX - panelWidth / 2,
                y: sf.midY + 80,
                width: panelWidth,
                height: panelHeight
            )
            
            panel.alphaValue = 0.0
            panel.setFrame(NSRect(
                x: targetFrame.origin.x,
                y: targetFrame.origin.y + 15,
                width: targetFrame.size.width,
                height: targetFrame.size.height
            ), display: true)
            
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(field)
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
                panel.animator().setFrame(targetFrame, display: true)
            }, completionHandler: nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(field)
        }

        self.searchPanel = panel
        self.searchField = field
        self.countLabel = countLabel
        self.rowContainer = container
    }

    private func filterElements(query: String) {
        if query.isEmpty {
            filteredElements = allElements
            // Respect hideLabelsBeforeSearch: don't show labels until user types
            if AppSettings.shared.hideLabelsBeforeSearch {
                overlayController.dismissAll()
            } else {
                overlayController.showLabels(for: filteredElements)
            }
        } else {
            let lower = query.lowercased()
            let matches = allElements.filter {
                $0.title.lowercased().contains(lower) ||
                $0.role.lowercased().contains(lower) ||
                $0.label.lowercased().contains(lower)
            }
            
            filteredElements = matches.sorted { (e1, e2) -> Bool in
                let score1 = calculateRelevance(element: e1, query: query)
                let score2 = calculateRelevance(element: e2, query: query)
                if score1 != score2 {
                    return score1 > score2
                }
                return e1.title.count < e2.title.count
            }
        }
        selectedIndex = 0
        firstVisibleIndex = 0
        countLabel?.stringValue = "\(filteredElements.count) found"
        overlayController.showLabels(for: filteredElements)
        updateSelection()
    }

    private func calculateRelevance(element: UIElement, query: String) -> Double {
        let title = element.title
        let label = element.label
        let role = element.role
        
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanQuery.isEmpty { return 0 }
        
        let cleanTitle = sanitizeForRelevance(title)
        
        var score: Double = 0
        
        // 1. Exact match on title (cleaned)
        if cleanTitle == cleanQuery {
            score += 1000
        }
        // 2. Starts with query (cleaned)
        else if cleanTitle.hasPrefix(cleanQuery) {
            score += 500
            if !cleanTitle.isEmpty {
                score += Double(cleanQuery.count) / Double(cleanTitle.count) * 100
            }
        }
        // 3. Contains query (cleaned)
        else if cleanTitle.contains(cleanQuery) {
            score += 100
            // Word boundary match bonus
            if cleanTitle.hasPrefix(" " + cleanQuery) ||
               cleanTitle.contains(" " + cleanQuery) ||
               cleanTitle.contains("-" + cleanQuery) ||
               cleanTitle.contains("_" + cleanQuery) ||
               cleanTitle.contains("/" + cleanQuery) {
                score += 150
            }
            if !cleanTitle.isEmpty {
                score += Double(cleanQuery.count) / Double(cleanTitle.count) * 50
            }
        }
        
        // 4. Match in Hotkey Label
        if label.lowercased() == cleanQuery {
            score += 800
        }
        
        // 5. Match in Role
        let cleanRole = role.lowercased()
        if cleanRole.contains(cleanQuery) {
            score += 50
        }
        
        // 6. Actionable elements priority bonus
        let lowerRole = role.lowercased()
        if lowerRole.contains("button") || 
           lowerRole.contains("text") || 
           lowerRole.contains("menu") || 
           lowerRole.contains("link") {
            score += 10
        }
        
        return score
    }
    
    private func sanitizeForRelevance(_ str: String) -> String {
        var s = str.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("\"") || s.hasPrefix("'") || s.hasPrefix("`") {
            s.removeFirst()
        }
        while s.hasSuffix("\"") || s.hasSuffix("'") || s.hasSuffix("`") {
            s.removeLast()
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func updateSelection() {
        updateDropdownList()
        updatePanelHeight()
        
        let query = searchField?.stringValue ?? ""
        if !query.isEmpty && !filteredElements.isEmpty && selectedIndex < filteredElements.count {
            let element = filteredElements[selectedIndex]
            overlayController.highlightElement(element)
            Log.debug("Selected: \(element.title)")
        } else {
            overlayController.highlightElement(nil)
        }
    }

    private func updateDropdownList() {
        guard let container = rowContainer else { return }
        
        container.subviews.forEach { $0.removeFromSuperview() }
        
        let query = searchField?.stringValue ?? ""
        let rowsToShow = query.isEmpty ? 0 : min(filteredElements.count, 6)
        guard rowsToShow > 0 else { return }
        
        if selectedIndex < firstVisibleIndex {
            firstVisibleIndex = selectedIndex
        } else if selectedIndex >= firstVisibleIndex + 6 {
            firstVisibleIndex = selectedIndex - 5
        }
        
        firstVisibleIndex = max(0, min(firstVisibleIndex, filteredElements.count - rowsToShow))
        
        let rowHeight: CGFloat = 44
        for i in 0..<rowsToShow {
            let elementIndex = firstVisibleIndex + i
            guard elementIndex < filteredElements.count else { break }
            let element = filteredElements[elementIndex]
            let isSelected = elementIndex == selectedIndex
            
            let y = CGFloat(rowsToShow - 1 - i) * rowHeight
            
            let rowView = SearchResultRowView(
                frame: NSRect(x: 10, y: y + 4, width: container.bounds.width - 20, height: rowHeight - 8),
                element: element,
                isSelected: isSelected
            )
            container.addSubview(rowView)
        }
    }

    private func updatePanelHeight(animate: Bool = true) {
        guard let panel = searchPanel else { return }
        
        let query = searchField?.stringValue ?? ""
        let rowsToShow = query.isEmpty ? 0 : min(filteredElements.count, 6)
        let hasResults = rowsToShow > 0
        let newHeight = 60.0 + (hasResults ? (1.0 + CGFloat(rowsToShow) * 44.0) : 0.0)
        
        if let contentView = panel.contentView as? SearchPanelContentView {
            contentView.separatorView?.isHidden = !hasResults
            contentView.rowContainer?.isHidden = !hasResults
        }
        
        let currentFrame = panel.frame
        let heightDiff = newHeight - currentFrame.height
        
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y - heightDiff,
            width: currentFrame.size.width,
            height: newHeight
        )
        
        if animate {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(newFrame, display: true)
            }, completionHandler: nil)
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }
}

// MARK: - SearchPanelContentView

class SearchPanelContentView: NSView {
    var searchIconView: NSImageView?
    var searchField: NSTextField?
    var countLabel: NSTextField?
    var separatorView: NSView?
    var rowContainer: NSView?
    
    private let visualEffectView = NSVisualEffectView()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        
        visualEffectView.frame = self.bounds
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .popover
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        addSubview(visualEffectView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        let bounds = self.bounds
        let topY = bounds.height - 60.0
        
        searchIconView?.frame = NSRect(x: 18, y: topY + 16, width: 28, height: 28)
        searchField?.frame = NSRect(x: 54, y: topY + 14, width: bounds.width - 160, height: 32)
        countLabel?.frame = NSRect(x: bounds.width - 96, y: topY + 16, width: 80, height: 28)
        
        separatorView?.frame = NSRect(x: 0, y: topY, width: bounds.width, height: 1)
        rowContainer?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: topY)
    }
}

// MARK: - SearchResultRowView

class SearchResultRowView: NSView {
    let element: UIElement
    let isSelected: Bool
    
    private let badgeField: NSTextField
    private let titleField: NSTextField
    private let roleField: NSTextField
    
    init(frame frameRect: NSRect, element: UIElement, isSelected: Bool) {
        self.element = element
        self.isSelected = isSelected
        
        badgeField = NSTextField(frame: .zero)
        badgeField.cell = CenteredTextFieldCell()
        
        titleField = NSTextField(frame: .zero)
        titleField.cell = CenteredTextFieldCell()
        
        roleField = NSTextField(frame: .zero)
        roleField.cell = CenteredTextFieldCell()
        
        super.init(frame: frameRect)
        
        wantsLayer = true
        layer?.cornerRadius = 8
        
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        badgeField.isEditable = false
        badgeField.isBezeled = false
        badgeField.drawsBackground = false
        badgeField.alignment = .center
        badgeField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        
        badgeField.wantsLayer = true
        badgeField.layer?.cornerRadius = 5
        badgeField.layer?.masksToBounds = true
        
        if isSelected {
            badgeField.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
            badgeField.textColor = .white
        } else {
            badgeField.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            badgeField.textColor = NSColor.secondaryLabelColor
        }
        
        badgeField.stringValue = element.label.isEmpty ? " " : element.label
        
        titleField.isEditable = false
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        titleField.textColor = isSelected ? .white : NSColor.labelColor
        titleField.stringValue = element.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed \(element.role)" : element.title
        titleField.lineBreakMode = .byTruncatingTail
        
        roleField.isEditable = false
        roleField.isBezeled = false
        roleField.drawsBackground = false
        roleField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        roleField.textColor = isSelected ? NSColor.white.withAlphaComponent(0.7) : NSColor.secondaryLabelColor
        roleField.stringValue = cleanRoleName(element.role)
        roleField.alignment = .right
        
        addSubview(badgeField)
        addSubview(titleField)
        addSubview(roleField)
    }
    
    private func cleanRoleName(_ role: String) -> String {
        return role.replacingOccurrences(of: "AX", with: "")
    }
    
    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        
        let badgeW: CGFloat = element.label.isEmpty ? 0 : 38
        if badgeW > 0 {
            badgeField.frame = NSRect(x: 12, y: (h - 22) / 2, width: badgeW, height: 22)
        }
        
        let titleX = badgeW > 0 ? badgeW + 24 : 12
        let roleW: CGFloat = 90
        
        titleField.frame = NSRect(
            x: titleX,
            y: (h - 20) / 2,
            width: max(0, w - titleX - roleW - 24),
            height: 20
        )
        
        roleField.frame = NSRect(
            x: w - roleW - 12,
            y: (h - 18) / 2,
            width: roleW,
            height: 18
        )
    }
}

// MARK: - CenteredTextFieldCell

class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let rect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let deltaHeight = rect.height - textSize.height
        if deltaHeight > 0 {
            // Shift down by half the height difference to center vertically
            return NSRect(x: rect.origin.x, y: rect.origin.y + (deltaHeight / 2) - 1.5, width: rect.width, height: textSize.height)
        }
        return rect
    }
    
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let aRect = drawingRect(forBounds: rect)
        super.select(withFrame: aRect, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
    
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let aRect = drawingRect(forBounds: rect)
        super.edit(withFrame: aRect, in: controlView, editor: textObj, delegate: delegate, event: event)
    }
}

extension SearchMode {
    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            filterElements(query: field.stringValue)
        }
    }
}

class SearchPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}
