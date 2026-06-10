import Cocoa
import ApplicationServices

final class AccessibilityService {

    static let shared = AccessibilityService()

    private let actionableRoles: Set<String> = [
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXPopUpButtonRole as String,
        kAXMenuItemRole as String,
        "AXLink",
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXTab",
        kAXMenuBarItemRole as String,
        "AXToolbar",
        "AXDockItem",
        "AXMenuExtra",
        kAXSliderRole as String,
        "AXDisclosureTriangle",
    ]

    private let electronBundlePrefixes = [
        "com.microsoft.VSCode",
        "com.google.antigravity-ide",
        "com.todesktop",
        "com.electron.",
    ]

    private let maxElements = 200

    // MARK: - Cache

    private struct CacheEntry {
        let elements: [UIElement]
        let timestamp: CFTimeInterval
    }
    private var cacheMap: [pid_t: CacheEntry] = [:]
    private var textElementCacheMap: [pid_t: CacheEntry] = [:] // Separate cache for text-only elements
    private let cacheTTL: CFTimeInterval = 0.8 // seconds — shorter for snappier refresh

    private struct PrefetchedEntry {
        let elements: [UIElement]
        let timestamp: CFTimeInterval
        let bundleID: String
    }
    private var prefetchedMap: [pid_t: PrefetchedEntry] = [:]

    // MARK: - Disk Cache (per-app hint snapshots)

    private struct HintSnapshot: Codable {
        let bundleID: String
        let timestamp: TimeInterval
        let elements: [ElementSnapshot]
    }
    private var diskCache: [String: HintSnapshot] = [:]
    private let diskCacheDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Hopr/HintCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private let maxDiskCacheApps = 10
    private let prefetchTTL: CFTimeInterval = 120.0

    /// Serial queue to protect cache access from concurrent reads/writes
    private let cacheQueue = DispatchQueue(label: "com.hopr.ax-cache")
    private static let scanQueue = DispatchQueue(label: "com.hopr.ax-scan", qos: .userInitiated)

    private init() {}

    // MARK: - AX Value Helpers

