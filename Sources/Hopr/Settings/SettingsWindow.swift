import Cocoa
import SwiftUI

// MARK: - Tab identifier enum
enum SettingsTab: String, CaseIterable {
    case general   = "General"
    case clicking  = "Clicking"
    case scrolling = "Scrolling"
    case mouse     = "Mouse"
    case ignored   = "Ignored Apps"
    case about     = "About"

    var icon: String {
        switch self {
        case .general:  return "gearshape.2.fill"
        case .clicking: return "hand.point.up.left.fill"
        case .scrolling: return "arrow.up.arrow.down.circle.fill"
        case .mouse:    return "computermouse.fill"
        case .ignored:  return "xmark.app.fill"
        case .about:    return "info.bubble.fill"
        }
    }
}

// MARK: - Toolbar delegate
final class SettingsToolbarDelegate: NSObject, NSToolbarDelegate {
    var tabs: [SettingsTab] = SettingsTab.allCases
    var onSelect: ((SettingsTab) -> Void)?

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.rawValue) } + [.flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = tabs.first(where: { $0.rawValue == itemIdentifier.rawValue }) else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.rawValue
        item.paletteLabel = tab.rawValue
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.rawValue)
        item.target = self
        item.action = #selector(tabSelected(_:))
        return item
    }

    @objc private func tabSelected(_ sender: NSToolbarItem) {
        if let tab = tabs.first(where: { $0.rawValue == sender.itemIdentifier.rawValue }) {
            onSelect?(tab)
        }
    }
}

// MARK: - Settings Window
final class SettingsWindow: NSObject {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var toolbarDelegate: SettingsToolbarDelegate?
    private var currentTab: SettingsTab = .general

    private override init() {}

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        buildWindow()
    }

    private func buildWindow() {
        // Hosting controller with initial tab
        let hostingVC = makeHostingController(for: currentTab)
        hostingController = hostingVC

        let win = NSWindow(contentViewController: hostingVC)
        win.title = currentTab.rawValue
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(contentSize(for: currentTab))
        win.center()
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = false
        win.titleVisibility = .hidden   // title hidden; toolbar shows tab name

        // Toolbar
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        let delegate = SettingsToolbarDelegate()
        delegate.onSelect = { [weak self] tab in
            self?.switchTo(tab)
        }
        toolbar.delegate = delegate
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(currentTab.rawValue)

        win.toolbar = toolbar
        toolbarDelegate = delegate

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func switchTo(_ tab: SettingsTab) {
        currentTab = tab
        window?.title = tab.rawValue
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)

        let newVC = makeHostingController(for: tab)
        hostingController = newVC

        let size = contentSize(for: tab)
        window?.contentViewController = newVC

        // Animate size change
        if let win = window {
            var frame = win.frame
            let delta = size.height - win.contentView!.frame.height
            frame.origin.y -= delta
            frame.size = NSSize(width: size.width, height: win.frame.height + delta)
            win.setFrame(frame, display: true, animate: true)
            win.setContentSize(size)
        }
    }

    private func makeHostingController(for tab: SettingsTab) -> NSHostingController<AnyView> {
        let view: AnyView
        switch tab {
        case .general:   view = AnyView(GeneralTab())
        case .clicking:  view = AnyView(ClickingTab())
        case .scrolling: view = AnyView(ScrollingTab())
        case .mouse:     view = AnyView(MouseTab())
        case .ignored:   view = AnyView(IgnoredAppsTab())
        case .about:     view = AnyView(AboutTab())
        }
        let vc = NSHostingController(rootView: view)
        vc.view.setFrameSize(contentSize(for: tab))
        return vc
    }

    private func contentSize(for tab: SettingsTab) -> NSSize {
        switch tab {
        case .general:   return NSSize(width: 580, height: 630)
        case .clicking:  return NSSize(width: 580, height: 470)
        case .scrolling: return NSSize(width: 580, height: 350)
        case .mouse:     return NSSize(width: 580, height: 380)
        case .ignored:   return NSSize(width: 580, height: 400)
        case .about:     return NSSize(width: 580, height: 400)
        }
    }
}
