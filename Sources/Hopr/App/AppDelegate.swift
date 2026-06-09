import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private let modeController = ModeController()

    private let hintMode = HintMode()
    private let scrollMode = ScrollMode()
    private let searchMode = SearchMode()
    private let mouseMode = MouseMode()
    private let modeIndicator = ModeIndicator()
    private var prefetchTimer: Timer?
    private var menubarObserver: NSObjectProtocol?
    private var menubarAnimator: MenubarAnimator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Permissions.ensureAccessibility() {
            Log.info("Waiting for accessibility permissions...")
        } else {
            Log.info("Accessibility permissions granted")
        }

        applyDockIcon()

        setupStatusBar()
        setupModes()

        // Load disk cache so hint mode has instant data even after app restart
        AccessibilityService.shared.loadDiskCache()
        AccessibilityService.shared.cleanupOldDiskCaches()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHintClick),
            name: .hintModeDidClick,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollModeExit),
            name: .scrollModeDidExit,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNudgeDragStart),
            name: .nudgeDragDidStart,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMouseDragStart),
            name: .mouseDragDidStart,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMouseDragEnd),
            name: .mouseDragDidEnd,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHintLoadingDidStart),
            name: .hintModeLoadingDidStart,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHintLoadingDidEnd),
            name: .hintModeLoadingDidEnd,
            object: nil
        )

        // Pre-fetch hint elements when frontmost app changes so hint mode activates instantly
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        hotkeyManager = HotkeyManager(modeController: modeController)
        if hotkeyManager.start() {
            Log.info("Hopr started — Shift+Space (hint), Shift+J (scroll), Shift+/ (search)")
        }

        // Initial prefetch after a short delay to let the system settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.hintMode.prefetch()
        }

        setupPrefetchTimer()

        // Observe showMenubarIcon changes via UserDefaults so toggling in Settings takes effect immediately
        menubarObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.statusItem.isVisible = AppSettings.shared.showMenubarIcon
        }
        // Apply initial value
        statusItem.isVisible = AppSettings.shared.showMenubarIcon
    }

    @objc private func handleAppActivation(_ notification: Notification) {
        if let app = notification.object as? NSRunningApplication {
            let bundleID = app.bundleIdentifier
            let isIgnored = AppSettings.shared.isAppIgnored(bundleID) ||
                            bundleID == Bundle.main.bundleIdentifier ||
                            bundleID == "com.timpler.screenstudio" ||
                            app.activationPolicy == .accessory
            
            if isIgnored {
                // Do not deactivate current mode for ignored, self, Screen Studio, or accessory apps
                if modeController.currentMode == .idle {
                    hintMode.prefetch(for: app)
                }
                return
            }
        }

        // When user switches to a new app, pre-scan its UI elements in background
        // so hint mode can show labels instantly
        if modeController.currentMode != .idle && modeController.currentMode != .mouse {
            modeController.deactivateCurrentMode()
        }
        if let app = notification.object as? NSRunningApplication {
            hintMode.prefetch(for: app)
        } else {
            hintMode.prefetch()
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Use the animated Hollow Knight icon
            menubarAnimator = MenubarAnimator(button: button)
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
        // Initial menu population
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Header
        let headerItem = NSMenuItem(title: "Hopr", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        let settings = AppSettings.shared
        // Shortcuts section
        addMenuItem(menu, title: "Hint Mode", shortcut: settings.hintShortcut.displayString, action: #selector(activateHint))
        addMenuItem(menu, title: "Scroll Mode", shortcut: settings.scrollShortcut.displayString, action: #selector(activateScroll))
        addMenuItem(menu, title: "Mouse Mode", shortcut: settings.mouseShortcut.displayString, action: #selector(activateMouse))
        addMenuItem(menu, title: "Search Mode", shortcut: settings.searchShortcut.displayString, action: #selector(activateSearch))
        addMenuItem(menu, title: "Exit Mode", shortcut: "Esc", action: #selector(activateEscape))

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Hopr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)
    }

    private func addMenuItem(_ menu: NSMenu, title: String, shortcut: String, action: Selector) {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.isEnabled = true
        let full = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
        full.append(NSAttributedString(string: "  \(shortcut)", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
        ]))
        item.attributedTitle = full
        menu.addItem(item)
    }

    @objc private func activateHint() {
        modeController.activateHintMode()
    }

    @objc private func activateScroll() {
        modeController.activateScrollMode()
    }

    @objc private func activateMouse() {
        modeController.activateMouseMode()
    }

    @objc private func activateSearch() {
        modeController.activateSearchMode()
    }

    @objc private func activateEscape() {
        modeController.deactivateCurrentMode()
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    private func setupModes() {
        modeController.registerMode(hintMode, for: .hint)
        modeController.registerMode(scrollMode, for: .scroll)
        modeController.registerMode(searchMode, for: .search)
        modeController.registerMode(mouseMode, for: .mouse)

        modeController.onModeChange = { [weak self] mode in
            self?.handleModeChange(mode)
        }
        hintMode.onVisibilityChange = { [weak self] visible in
            if visible {
                self?.modeIndicator.show(mode: .hint)
            } else {
                self?.modeIndicator.hide()
            }
        }
    }

    @objc private func handleHintClick() {
        modeController.deactivateCurrentMode()
    }

    @objc private func handleScrollModeExit() {
        guard modeController.currentMode == .scroll else { return }
        modeController.deactivateCurrentMode()
    }

    @objc private func handleNudgeDragStart() {
        modeIndicator.updatePill(icon: "cursorarrow.and.square.on.square", text: "Drag — WASD/Arrows to move · Enter to drop", color: .systemOrange)
    }

    @objc private func handleMouseDragStart() {
        modeIndicator.updatePill(icon: "cursorarrow.and.square.on.square", text: "Mouse Dragging — WASD to move · Release Q to drop", color: .systemOrange)
    }

    @objc private func handleMouseDragEnd() {
        guard modeController.currentMode == .mouse else { return }
        modeIndicator.show(mode: .mouse)
    }

    @objc private func handleHintLoadingDidStart() {
        guard modeController.currentMode == .hint else { return }
        modeIndicator.show(mode: .hint, isLoading: true)
    }

    @objc private func handleHintLoadingDidEnd() {
        guard modeController.currentMode == .hint else { return }
        modeIndicator.show(mode: .hint, isLoading: false)
    }

    private func setupPrefetchTimer() {
        prefetchTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Only prefetch periodically if the app is currently in idle mode
            if self.modeController.currentMode == .idle {
                AccessibilityService.shared.prefetch()
            }
        }
    }

    private func handleModeChange(_ mode: AppMode) {
        modeIndicator.show(mode: mode)

        if mode == .idle {
            OverlayWindowController.dismissHUDNotification()
        } else {
            OverlayWindowController.showHUDNotification(mode: mode)
        }

        switch mode {
        case .idle:
            hintMode.deactivate()
            scrollMode.deactivate()
            searchMode.deactivate()
            mouseMode.deactivate()
            SoundManager.shared.playExitMode()
            menubarAnimator?.setExpression(.normal)
        case .hint:
            hintMode.activate()
            menubarAnimator?.playSurprised()
        case .scroll:
            scrollMode.activate()
            menubarAnimator?.playHappy()
        case .search:
            searchMode.activate()
            menubarAnimator?.setExpression(.surprised, revertAfter: 1.0)
        case .mouse:
            mouseMode.activate()
            menubarAnimator?.playAngry()
        }
    }

    private func resizeAndPadIcon(_ image: NSImage, scaleFactor: CGFloat = 0.80) -> NSImage {
        let targetSize = NSSize(width: 512, height: 512)
        let paddedImage = NSImage(size: targetSize)
        
        paddedImage.lockFocus()
        
        // Clear background to be completely transparent
        NSColor.clear.set()
        NSRect(origin: .zero, size: targetSize).fill()
        
        let w = targetSize.width * scaleFactor
        let h = targetSize.height * scaleFactor
        let x = (targetSize.width - w) / 2
        let y = (targetSize.height - h) / 2
        let destRect = NSRect(x: x, y: y, width: w, height: h)
        
        image.draw(in: destRect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
        
        paddedImage.unlockFocus()
        return paddedImage
    }

    func applyDockIcon() {
        let fm = FileManager.default
        let localPath = fm.currentDirectoryPath + "/Resources/icon.png"
        let bundlePath = Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent("icon.png") }

        var iconImage: NSImage? = nil
        if fm.fileExists(atPath: localPath) {
            iconImage = NSImage(contentsOfFile: localPath)
        } else if let bundlePath, fm.fileExists(atPath: bundlePath) {
            iconImage = NSImage(contentsOfFile: bundlePath)
        }

        if let icon = iconImage {
            NSApplication.shared.applicationIconImage = resizeAndPadIcon(icon, scaleFactor: 0.80)
        }
    }
}