    /// Extract CGPoint from a CFTypeRef returned by AXUIElementCopyAttributeValue.
    private func axPointValue(_ ref: CFTypeRef?) -> CGPoint? {
        guard let ref else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeBitCast(ref, to: AXValue.self), .cgPoint, &point) else { return nil }
        return point
    }

    /// Extract CGSize from a CFTypeRef returned by AXUIElementCopyAttributeValue.
    private func axSizeValue(_ ref: CFTypeRef?) -> CGSize? {
        guard let ref else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(ref, to: AXValue.self), .cgSize, &size) else { return nil }
        return size
    }

    private func isElectronApp(_ app: NSRunningApplication) -> Bool {
        if let bundle = app.bundleIdentifier {
            return electronBundlePrefixes.contains(where: { bundle.hasPrefix($0) })
        }
        let name = app.localizedName?.lowercased() ?? ""
        return name.contains("vscode") || name.contains("visual studio code")
            || name.contains("antigravity") || name.contains("cursor")
            || name.contains("slack") || name.contains("discord")
            || name.contains("notion") || name.contains("obsidian")
    }

    private func isPossibleMenuBarApp(_ app: NSRunningApplication) -> Bool {
        guard let bundle = app.bundleIdentifier else { return true }
        
        let skipPrefixes = [
            "com.apple.WebKit",
            "com.apple.wallpaper",
            "com.apple.loginwindow",
            "com.apple.WindowManager",
            "com.apple.notificationcenter",
            "com.apple.security",
            "com.apple.coreservices",
            "com.apple.local",
            "com.google.Chrome.helper"
        ]
        
        for prefix in skipPrefixes {
            if bundle.hasPrefix(prefix) {
                return false
            }
        }
        
        let lowerName = app.localizedName?.lowercased() ?? ""
        if lowerName.contains("helper") || lowerName.contains("daemon") || lowerName.contains("host") || lowerName.contains("powerchime") {
            if !bundle.contains("TextInputMenuAgent") && !bundle.contains("WiFiAgent") {
                return false
            }
        }
        
        return true
    }

    private func isDisclosureElement(_ elem: UIElement) -> Bool {
        if elem.role == "AXDisclosureTriangle" {
            return true
        }
        if elem.role == "AXStaticText" {
            let t = elem.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t == "" || t == "" || t == "" || t == "" || t == "▶" || t == "▼"
        }
        return false
    }

    /// Get actionable UI elements: fast scan using AXUIElementsForSearchPredicate
    func getActionableElements(for app: NSRunningApplication? = nil) -> [UIElement] {
        let frontApp = app ?? NSWorkspace.shared.frontmostApplication
        let currentPID = frontApp?.processIdentifier ?? 0
        let now = CACurrentMediaTime()

        // Return cache if still fresh AND same app
        let cached: [UIElement]? = cacheQueue.sync {
            if let entry = cacheMap[currentPID], (now - entry.timestamp) < cacheTTL {
                return entry.elements
            }
            return nil
        }
        if let cached = cached { return cached }

        guard let frontApp = frontApp else { return [] }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Electron apps require AXManualAccessibility
        if isElectronApp(frontApp) {
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
        } else {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
        }

        var allElements: [UIElement] = []

        // Try to extract browser elements via AppleScript for super-fast, viewport-only scan
        let browserElements = extractBrowserElements(frontApp: frontApp, appElement: appElement)

        // Primary: fast predicate search (like Hopr) — one call per role, no tree traversal
        let searchKeys = [
            "AXButtonSearchKey",
            "AXCheckBoxSearchKey",
            "AXRadioGroupSearchKey",
            "AXLinkSearchKey",
            "AXTextFieldSearchKey",
            "AXTextAreaSearchKey",
            "AXKeyboardFocusableSearchKey",
        ]

        let searchResult = searchViaPredicate(appElement: appElement, searchKeys: searchKeys)
        
        if let browserElements = browserElements {
            // Merge native window chrome elements (tabs, toolbar buttons) with HTML viewport elements
            let bundleID = frontApp.bundleIdentifier ?? ""
            let isChrome = bundleID.contains("Chrome") || bundleID.contains("Chromium") || bundleID.contains("Brave") || bundleID.contains("Edge") || bundleID.contains("Vivaldi")
            if isChrome {
                let nativeElements = getNativeWindowElements(from: appElement)
                allElements = nativeElements + browserElements
            } else {
                allElements = searchResult + browserElements
            }
        } else {
            allElements = searchResult
            // Fallback: if search predicate returned too few, do a targeted traversal
            if allElements.count <= 2 {
                allElements.removeAll()
                if let window = getFrontmostWindow(from: appElement) {
                    var elements: [UIElement] = []
                    traverse(element: window, depth: 0, parentRowId: nil, inListOrRow: false, elements: &elements)
                    allElements.append(contentsOf: elements)
                } else if let windows = getAllWindows(from: appElement) {
                    for window in windows {
                        var elements: [UIElement] = []
                        traverse(element: window, depth: 0, parentRowId: nil, inListOrRow: false, elements: &elements)
                        allElements.append(contentsOf: elements)
                    }
                }
            } else {
                // Predicate search worked for native UI, but we must also scan any AXWebArea / AXWebDocument
                // elements to make sure web content (HTML links, buttons, fields) is fully covered.
                var targetWindows: [AXUIElement] = []
                if let frontWindow = getFrontmostWindow(from: appElement) {
                    targetWindows = [frontWindow]
                } else if let windows = getAllWindows(from: appElement) {
                    targetWindows = windows
                }
                
                var webElements: [UIElement] = []
                for window in targetWindows {
                    let webAreas = findWebAreas(in: window)
                    for webArea in webAreas {
                        var elements: [UIElement] = []
                        traverse(element: webArea, depth: 0, parentRowId: nil, inListOrRow: false, elements: &elements)
                        webElements.append(contentsOf: elements)
                    }
                }
                allElements.append(contentsOf: webElements)
            }
        }

        let processed = postProcess(allElements)

        cacheQueue.sync {
            cacheMap[currentPID] = CacheEntry(elements: processed, timestamp: now)
        }
        return processed
    }

    /// Fast focused scan: only text input fields (text fields, text areas, combo boxes).
    /// Much faster than getActionableElements() which scans ALL roles.
    func getTextInputElements(for app: NSRunningApplication? = nil) -> [UIElement] {
        let frontApp = app ?? NSWorkspace.shared.frontmostApplication
        let currentPID = frontApp?.processIdentifier ?? 0
        let now = CACurrentMediaTime()

        // Check cache first (using separate text-only cache)
        let cached: [UIElement]? = cacheQueue.sync {
            if let entry = textElementCacheMap[currentPID], (now - entry.timestamp) < cacheTTL {
                return entry.elements
            }
            return nil
        }
        if let cached = cached { return cached }

        guard let frontApp = frontApp else { return [] }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        if isElectronApp(frontApp) {
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
        } else {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
        }

        // Only search text-related roles — much faster than full scan
        let textSearchKeys = [
            "AXTextFieldSearchKey",
            "AXTextAreaSearchKey",
        ]

        var elements = searchViaPredicate(appElement: appElement, searchKeys: textSearchKeys)

        // Also check browser elements for text fields in web pages
        if let browserElements = extractBrowserElements(frontApp: frontApp, appElement: appElement) {
            let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]
            let webTextFields = browserElements.filter { textRoles.contains($0.role) }
            elements.append(contentsOf: webTextFields)
        }

        // Deduplicate by role+title
        var seen = Set<String>()
        var unique: [UIElement] = []
        for elem in elements {
            let key = "\(elem.role):\(elem.title):\(Int(elem.frame.origin.x)),\(Int(elem.frame.origin.y))"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(elem)
            }
        }

        cacheQueue.sync {
            textElementCacheMap[currentPID] = CacheEntry(elements: unique, timestamp: now)
        }
        return unique
    }

    /// Cache pre-scanned text input elements for instant FocusTextMode activation.
    func cacheTextInputElements(_ elements: [UIElement], for pid: pid_t, bundleID: String) {
        cacheQueue.sync {
            prefetchedMap[pid] = PrefetchedEntry(elements: elements, timestamp: CACurrentMediaTime(), bundleID: bundleID)
        }
    }

    private struct BrowserElement: Decodable {
        let left: Double
        let top: Double
        let width: Double
        let height: Double
        let role: String
        let title: String
    }

    private func extractBrowserElements(frontApp: NSRunningApplication, appElement: AXUIElement) -> [UIElement]? {
        guard let bundleID = frontApp.bundleIdentifier else { return nil }
        
        let isSafari = bundleID.contains("Safari")
        let isChrome = bundleID.contains("Chrome") || bundleID.contains("Chromium") || bundleID.contains("Brave") || bundleID.contains("Edge") || bundleID.contains("Vivaldi")
        
        guard isSafari || isChrome else { return nil }
        
        // Find web areas first so we know their screen coordinates
        var targetWindows: [AXUIElement] = []
        if let frontWindow = getFrontmostWindow(from: appElement) {
            targetWindows = [frontWindow]
        } else if let windows = getAllWindows(from: appElement) {
            targetWindows = windows
        }
        
        var allWebElements: [UIElement] = []
        var webAreaFound = false
        
        for window in targetWindows {
            let webAreas = findWebAreas(in: window)
            for webArea in webAreas {
                webAreaFound = true
                
                // Get webArea frame
                var webAreaFrame = CGRect.zero
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(webArea, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(webArea, kAXSizeAttribute as CFString, &sizeRef)
                if let p = axPointValue(posRef) { webAreaFrame.origin = p }
                if let s = axSizeValue(sizeRef) { webAreaFrame.size = s }
                
                guard webAreaFrame.width > 50 && webAreaFrame.height > 50 else { continue }
                
                // Query via AppleScript
                let browserElems = queryBrowserViaAppleScript(bundleID: bundleID, webAreaFrame: webAreaFrame)
                if !browserElems.isEmpty {
                    allWebElements.append(contentsOf: browserElems)
                } else {
                    // Fallback to accessibility tree traversal for this webArea
                    var elements: [UIElement] = []
                    traverse(element: webArea, depth: 0, parentRowId: nil, inListOrRow: false, elements: &elements)
                    allWebElements.append(contentsOf: elements)
                }
            }
        }
        
        if webAreaFound {
            return allWebElements
        }
        return nil
    }

    private func queryBrowserViaAppleScript(bundleID: String, webAreaFrame: CGRect) -> [UIElement] {
        let js = """
        (function() {
          var elements = document.querySelectorAll('a, button, input, select, textarea, [role=\"button\"], [role=\"link\"], [role=\"checkbox\"], [role=\"radio\"], [onclick]');
          var results = [];
          var viewportWidth = window.innerWidth;
          var viewportHeight = window.innerHeight;
          for (var i = 0; i < elements.length; i++) {
            var el = elements[i];
            var style = window.getComputedStyle(el);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') continue;
            var rect = el.getBoundingClientRect();
            if (rect.width < 3 || rect.height < 3) continue;
            if (rect.bottom < 0 || rect.right < 0 || rect.top > viewportHeight || rect.left > viewportWidth) continue;
            var role = el.getAttribute('role') || el.tagName.toLowerCase();
            if (role === 'a') role = 'AXLink';
            else if (role === 'button') role = 'AXButton';
            else if (role === 'input') {
              var type = el.getAttribute('type') || 'text';
              if (type === 'checkbox') role = 'AXCheckBox';
              else if (type === 'radio') role = 'AXRadioButton';
              else role = 'AXTextField';
            }
            else if (role === 'textarea') role = 'AXTextArea';
            else if (role === 'select') role = 'AXPopUpButton';
            else if (role.indexOf('button') !== -1) role = 'AXButton';
            else if (role.indexOf('link') !== -1) role = 'AXLink';
            else role = 'AXButton';
            var title = el.getAttribute('aria-label') || el.innerText || el.value || el.placeholder || el.title || '';
            title = title.trim();
            results.push({
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              role: role,
              title: title
            });
            if (results.length > 300) break;
          }
          return JSON.stringify(results);
        })()
        """
        
        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptText: String
        if bundleID.contains("Safari") {
            scriptText = """
            tell application "Safari"
                if (count of windows) is not 0 then
                    tell front window
                        do JavaScript "\(escapedJS)" in current tab
                    end tell
                else
                    return ""
                end if
            end tell
            """
        } else {
            // Find app name
            let appName: String
            if bundleID.contains("Chrome") {
                appName = "Google Chrome"
            } else if bundleID.contains("Brave") {
                appName = "Brave Browser"
            } else if bundleID.contains("Edge") {
                appName = "Microsoft Edge"
            } else if bundleID.contains("Vivaldi") {
                appName = "Vivaldi"
            } else {
                appName = "Chromium"
            }
            
            scriptText = """
            tell application "\(appName)"
                if (count of windows) is not 0 then
                    tell active tab of front window
                        execute javascript "\(escapedJS)"
                    end tell
                else
                    return ""
                end if
            end tell
            """
        }
        
        guard let script = NSAppleScript(source: scriptText) else { return [] }
        var errorInfo: NSDictionary?
        let resultDescriptor = script.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            Log.error("AppleScript error querying browser elements: \(error)")
            return []
        }
        
        guard let jsonStr = resultDescriptor.stringValue, !jsonStr.isEmpty else {
            return []
        }
        
        guard let data = jsonStr.data(using: .utf8),
              let browserElements = try? JSONDecoder().decode([BrowserElement].self, from: data) else {
            return []
        }
        
        var uiElements: [UIElement] = []
        for be in browserElements {
            let elemFrame = CGRect(
                x: webAreaFrame.origin.x + CGFloat(be.left),
                y: webAreaFrame.origin.y + CGFloat(be.top),
                width: CGFloat(be.width),
                height: CGFloat(be.height)
            )
            
            let elem = UIElement(
                element: nil,
                role: be.role,
                title: be.title,
                frame: elemFrame,
                enabled: true
            )
            uiElements.append(elem)
        }
        
        Log.debug("Browser elements fetched via AppleScript: \(uiElements.count)")
        return uiElements
    }

    // MARK: - Search Predicate (Hopr-style fast discovery)

    /// Use AXUIElementsForSearchPredicate to find actionable elements without tree traversal.
    /// This is how Hopr achieves fast element discovery — system-level search, not manual traversal.
    private func searchViaPredicate(appElement: AXUIElement, searchKeys: [String]) -> [UIElement] {
        var found: [UIElement] = []
        var seenTitles = Set<String>()

        for searchKey in searchKeys {
            let predicate: [String: Any] = [
                "AXSearchKey": searchKey,
                "AXRecursive": true
            ]

            // Try parameterized attribute first (Hopr's approach)
            var resultRef: CFTypeRef?
            let err = AXUIElementCopyParameterizedAttributeValue(
                appElement,
                "AXUIElementsForSearchPredicate" as CFString,
                predicate as CFTypeRef,
                &resultRef
            )

            if err == .success, let results = resultRef as? [AXUIElement] {
                for axElem in results {
                    guard let elem = UIElement.from(axElem) else { continue }
                    let key = "\(elem.role):\(elem.title)"
                    guard !seenTitles.contains(key) else { continue }
                    seenTitles.insert(key)
                    found.append(elem)
                }
            }
        }

        return found
    }

    /// Check if the active/frontmost application is in native fullscreen mode
    func isAppFullscreen(_ app: NSRunningApplication? = nil) -> Bool {
        let frontApp = app ?? NSWorkspace.shared.frontmostApplication
        guard let frontApp = frontApp else { return false }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        if let window = getFrontmostWindow(from: appElement) {
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &val) == .success,
               let subrole = val as? String,
               subrole == "AXFullScreenWindow" {
                return true
            }
            var fsVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fsVal) == .success,
               let num = fsVal as? NSNumber {
                return num.boolValue
            }
        }
        return false
    }

    /// Slow scan: Dock + status bar accessory apps (system overlays).
    /// Call this on a background thread after fast scan completes.
    func getSystemOverlayElements() -> [UIElement] {
        if isAppFullscreen() {
            Log.info("Frontmost app is fullscreen. Skipping system wide overlay scan (Dock and Menu bar).")
            return []
        }

        var overlays: [UIElement] = []

        // 1. Scan Dock
        if let dockApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) {
            let appElement = AXUIElementCreateApplication(dockApp.processIdentifier)
            var elements: [UIElement] = []
            traverse(element: appElement, depth: 0, parentRowId: nil, inListOrRow: false, elements: &elements)
            for i in 0..<elements.count {
                elements[i].isSystemOverlay = true
            }
            overlays.append(contentsOf: elements)
        }

        // 2. Scan accessory apps (status bar: Wi-Fi, battery, clock, control center, 3rd-party widgets)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .accessory {
            if app.bundleIdentifier == "com.apple.dock" || app.processIdentifier == NSRunningApplication.current.processIdentifier {
                continue
            }
            if !isPossibleMenuBarApp(app) {
                continue
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            if isElectronApp(app) {
                AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
            } else {
                AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
            }

            // Menu bars
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    var roleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                       let role = roleRef as? String,
                       role == "AXMenuBar" {
                        var elements: [UIElement] = []
                        traverse(element: child, depth: 0, parentRowId: nil, inListOrRow: false, elements: &elements)
                        for i in 0..<elements.count {
                            elements[i].isSystemOverlay = true
                        }
                        overlays.append(contentsOf: elements)
                    }
                }
            }

            // Visible windows (popovers/dialogs: Control Center, Spotlight)
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement] {
                for window in windows {
                    var size = CGSize.zero
                    var sizeRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success {
                        if let s = axSizeValue(sizeRef) { size = s }
                    }
                    if size.width > 5 && size.height > 5 {
                        var elements: [UIElement] = []
                        traverse(element: window, depth: 0, parentRowId: nil, inListOrRow: false, elements: &elements)
                        for i in 0..<elements.count {
                            elements[i].isSystemOverlay = true
                        }
                        overlays.append(contentsOf: elements)
                    }
                }
            }
        }

        return postProcess(overlays)
    }

    // MARK: - Post-Processing

    private func postProcess(_ allElements: [UIElement]) -> [UIElement] {
        var toRemove = Set<UUID>()
        let rows = allElements.filter { $0.role == "AXRow" || $0.role == "AXOutlineRow" }
        for row in rows {
            let descendants = allElements.filter { $0.parentRowId == row.id }
            let textDescendants = descendants.filter {
                ($0.role == "AXStaticText" || $0.role == "AXTextField" || $0.role == "AXTextArea" || $0.role == "AXLink")
                && !isDisclosureElement($0)
            }
            if !textDescendants.isEmpty {
                if let primaryLabel = textDescendants.first {
                    toRemove.insert(row.id)
                    for desc in textDescendants {
                        if desc.id != primaryLabel.id {
                            toRemove.insert(desc.id)
                        }
                    }
                }
            }

            let buttonDescendants = descendants.filter { $0.role == "AXButton" }
            for btn in buttonDescendants {
                let lowerTitle = btn.title.lowercased()
                if lowerTitle.contains("expand") || lowerTitle.contains("collapse") ||
                   lowerTitle.contains("chevron") || lowerTitle.contains("arrow") ||
                   btn.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    toRemove.insert(btn.id)
                }
            }
        }

        let visible = allElements.filter { elem in
            !toRemove.contains(elem.id)
            && elem.frame.width > 5 && elem.frame.height > 5
            && elem.frame.origin.x > -200 && elem.frame.origin.y > -200
        }

        return deduplicateOverlapping(visible)
    }

    func clearCache(for pid: pid_t) {
        cacheQueue.sync {
            _ = cacheMap.removeValue(forKey: pid)
        }
    }

    func forceRefresh() -> [UIElement] {
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        cacheQueue.sync {
            _ = cacheMap.removeValue(forKey: currentPID)
        }
        let appElements = getActionableElements()
        let overlays = getSystemOverlayElements()
        return appElements + overlays
    }

    /// Pre-fetch elements in background so next activation (Hint or Search mode) is instant.
    /// Includes system overlays for complete hints on first show.
    func prefetch(for app: NSRunningApplication? = nil) {
        let targetApp = app ?? NSWorkspace.shared.frontmostApplication
        guard let targetApp = targetApp else { return }
        let pid = targetApp.processIdentifier
        let bundleID = targetApp.bundleIdentifier ?? "unknown"

        AccessibilityService.scanQueue.async { [weak self] in
            guard let self = self else { return }
            let elements = self.getActionableElements(for: targetApp)

            // Merge system overlays (Dock, status bar) into prefetch
            let overlays = self.getSystemOverlayElements()
            let combined = elements + overlays

            self.cacheQueue.sync {
                self.prefetchedMap[pid] = PrefetchedEntry(elements: combined, timestamp: CACurrentMediaTime(), bundleID: bundleID)
            }
            Log.debug("AccessibilityService prefetch: \(combined.count) elements ready for PID \(pid) (\(bundleID))")
        }
    }

    /// Retrieve and consume prefetched elements for a PID
    func consumePrefetchedElements(for pid: pid_t) -> (elements: [UIElement], bundleID: String)? {
        return cacheQueue.sync {
            let now = CACurrentMediaTime()
            if let entry = prefetchedMap[pid], (now - entry.timestamp) < prefetchTTL {
                prefetchedMap.removeValue(forKey: pid)
                return (entry.elements, entry.bundleID)
            }
            return nil
        }
    }

    private func getFocusedWindow(from appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let ref = windowRef {
            return unsafeBitCast(ref, to: AXUIElement.self)
        }
        // Fallback: get first window
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement],
           let first = windows.first {
            return first
        }
        return nil
    }

    private func getAllWindows(from appElement: AXUIElement) -> [AXUIElement]? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else { return nil }
        return windows
    }

    private func getMenuBar(from appElement: AXUIElement) -> AXUIElement? {
        var menuBarRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
           let ref = menuBarRef {
            return unsafeBitCast(ref, to: AXUIElement.self)
        }
        return nil
    }

    private func traverse(element: AXUIElement, depth: Int, parentRowId: UUID?, inListOrRow: Bool, elements: inout [UIElement], skipWebAreas: Bool = false) {
        // Electron apps have very deep trees (often over 30 levels) — need enough depth to reach all elements
        guard depth < 45 else { return }

        var currentParentRowId = parentRowId
        var nextInListOrRow = inListOrRow
        var isWebArea = false
        if var uiElement = UIElement.from(element) {
            uiElement.parentRowId = parentRowId
            if uiElement.role == "AXRow" || uiElement.role == "AXOutlineRow" {
                currentParentRowId = uiElement.id
                nextInListOrRow = true
            } else if uiElement.role == "AXList" || uiElement.role == "AXTable" || uiElement.role == "AXOutline" {
                nextInListOrRow = true
            } else if uiElement.role == "AXWebArea" || uiElement.role == "AXWebDocument" {
                isWebArea = true
            }

            if !(skipWebAreas && isWebArea) {
                if shouldInclude(uiElement, element, inListOrRow: inListOrRow) {
                    elements.append(uiElement)
                }
            }
        }

        // When skipping web areas, don't recurse into their children
        if skipWebAreas && isWebArea {
            return
        }

        var children: [AXUIElement] = []

        // 1. Try AXChildrenInNavigationOrder
        var navRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &navRef) == .success,
           let navChildren = navRef as? [AXUIElement] {
            children.append(contentsOf: navChildren)
        }

        // 2. Try kAXChildrenAttribute
        var normalRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &normalRef) == .success,
           let normalChildren = normalRef as? [AXUIElement] {
            children.append(contentsOf: normalChildren)
        }

        // Deduplicate children using CFHash for performance
        var uniqueChildren: [AXUIElement] = []
        var seenHashes = Set<CFHashCode>()
        for child in children {
            let hash = CFHash(child)
            if !seenHashes.contains(hash) {
                seenHashes.insert(hash)
                uniqueChildren.append(child)
            }
        }

        for child in uniqueChildren {
            traverse(element: child, depth: depth + 1, parentRowId: currentParentRowId, inListOrRow: nextInListOrRow, elements: &elements, skipWebAreas: skipWebAreas)
        }
    }

    private func getNativeWindowElements(from appElement: AXUIElement) -> [UIElement] {
        var elements: [UIElement] = []

        var targetWindows: [AXUIElement] = []
        if let frontWindow = getFrontmostWindow(from: appElement) {
            targetWindows = [frontWindow]
        } else if let windows = getAllWindows(from: appElement) {
            targetWindows = windows
        }

        for window in targetWindows {
            traverse(element: window, depth: 0, parentRowId: nil, inListOrRow: false, elements: &elements, skipWebAreas: true)
        }
        return elements
    }

    private func findWebAreas(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 10 else { return [] }
        
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return [] }
              
        if role == "AXWebArea" || role == "AXWebDocument" {
            return [element]
        }
        
        var webAreas: [AXUIElement] = []
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                webAreas.append(contentsOf: findWebAreas(in: child, depth: depth + 1))
            }
        }
        return webAreas
    }

    private func supportsPressAction(_ element: AXUIElement) -> Bool {
        var actionNames: CFArray?
        let actions = [
            kAXPressAction as String,
            "AXOpen",
            kAXConfirmAction as String,
            kAXPickAction as String,
        ]
        
        guard AXUIElementCopyActionNames(element, &actionNames) == .success,
              let names = actionNames as? [String] else {
            return false
        }
        
        return names.contains { actions.contains($0) }
    }

    /// Include element if it's actionable OR has a meaningful name (title/description)
    private func shouldInclude(_ elem: UIElement, _ rawElement: AXUIElement, inListOrRow: Bool) -> Bool {
        // Exclude Dock items with empty/whitespace titles (like separators)
        if elem.role == "AXDockItem" {
            if elem.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }

        if actionableRoles.contains(elem.role) { return true }
        if isDisclosureElement(elem) { return true }
        
        // Always include rows so post-processing works
        if elem.role == "AXRow" || elem.role == "AXOutlineRow" { return true }

        if !elem.title.isEmpty {
            // Skip full-window container groups — they're layout wrappers, not interactive
            if elem.role == "AXGroup" || elem.role == "AXWebArea" {
                return false
            }
            // Filter out non-alphanumeric static text / icon labels
            if elem.role == "AXStaticText" {
                let trimmed = elem.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let isChevron = trimmed == "" || trimmed == "" || trimmed == "" || trimmed == "" || trimmed == "▶" || trimmed == "▼"
                let hasLetterOrDigit = trimmed.rangeOfCharacter(from: .alphanumerics) != nil
                if !hasLetterOrDigit && !isChevron {
                    return false
                }
                
                // Only include static text if it is inside a list/row/table/outline or supports actions, or is a chevron
                if inListOrRow || supportsPressAction(rawElement) || isChevron {
                    return true
                }
                return false
            }
            
            // For other elements, check if they support actions
            return supportsPressAction(rawElement)
        }
        return false
    }

    /// Remove overlapping elements — keep the larger/more specific one
    private func deduplicateOverlapping(_ elements: [UIElement]) -> [UIElement] {
        guard elements.count > 1 else { return elements }

        let rolePriority: [String: Int] = [
            kAXButtonRole as String: 0,
            kAXCheckBoxRole as String: 0,
            kAXRadioButtonRole as String: 0,
            kAXPopUpButtonRole as String: 0,
            kAXMenuItemRole as String: 1,
            "AXLink": 2,
            kAXTextFieldRole as String: 3,
            kAXTextAreaRole as String: 3,
            "AXTab": 4,
            kAXMenuBarItemRole as String: 1,
            "AXDockItem": 1,
            "AXMenuExtra": 1,
        ]

        let containerRoles: Set<String> = [
            "AXGroup", "AXScrollArea", "AXOutline", "AXList", "AXTable",
            "AXRow", "AXOutlineRow", "AXWindow", "AXWebArea", "AXToolbar",
            "AXSplitView", "AXScrollbar", "AXSheet"
        ]

        var keptDict: [UUID: UIElement] = [:]
        var kept: [UIElement] = []

        let sorted = elements.sorted { (e1, e2) -> Bool in
            if e1.isSystemOverlay != e2.isSystemOverlay {
                return e1.isSystemOverlay && !e2.isSystemOverlay
            }
            return e1.frame.width * e1.frame.height > e2.frame.width * e2.frame.height
        }

        for elem in sorted {
            var foundOverlap: UUID? = nil

            for keptElem in kept {
                if containerRoles.contains(keptElem.role) { continue }

                let intersection = elem.frame.intersection(keptElem.frame)
                guard intersection.width > 0 && intersection.height > 0 else { continue }

                let overlapArea = intersection.width * intersection.height
                let elemArea = elem.frame.width * elem.frame.height
                let keptArea = keptElem.frame.width * keptElem.frame.height
                let smallerArea = min(elemArea, keptArea)

                guard smallerArea > 0 && (overlapArea / smallerArea) > 0.4 else { continue }

                let elemCenter = CGPoint(x: elem.frame.midX, y: elem.frame.midY)
                let keptCenter = CGPoint(x: keptElem.frame.midX, y: keptElem.frame.midY)
                let distance = hypot(elemCenter.x - keptCenter.x, elemCenter.y - keptCenter.y)
                if distance > 8.0 { continue }

                if keptElem.isSystemOverlay && !elem.isSystemOverlay {
                    foundOverlap = keptElem.id
                    break
                }

                let elemPriority = rolePriority[elem.role] ?? 99
                let keptPriority = rolePriority[keptElem.role] ?? 99
                if elemPriority < keptPriority {
                    foundOverlap = keptElem.id
                }
                break
            }

            if let overlapId = foundOverlap {
                let oldElem = keptDict[overlapId]!
                let elemPriority = rolePriority[elem.role] ?? 99
                let oldPriority = rolePriority[oldElem.role] ?? 99
                if elemPriority < oldPriority {
                    keptDict[overlapId] = elem
                    if let idx = kept.firstIndex(where: { $0.id == overlapId }) {
                        kept[idx] = elem
                    }
                }
            } else {
                keptDict[elem.id] = elem
                kept.append(elem)
            }
        }

        return kept
    }

    func getFocusedElement() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let ref = focused else {
            return nil
        }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    func getScrollArea() -> AXUIElement? {
        let areas = getAllScrollAreas()
        return areas.first?.element
    }

    /// Find ALL scrollable areas — enable accessibility + traverse AX tree
    func getAllScrollAreas() -> [ScrollableArea] {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return [] }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Electron apps require AXManualAccessibility (AXEnhancedUserInterface FAILS on Electron with error -25208)
        let isElectron = isElectronApp(frontApp)
        if isElectron {
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
        } else {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
        }

        // Scan only the frontmost window of the frontmost app to prevent clutter
        var targetWindows: [AXUIElement] = []
        if let frontWindow = getFrontmostWindow(from: appElement) {
            targetWindows = [frontWindow]
        } else {
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement] {
                targetWindows = windows
            }
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
        var allAreas: [ScrollableArea] = []

        for window in targetWindows {
            // Get window frame
            var windowFrame = CGRect.zero
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
            if let p = axPointValue(posRef) { windowFrame.origin = p }
            if let s = axSizeValue(sizeRef) { windowFrame.size = s }

            guard windowFrame.width > 100, windowFrame.height > 100 else { continue }

            // Try to find scroll areas INSIDE the window via AX tree traversal
            var innerAreas: [ScrollableArea] = []

            Log.debug("  Window frame: \(Int(windowFrame.width))×\(Int(windowFrame.height)) @ (\(Int(windowFrame.origin.x)),\(Int(windowFrame.origin.y)))")

            if isElectron {
                findElectronScrollPanels(in: window, windowFrame: windowFrame, depth: 0, results: &innerAreas)
            } else {
                findScrollAreas(in: window, depth: 0, results: &innerAreas)
            }

            if !innerAreas.isEmpty {
                allAreas.append(contentsOf: innerAreas)
            } else {
                // Fallback: only use window as scroll area if it actually has scroll bars
                var hasVerticalBar = false
                var hasHorizontalBar = false
                var verticalRef: CFTypeRef?
                var horizontalRef: CFTypeRef?

                AXUIElementCopyAttributeValue(window, kAXVerticalScrollBarAttribute as CFString, &verticalRef)
                AXUIElementCopyAttributeValue(window, kAXHorizontalScrollBarAttribute as CFString, &horizontalRef)
                hasVerticalBar = verticalRef != nil
                hasHorizontalBar = horizontalRef != nil

                if hasVerticalBar || hasHorizontalBar {
                    let screenFrame = CGRect(
                        origin: CGPoint(x: windowFrame.origin.x, y: primaryHeight - windowFrame.origin.y - windowFrame.height),
                        size: windowFrame.size
                    )
                    allAreas.append(ScrollableArea(element: window, frame: windowFrame, screenFrame: screenFrame))
                }
            }
        }

        // Filter out fullsize window containers (keep only actual panels)
        let filteredAreas = allAreas.filter { area in
            let isWindowSize = (area.frame.width >= windowFrame.width * 0.95) && (area.frame.height >= windowFrame.height * 0.95)
            return !isWindowSize
        }

        let result = deduplicateScrollAreas(filteredAreas.isEmpty ? allAreas : filteredAreas)
        Log.debug("getAllScrollAreas: \(targetWindows.count) windows scanned, \(allAreas.count) raw areas → \(result.count) after dedup")

        // Debug: log each area
        for (i, area) in allAreas.enumerated() {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(area.element, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? "unknown"
            Log.debug("  Area[\(i)]: \(role) frame=\(Int(area.frame.width))×\(Int(area.frame.height)) @ (\(Int(area.frame.origin.x)),\(Int(area.frame.origin.y)))")
        }

        Log.debug("After dedup → \(result.count) areas:")
        for (i, area) in result.enumerated() {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(area.element, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? "unknown"
            Log.debug("  Result[\(i)]: \(role) frame=\(Int(area.frame.width))×\(Int(area.frame.height)) @ (\(Int(area.frame.origin.x)),\(Int(area.frame.origin.y)))")
        }

        return result
    }

    // MARK: - Scroll Area Search Predicate

    /// Find distinct scrollable sub-panels in Electron apps (VSCode, etc.)
    /// Electron doesn't expose AXScrollArea — instead, panels are AXGroup elements
    /// with distinct non-overlapping frames (sidebar, editor, terminal, panel).
    private func isPanelElement(_ element: AXUIElement, windowFrame: CGRect) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return false }

        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        var size = CGSize.zero
        if let s = axSizeValue(sizeRef) { size = s }

        let panelRoles: Set<String> = ["AXGroup", "AXScrollArea", "AXTextArea", "AXWebArea", "AXList", "AXTable", "AXOutline"]

        // Check if it's a recognized panel role and has reasonable size
        guard panelRoles.contains(role) && size.width > 60 && size.height > 60 else {
            Log.debug("    isPanelElement(\(role)): FAIL - role not in \(panelRoles) or size too small (\(Int(size.width))×\(Int(size.height)))")
            return false
        }

        // Allow panels that are smaller than the window (sidebar, bottom panels, etc)
        let widthRatio = size.width / max(windowFrame.width, 1)
        let heightRatio = size.height / max(windowFrame.height, 1)

        let isSidebar = widthRatio < 0.4 && heightRatio > 0.5
        let isBottomPanel = widthRatio > 0.5 && heightRatio < 0.4
        let isMainArea = widthRatio > 0.5 && heightRatio > 0.5

        let result = isSidebar || isBottomPanel || isMainArea
        if result {
            let type = isSidebar ? "SIDEBAR" : (isBottomPanel ? "BOTTOM" : "MAIN")
            Log.debug("    isPanelElement(\(role)): YES (\(type)) w=\(String(format: "%.1f", widthRatio))% h=\(String(format: "%.1f", heightRatio * 100))%")
        } else {
            Log.debug("    isPanelElement(\(role)): NO - ratios w=\(String(format: "%.1f", widthRatio * 100))% h=\(String(format: "%.1f", heightRatio * 100))%")
        }
        return result
    }

    /// Check if element is likely scrollable using multiple indicators
    private func isScrollablePanel(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "unknown"

        // Check role FIRST - some roles are inherently scrollable/are common panel types
        // AXGroup is used for VSCode panels (sidebar, editor, terminal)
        // AXOutline for tree views (GRAPH panel)
        // etc.
        let inherentlyScrollableRoles: Set<String> = ["AXScrollArea", "AXWebArea", "AXWebDocument", "AXList", "AXTable", "AXOutline"]
        let panelRoles: Set<String> = ["AXGroup"]  // AXGroup panels are typically scrollable in VSCode

        if inherentlyScrollableRoles.contains(role) {
            Log.debug("      isScrollable(\(role)): YES - inherent scrollable role")
            return true
        }

        // Check explicit scroll bars (most reliable for detecting actual scrollability)
        var verticalRef: CFTypeRef?
        var horizontalRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXVerticalScrollBarAttribute as CFString, &verticalRef)
        AXUIElementCopyAttributeValue(element, kAXHorizontalScrollBarAttribute as CFString, &horizontalRef)
        if verticalRef != nil || horizontalRef != nil {
            Log.debug("      isScrollable(\(role)): YES - has scroll bar")
            return true
        }

        // Check for AXHasScrollBar attribute (VSCode uses this)
        var hasScrollRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXHasScrollBar" as CFString, &hasScrollRef) == .success {
            Log.debug("      isScrollable(\(role)): YES - AXHasScrollBar")
            return true
        }

        // For panel roles (AXGroup), be more lenient - assume scrollable if it looks like a panel
        if panelRoles.contains(role) {
            Log.debug("      isScrollable(\(role)): YES - panel role (assume scrollable)")
            return true
        }

        // Last resort: check if has content that could be scrolled (AXValue)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
            Log.debug("      isScrollable(\(role)): YES - has AXValue")
            return valueRef != nil
        }

        Log.debug("      isScrollable(\(role)): NO")
        return false
    }

    /// Find distinct scrollable sub-panels in Electron apps (VSCode, etc.)
    /// Electron doesn't expose AXScrollArea — instead, panels are AXGroup elements
    /// with distinct non-overlapping frames (sidebar, editor, terminal, panel).
    private func findElectronScrollPanels(
        in element: AXUIElement,
        windowFrame: CGRect,
        depth: Int,
        results: inout [ScrollableArea]
    ) {
        // Electron trees are deep; we need enough depth to reach the panel level
        guard depth < 30 else { return }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        var point = CGPoint.zero
        var size = CGSize.zero
        if let p = axPointValue(posRef) { point = p }
        if let s = axSizeValue(sizeRef) { size = s }
        let frame = CGRect(origin: point, size: size)

        let isPanel = isPanelElement(element, windowFrame: windowFrame)

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &childrenRef) != .success {
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        }
        let children = childrenRef as? [AXUIElement] ?? []

        if isPanel {
            // Filter immediate children that are panel candidates
            var childPanels: [(AXUIElement, CGSize)] = []
            for child in children {
                if isPanelElement(child, windowFrame: windowFrame) {
                    var childSizeRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &childSizeRef)
                    var childSize = CGSize.zero
                    if let s = axSizeValue(childSizeRef) { childSize = s }
                    childPanels.append((child, childSize))
                }
            }
            
            if childPanels.count >= 2 {
                // Layout container with multiple panels (e.g., VSCode main window)
                // Recurse to find individual panels
                Log.debug("    Panel with \(childPanels.count) children - recursing")
            } else if childPanels.count == 1 {
                let childSize = childPanels[0].1
                if childSize.width >= size.width * 0.95 && childSize.height >= size.height * 0.95 {
                    // Wrapper panel: recurse into single child
                    Log.debug("    Single wrapper child - recursing")
                } else {
                    // Leaf panel with one child: add it if it looks scrollable
                    Log.debug("    Leaf panel with 1 child size=\(Int(childSize.width))×\(Int(childSize.height))")
                    if isScrollablePanel(element) {
                        let area = ScrollableArea(element: element, frame: frame)
                        results.append(area)
                        return
                    }
                }
            } else {
                // No child panels found - this could be a leaf scrollable panel itself
                // (e.g., sidebar outline, terminal, editor content area)
                Log.debug("    No child panels - checking if self is scrollable")
                if isScrollablePanel(element) {
                    let area = ScrollableArea(element: element, frame: frame)
                    results.append(area)
                    return
                }
            }
        }

        for child in children {
            findElectronScrollPanels(in: child, windowFrame: windowFrame, depth: depth + 1, results: &results)
        }
    }

    /// Get the frontmost window directly (like Hopr's frontmostWindow)
    private func getFrontmostWindow(from appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, "AXFrontmostWindow" as CFString, &windowRef) == .success,
           let ref = windowRef {
            return unsafeBitCast(ref, to: AXUIElement.self)
        }
        // Fallback to focused window
        return getFocusedWindow(from: appElement)
    }

    /// Fallback: use NSApplication windows for scroll areas
    private func fallbackScrollAreas() -> [ScrollableArea] {
        var areas: [ScrollableArea] = []
        for window in NSApplication.shared.windows where window.isVisible && window.frame.height > 200 {
            let frame = window.frame
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
            let axFrame = CGRect(
                origin: CGPoint(x: frame.origin.x, y: primaryHeight - frame.origin.y - frame.height),
                size: frame.size
            )
            areas.append(ScrollableArea(element: AXUIElementCreateApplication(0), frame: axFrame))
        }
        return areas
    }

    private func findScrollAreas(in element: AXUIElement, depth: Int, results: inout [ScrollableArea]) {
        guard depth < 15 else { return }

        let role: String? = {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success else { return nil }
            return ref as? String
        }()

        // Handle WebArea specifically (Safari/Chrome web pages)
        if let role, (role == "AXWebArea" || role == "AXWebDocument") {
            if let area = ScrollableArea.from(element) {
                results.append(area)
                // Find sub-scrollable panels inside the web area
                findWebScrollAreas(in: element, webAreaFrame: area.frame, depth: 0, results: &results)
                return // Avoid standard recursion inside webview DOM
            }
        }

        // Standard scroll areas
        if let role, (role == kAXScrollAreaRole as String || role == "AXScrollArea") {
            if let area = ScrollableArea.from(element) {
                results.append(area)
            }
        }

        // VSCode/Electron: AXGroup with actual scroll bars
        if let role, role == "AXGroup" {
            // Only add if it actually has visible scroll bars AND reasonable size
            var hasVerticalBar = false
            var hasHorizontalBar = false
            var verticalRef: CFTypeRef?
            var horizontalRef: CFTypeRef?

            AXUIElementCopyAttributeValue(element, kAXVerticalScrollBarAttribute as CFString, &verticalRef)
            AXUIElementCopyAttributeValue(element, kAXHorizontalScrollBarAttribute as CFString, &horizontalRef)
            hasVerticalBar = verticalRef != nil
            hasHorizontalBar = horizontalRef != nil

            if (hasVerticalBar || hasHorizontalBar), let area = ScrollableArea.from(element) {
                if area.frame.width > 80 && area.frame.height > 80 {
                    results.append(area)
                }
            }
        }

        // Text areas only if they have multiple lines (i.e., scrollable content)
        if let role, role == "AXTextArea" {
            if let area = ScrollableArea.from(element) {
                // Filter out single-line text areas
                if area.frame.height > 40 && area.frame.width > 100 {
                    results.append(area)
                }
            }
        }

        var childrenRef: CFTypeRef?
        // Try AXChildrenInNavigationOrder first (Hopr technique), fallback to AXChildren
        if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &childrenRef) != .success {
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        }
        guard let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            findScrollAreas(in: child, depth: depth + 1, results: &results)
        }
    }

    /// Find web view scrollable areas (AXWebArea, AXGroup with scroll)
    private func findWebViewScrollAreas(in element: AXUIElement, depth: Int, results: inout [ScrollableArea]) {
        guard depth < 15 else { return }

        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           (role == "AXWebArea" || role == "AXWebDocument") {

            if let area = ScrollableArea.from(element) {
                if area.frame.width > 100 && area.frame.height > 100 {
                    results.append(area)
                }
                return // Don't recurse into web content
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            findWebViewScrollAreas(in: child, depth: depth + 1, results: &results)
        }
    }

    /// Find scrollable elements inside a web area (descendants of AXWebArea/AXWebDocument)
    private func findWebScrollAreas(
        in element: AXUIElement,
        webAreaFrame: CGRect,
        depth: Int,
        results: inout [ScrollableArea]
    ) {
        // Chromium trees can be deep, let's allow up to 30 depth
        guard depth < 30 else { return }

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        var point = CGPoint.zero
        var size = CGSize.zero
        if let p = axPointValue(posRef) { point = p }
        if let s = axSizeValue(sizeRef) { size = s }
        let frame = CGRect(origin: point, size: size)

        let isWebScrollCandidate = (role == "AXGroup" || role == "AXScrollArea" || role == "AXList" || role == "AXTable" || role == "AXOutline" || role == "AXTextArea")
            && size.width > 80 && size.height > 80
            && (size.width < webAreaFrame.width * 0.98 || size.height < webAreaFrame.height * 0.98)
            && size.height >= webAreaFrame.height * 0.40

        if isWebScrollCandidate {
            var isScrollable = false
            
            if role == "AXScrollArea" {
                isScrollable = true
            } else {
                // In Chrome/Chromium, scrollable divs have AXFocusableAncestor
                var focusRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, "AXFocusableAncestor" as CFString, &focusRef) == .success {
                    isScrollable = true
                }
                
                // Fallback for Safari (safari uses AXDOMClassList/AXDOMIdentifier but might not have AXFocusableAncestor setup for scrollable elements)
                if !isScrollable {
                    var domIdRef: CFTypeRef?
                    var classRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, "AXDOMIdentifier" as CFString, &domIdRef) == .success
                        || AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &classRef) == .success {
                        isScrollable = true
                    }
                }
            }

            if isScrollable {
                let area = ScrollableArea(element: element, frame: frame)
                results.append(area)
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &childrenRef) != .success {
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        }
        guard let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            findWebScrollAreas(in: child, webAreaFrame: webAreaFrame, depth: depth + 1, results: &results)
        }
    }

    private func deduplicateScrollAreas(_ areas: [ScrollableArea]) -> [ScrollableArea] {
        guard areas.count > 1 else { return areas }

        // First, remove near-duplicate areas (Electron has nested AXGroups with frames
        // differing by 1-2px)
        var uniqueAreas: [ScrollableArea] = []
        let tolerance: CGFloat = 10

        Log.debug("Dedup phase 1 - Remove near-duplicates (tolerance=\(Int(tolerance))px):")
        for area in areas {
            let isDuplicate = uniqueAreas.contains { existing in
                abs(existing.frame.origin.x - area.frame.origin.x) < tolerance
                && abs(existing.frame.origin.y - area.frame.origin.y) < tolerance
                && abs(existing.frame.width - area.frame.width) < tolerance
                && abs(existing.frame.height - area.frame.height) < tolerance
            }
            if isDuplicate {
                Log.debug("  SKIP (duplicate): \(Int(area.frame.width))×\(Int(area.frame.height))")
            } else {
                Log.debug("  KEEP: \(Int(area.frame.width))×\(Int(area.frame.height))")
                uniqueAreas.append(area)
            }
        }

        // Remove only VERY nested areas (>95% contained, minimal padding)
        // Keep separate panels (chat, terminal, sidebar) even if they share parent window
        var kept: [ScrollableArea] = []

        Log.debug("Dedup phase 2 - Remove deeply nested areas (>95% overlap):")
        for area in uniqueAreas {
            var isDeeplyNested = false

            for other in uniqueAreas {
                if other.frame == area.frame { continue }

                // Only filter if area is EXTREMELY nested (>95% overlap AND fully contained)
                let intersection = area.frame.intersection(other.frame)
                let areaSize = area.frame.width * area.frame.height
                guard areaSize > 0 else { continue }

                let overlapRatio = (intersection.width * intersection.height) / areaSize
                // Very high threshold to keep separate panels like chat & terminal
                if overlapRatio > 0.95 && other.frame.contains(area.frame) {
                    Log.debug("  FILTER: \(Int(area.frame.width))×\(Int(area.frame.height)) nested in \(Int(other.frame.width))×\(Int(other.frame.height)) (overlap=\(String(format: "%.1f", overlapRatio * 100))%)")
                    isDeeplyNested = true
                    break
                }
            }

            if !isDeeplyNested {
                Log.debug("  KEEP: \(Int(area.frame.width))×\(Int(area.frame.height))")
                kept.append(area)
            }
        }
        return kept
    }

    // MARK: - Disk Cache (Hint Snapshots)

    /// Save hint elements to disk so next activation is instant (even after app restart).
    func saveHintSnapshot(elements: [UIElement], bundleID: String) {
        let nonOverlay = elements.filter { !$0.isSystemOverlay }
        guard !nonOverlay.isEmpty else { return }

        let snapshot = HintSnapshot(
            bundleID: bundleID,
            timestamp: Date().timeIntervalSince1970,
            elements: nonOverlay.map { ElementSnapshot($0) }
        )

        cacheQueue.sync {
            diskCache[bundleID] = snapshot
        }

        // Write to disk asynchronously
        DispatchQueue.global(qos: .utility).async { [diskCacheDir, maxDiskCacheApps] in
            let fileURL = diskCacheDir.appendingPathComponent("\(bundleID).json")
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: fileURL, options: .atomic)
            }
            self.cleanupOldDiskCaches(maxKeep: maxDiskCacheApps)
        }
    }

    /// Load a hint snapshot from disk for instant display.
    func loadHintSnapshot(for bundleID: String) -> [UIElement]? {
        // Check in-memory cache first
        let cached: HintSnapshot? = cacheQueue.sync {
            diskCache[bundleID]
        }
        if let cached = cached {
            return cached.elements.map { $0.toUIElement() }
        }
        return nil
    }

    /// Load all disk cache files into memory on startup.
    func loadDiskCache() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: diskCacheDir, includingPropertiesForKeys: nil) else { return }

        var cache: [String: HintSnapshot] = [:]
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let snapshot = try? JSONDecoder().decode(HintSnapshot.self, from: data) {
                cache[snapshot.bundleID] = snapshot
            }
        }

        cacheQueue.sync {
            diskCache = cache
        }
        Log.info("Disk hint cache loaded: \(cache.count) apps")
    }

    /// Remove disk cache files for apps no longer running.
    func cleanupOldDiskCaches(maxKeep: Int = 10) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: diskCacheDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        // Sort by modification date (newest first)
        let sorted = files
            .filter { $0.pathExtension == "json" }
            .sorted { f1, f2 in
                let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }

        // Remove oldest beyond maxKeep
        for file in sorted.dropFirst(maxKeep) {
            try? fm.removeItem(at: file)
        }
    }
}
