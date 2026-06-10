import Cocoa

final class FocusTextMode: Mode {

    private let overlayController = OverlayWindowController()
    private var allElements: [UIElement] = []
    private var currentCandidates: [UIElement] = []
    private var typedPrefix = ""
    private var pendingTimer: Timer?
    private var isActive = false
    private var currentlyHeldKey: String? = nil

    private static let scanQueue = DispatchQueue(label: "com.hopr.focustext-scan", qos: .userInitiated)

    private var activePID: pid_t = 0
    private var activeBundleID: String = "unknown"

    func activate() {
        isActive = true
        typedPrefix = ""
        currentlyHeldKey = nil
        pendingTimer?.invalidate()
        pendingTimer = nil

        let currentApp = NSWorkspace.shared.frontmostApplication
        activePID = currentApp?.processIdentifier ?? 0
        activeBundleID = currentApp?.bundleIdentifier ?? "unknown"

        SoundManager.shared.playEnterMode()

        // Try prefetched data first (instant show)
        if let prefetched = AccessibilityService.shared.consumePrefetchedElements(for: activePID) {
            let textFields = prefetched.elements.filter { $0.isTextInput }
            let labeled = KeyMapper.assignLabels(to: textFields, for: prefetched.bundleID)
            self.allElements = labeled
            self.currentCandidates = labeled
            self.overlayController.showFocusModeOverlays(for: labeled)
            Log.info("Focus Text: instant show \(labeled.count) fields (prefetched)")
        } else {
            // No cache — show loading while scanning
            loadingStartTime = CACurrentMediaTime()
            NotificationCenter.default.post(name: .hintModeLoadingDidStart, object: nil)
        }

        // Always refresh in background for latest data
        refreshAsync(isInitialLoad: !allElements.isEmpty)
    }

    func deactivate() {
        isActive = false
        pendingTimer?.invalidate()
        pendingTimer = nil
        overlayController.dismissAll()
        allElements = []
        currentCandidates = []
        typedPrefix = ""
        currentlyHeldKey = nil
    }

    /// Pre-fetch text fields when app changes for instant activation
    func prefetch(for app: NSRunningApplication? = nil) {
        let targetApp = app ?? NSWorkspace.shared.frontmostApplication
        guard let targetApp = targetApp else { return }
        let pid = targetApp.processIdentifier
        let bundleID = targetApp.bundleIdentifier ?? "unknown"

        FocusTextMode.scanQueue.async {
            let elements = AccessibilityService.shared.getTextInputElements(for: targetApp)
            AccessibilityService.shared.cacheTextInputElements(elements, for: pid, bundleID: bundleID)
            Log.debug("FocusText prefetch: \(elements.count) fields for PID \(pid)")
        }
    }

    // MARK: - Background Refresh

    private static let minLoadingDisplayTime: TimeInterval = 0.35
    private var loadingStartTime: CFTimeInterval = 0

    private func refreshAsync(isInitialLoad: Bool) {
        FocusTextMode.scanQueue.async { [weak self] in
            guard let self = self, self.isActive else { return }

            let textFields = AccessibilityService.shared.getTextInputElements()

            DispatchQueue.main.async {
                guard self.isActive else { return }
                let labeled = KeyMapper.assignLabels(to: textFields, for: self.activeBundleID)
                self.allElements = labeled

                if self.typedPrefix.isEmpty {
                    self.currentCandidates = labeled
                    self.overlayController.showFocusModeOverlays(for: labeled)
                } else {
                    let matches = labeled.filter { $0.label.hasPrefix(self.typedPrefix) }
                    self.currentCandidates = matches
                    self.overlayController.showFocusModeOverlays(for: matches)
                }
                Log.info("Focus Text: \(labeled.count) fields scanned")

                if isInitialLoad {
                    self.finishLoadingIfNeeded()
                }
            }
        }
    }

    private func finishLoadingIfNeeded() {
        let elapsed = CACurrentMediaTime() - loadingStartTime
        let remaining = FocusTextMode.minLoadingDisplayTime - elapsed

        if remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                guard let self = self, self.isActive else { return }
                NotificationCenter.default.post(name: .hintModeLoadingDidEnd, object: nil)
            }
        } else {
            NotificationCenter.default.post(name: .hintModeLoadingDidEnd, object: nil)
        }
    }

    // MARK: - Key Handling

    func handleKeyPress(_ key: String, keyCode: UInt16, isRepeat: Bool, modifiers: KeyModifiers) -> Bool {
        guard isActive else { return false }
        guard !key.isEmpty else { return false }
        if isRepeat { return true }

        currentlyHeldKey = key.uppercased()
        pendingTimer?.invalidate()
        pendingTimer = nil

        typedPrefix += key.uppercased()

        let matches = currentCandidates.filter { $0.label.hasPrefix(typedPrefix) }
        let exactMatch = matches.first { $0.label == typedPrefix }
        let longerMatches = matches.filter { $0.label.count > typedPrefix.count }

        if let exactMatch, longerMatches.isEmpty {
            activateElement(exactMatch)
            return true
        }

        if matches.count == 1, let only = matches.first {
            if AppSettings.shared.autoClick {
                activateElement(only)
                return true
            } else {
                currentCandidates = matches
                overlayController.showFocusModeOverlays(for: matches)
                SoundManager.shared.playKeyPress()
                return true
            }
        }

        if exactMatch != nil, !longerMatches.isEmpty {
            currentCandidates = matches
            overlayController.showFocusModeOverlays(for: matches)
            SoundManager.shared.playKeyPress()
            return true
        }

        if !matches.isEmpty {
            currentCandidates = matches
            overlayController.showFocusModeOverlays(for: matches)
            SoundManager.shared.playKeyPress()
            return true
        }

        typedPrefix = ""
        currentCandidates = allElements
        overlayController.showFocusModeOverlays(for: allElements)
        SoundManager.shared.playKeyMiss()
        return true
    }

    func handleKeyUp(_ key: String, keyCode: UInt16) {
        let upperKey = key.uppercased()
        guard upperKey == currentlyHeldKey else { return }
        currentlyHeldKey = nil

        let matches = currentCandidates.filter { $0.label.hasPrefix(typedPrefix) }
        let exactMatch = matches.first { $0.label == typedPrefix }
        let longerMatches = matches.filter { $0.label.count > typedPrefix.count }

        if exactMatch != nil, !longerMatches.isEmpty {
            let prefixCopy = typedPrefix
            pendingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if let elem = self.currentCandidates.first(where: { $0.label == prefixCopy }) {
                    self.activateElement(elem)
                }
            }
        }
    }

    // MARK: - Element Activation

    private func activateElement(_ element: UIElement) {
        Log.info("Focus Text: \(element.title) [\(element.label)]")

        overlayController.animateActivation(of: element.label) { [weak self] in
            guard let self = self else { return }

            element.focus()

            self.overlayController.dismissAll()
            self.typedPrefix = ""
            self.currentCandidates = self.allElements

            NotificationCenter.default.post(name: .focusTextModeDidClick, object: nil)
        }
    }
}

// MARK: - UIElement Extension

extension UIElement {
    var isTextInput: Bool {
        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField",
        ]
        if textRoles.contains(role) { return true }
        if role.lowercased().contains("text") &&
           (role.lowercased().contains("field") || role.lowercased().contains("area")) {
            return true
        }
        return false
    }
}
