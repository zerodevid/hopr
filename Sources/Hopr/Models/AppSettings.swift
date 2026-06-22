import SwiftUI
import ServiceManagement

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // General — label color stored as hex string; replaces the old "theme" enum
    @AppStorage("labelBgColorHex") var labelBgColorHex: String = "#007AFF"  // system blue default
    @AppStorage("labelSize") var labelSize: Double = 14
    @AppStorage("showMenubarIcon") var showMenubarIcon: Bool = true
    @AppStorage("modeIndicatorPosition") var modeIndicatorPosition: String = "top"
    @AppStorage("hintPlacement") var hintPlacement: String = "auto" // options: "aboveBelow", "leftRight", "left", "right", "auto"
    @AppStorage("showModeNotification") var showModeNotification: Bool = true

    // Clicking
    @AppStorage("autoClick") var autoClick: Bool = true
    @AppStorage("chainClicks") var chainClicks: Bool = false
    @AppStorage("labelCharacters") var labelCharacters: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    @AppStorage("hideLabelsBeforeSearch") var hideLabelsBeforeSearch: Bool = false

    // Scrolling
    @AppStorage("showScrollAreaNumbers") var showScrollAreaNumbers: Bool = true
    @AppStorage("scrollSpeed") var scrollSpeed: Double = 8
    @AppStorage("dashSpeed") var dashSpeed: Double = 60
    @AppStorage("scrollKeyUp") var scrollKeyUp: Int = 38         // J (kVK_ANSI_J)
    @AppStorage("scrollKeyDown") var scrollKeyDown: Int = 40     // K (kVK_ANSI_K)
    @AppStorage("scrollKeyLeft") var scrollKeyLeft: Int = 4       // H (kVK_ANSI_H)
    @AppStorage("scrollKeyRight") var scrollKeyRight: Int = 37     // L (kVK_ANSI_L)

    // Mouse
    @AppStorage("mouseSpeed") var mouseSpeed: Double = 12
    @AppStorage("mouseFastSpeed") var mouseFastSpeed: Double = 40
    @AppStorage("mouseDragDelay") var mouseDragDelay: Double = 0.20
    @AppStorage("mouseKeyUp") var mouseKeyUp: Int = 13           // W (kVK_ANSI_W)
    @AppStorage("mouseKeyDown") var mouseKeyDown: Int = 1        // S (kVK_ANSI_S)
    @AppStorage("mouseKeyLeft") var mouseKeyLeft: Int = 0        // A (kVK_ANSI_A)
    @AppStorage("mouseKeyRight") var mouseKeyRight: Int = 2      // D (kVK_ANSI_D)

    // Ignored Apps
    @AppStorage("ignoredApps") var ignoredAppsData: Data = Data()

    // Global Shortcuts stored as JSON Data
    @AppStorage("hintShortcutData") private var hintShortcutData: Data = Data()
    @AppStorage("scrollShortcutData") private var scrollShortcutData: Data = Data()
    @AppStorage("mouseShortcutData") private var mouseShortcutData: Data = Data()
    @AppStorage("searchShortcutData") private var searchShortcutData: Data = Data()
    @AppStorage("focusTextShortcutData") private var focusTextShortcutData: Data = Data()

    // Launch at login setting synced with SMAppService
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet {
            syncLaunchAtLogin()
        }
    }

    var ignoredApps: [String] {
        get { (try? JSONDecoder().decode([String].self, from: ignoredAppsData)) ?? [] }
        set { ignoredAppsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var labelFont: NSFont {
        NSFont.systemFont(ofSize: CGFloat(labelSize), weight: .semibold)
    }

    /// Derived label colors: background from stored hex, text auto-chosen for contrast.
    var labelThemeColors: (background: NSColor, text: NSColor) {
        let bg = NSColor(hex: labelBgColorHex) ?? .controlAccentColor
        let text: NSColor = bg.isPerceptuallyLight ? .black : .white
        return (background: bg, text: text)
    }

    /// `SMAppService.mainApp` only works when the process is running from a real,
    /// code-signed `.app` bundle. Running the bare SwiftPM executable (e.g. via
    /// `swift run` or the VSCode Swift extension) makes `register()` fail with
    /// `SMAppServiceErrorDomain Code=22 (Invalid argument)`. Detect that here so we
    /// can skip registration gracefully instead of logging an opaque error.
    private var canUseLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    init() {
        // Synchronize initial state of launch at login from system SMAppService
        if canUseLaunchAtLogin {
            self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }

        // Migrate old copy-pasted default mouse keys (J,K,H,L) to WASD (13, 1, 0, 2)
        if mouseKeyUp == 38 && mouseKeyDown == 40 && mouseKeyLeft == 4 && mouseKeyRight == 37 {
            mouseKeyUp = 13
            mouseKeyDown = 1
            mouseKeyLeft = 0
            mouseKeyRight = 2
        }
    }

    func isAppIgnored(_ bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return ignoredApps.contains(id)
    }

    // MARK: - Global Shortcuts Getters/Setters

    var hintShortcut: KeyCombo {
        get {
            if let combo = try? JSONDecoder().decode(KeyCombo.self, from: hintShortcutData) {
                return combo
            }
            // Default: Cmd + Shift + Space
            let cmdAndShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
            return KeyCombo(keyCode: 49, modifiers: cmdAndShift) // 49 is Space
        }
        set {
            hintShortcutData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
        }
    }

    var scrollShortcut: KeyCombo {
        get {
            if let combo = try? JSONDecoder().decode(KeyCombo.self, from: scrollShortcutData) {
                return combo
            }
            // Default: Cmd + Shift + J
            let cmdAndShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
            return KeyCombo(keyCode: 38, modifiers: cmdAndShift) // 38 is J
        }
        set {
            scrollShortcutData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
        }
    }

    var mouseShortcut: KeyCombo {
        get {
            if let combo = try? JSONDecoder().decode(KeyCombo.self, from: mouseShortcutData) {
                return combo
            }
            // Default: Cmd + Shift + M
            let cmdAndShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
            return KeyCombo(keyCode: 46, modifiers: cmdAndShift) // 46 is M
        }
        set {
            mouseShortcutData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
        }
    }

    var focusTextShortcut: KeyCombo {
        get {
            if let combo = try? JSONDecoder().decode(KeyCombo.self, from: focusTextShortcutData) {
                return combo
            }
            // Default: Cmd + Shift + E
            let cmdAndShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
            return KeyCombo(keyCode: 14, modifiers: cmdAndShift) // 14 is E
        }
        set {
            focusTextShortcutData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
        }
    }

    var searchShortcut: KeyCombo {
        get {
            if let combo = try? JSONDecoder().decode(KeyCombo.self, from: searchShortcutData) {
                return combo
            }
            // Default: Cmd + Shift + /
            let cmdAndShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
            return KeyCombo(keyCode: 44, modifiers: cmdAndShift) // 44 is Slash
        }
        set {
            searchShortcutData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
        }
    }

    // MARK: - Launch at Login Sync

    func syncLaunchAtLogin() {
        guard canUseLaunchAtLogin else {
            Log.info("Launch at Login unavailable: Hopr is running as a bare executable, not a signed .app bundle. Build/run Hopr.app to enable it.")
            return
        }
        let status = SMAppService.mainApp.status
        if launchAtLogin && status != .enabled {
            do {
                try SMAppService.mainApp.register()
                Log.info("Registered launch at login successfully")
            } catch {
                Log.error("SMAppService registration failed: \(error)")
                // Registration failed — keep the UI toggle in sync with reality.
                DispatchQueue.main.async { self.launchAtLogin = false }
            }
        } else if !launchAtLogin && status == .enabled {
            do {
                try SMAppService.mainApp.unregister()
                Log.info("Unregistered launch at login successfully")
            } catch {
                Log.error("SMAppService unregistration failed: \(error)")
            }
        }
    }

    // MARK: - Reset Settings Helpers

    func resetGeneralSettings() {
        labelBgColorHex = "#007AFF"
        labelSize = 14
        showMenubarIcon = true
        modeIndicatorPosition = "top"
        hintPlacement = "auto"
        
        // Reset shortcuts
        hintShortcutData = Data()
        scrollShortcutData = Data()
        mouseShortcutData = Data()
        searchShortcutData = Data()
        focusTextShortcutData = Data()
        launchAtLogin = false
        showModeNotification = true
    }

    func resetClickingSettings() {
        autoClick = true
        chainClicks = false
        labelCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        hideLabelsBeforeSearch = false
    }

    func resetScrollingSettings() {
        showScrollAreaNumbers = true
        scrollSpeed = 8
        dashSpeed = 60
        scrollKeyUp = 38
        scrollKeyDown = 40
        scrollKeyLeft = 4
        scrollKeyRight = 37
    }

    func resetMouseSettings() {
        mouseSpeed = 12
        mouseFastSpeed = 40
        mouseDragDelay = 0.20
        mouseKeyUp = 13
        mouseKeyDown = 1
        mouseKeyLeft = 0
        mouseKeyRight = 2
    }

    func resetIgnoredAppsSettings() {
        ignoredApps = []
    }
}

