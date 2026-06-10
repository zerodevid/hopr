import Cocoa

final class ModeIndicator {

    private var window: NSWindow?

    func show(mode: AppMode, isLoading: Bool = false) {
        switch mode {
        case .idle:
            hide()
            return
        case .hint:
            if isLoading {
                showPill(icon: "arrow.triangle.2.circlepath", text: "Hint — Loading hints...", color: .systemYellow, shouldRotate: true)
            } else {
                showPill(icon: "cursorarrow.click.2", text: "Hint — ⇧ Right-Click · ⌘ Double-Click · ⌃ Hover · ⌥ Drag", color: .systemYellow, shouldRotate: false)
            }
        case .scroll:
            showPill(icon: "scroll", text: "Scroll — 1-9 select · J↓ K↑ H← L→", color: .systemGreen, shouldRotate: false)
        case .search:
            showPill(icon: "magnifyingglass", text: "Search — type to filter · Enter to click", color: .systemBlue, shouldRotate: false)
        case .mouse:
            showPill(icon: "computermouse", text: "Mouse — WASD move · Q click (hold: drag) · E right-click · ←↓↑→ scroll · Esc exit", color: .systemPurple, shouldRotate: false)
        case .focusText:
            showPill(icon: "text.cursor", text: "Focus Text — type label to focus input field · Esc exit", color: .systemCyan, shouldRotate: false)
        }
    }

    func hide() {
        guard let win = window else { return }
        self.window = nil
        
        let currentFrame = win.frame
        let position = AppSettings.shared.modeIndicatorPosition
        let offset = (position == "bottom" || position == "center") ? -10.0 : 10.0
        let targetFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + offset,
            width: currentFrame.size.width,
            height: currentFrame.size.height
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0.0
            win.animator().setFrame(targetFrame, display: true)
        }) {
            win.orderOut(nil)
        }
    }

    func updatePill(icon: String, text: String, color: NSColor, shouldRotate: Bool = false) {
        showPill(icon: icon, text: text, color: color, shouldRotate: shouldRotate)
    }

    private func showPill(icon: String, text: String, color: NSColor, shouldRotate: Bool = false) {
        if window == nil {
            createWindow()
        }
        guard let window = window else { return }
        // Build content view with vibrancy
        let contentView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
        contentView.material = .hudWindow
        contentView.state = .active
        contentView.blendingMode = .behindWindow
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.masksToBounds = true

        // Icon
        let iconHeight: CGFloat = 20
        let iconView = RotatingImageView(frame: NSRect(x: 12, y: (32 - iconHeight) / 2, width: 20, height: 20))
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: text) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(config)
            iconView.contentTintColor = color
        }
        
        contentView.addSubview(iconView)
        iconView.isRotating = shouldRotate

        // Text
        let label = NSTextField(frame: NSRect(x: 40, y: 6, width: 800, height: 20))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        label.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.sizeToFit()
        label.frame.origin.y = (32 - label.frame.height) / 2 - 0.5
        contentView.addSubview(label)

        // Resize window to fit
        let totalWidth = label.frame.maxX + 16
        window.contentView = contentView

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let position = AppSettings.shared.modeIndicatorPosition
            let targetY: CGFloat
            if position == "bottom" {
                targetY = sf.minY + 20
            } else if position == "center" {
                targetY = sf.midY - 16
            } else {
                targetY = sf.maxY - 42
            }
            let targetFrame = NSRect(
                x: sf.midX - totalWidth / 2,
                y: targetY,
                width: totalWidth,
                height: 32
            )
            
            let wasVisible = window.isVisible && window.alphaValue > 0.0
            
            if !wasVisible {
                window.alphaValue = 0.0
                let startOffset = (position == "bottom" || position == "center") ? -10.0 : 10.0
                window.setFrame(NSRect(
                    x: targetFrame.origin.x,
                    y: targetFrame.origin.y + startOffset,
                    width: targetFrame.size.width,
                    height: targetFrame.size.height
                ), display: true)
                window.orderFrontRegardless()
            }
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
                window.animator().setFrame(targetFrame, display: true)
            }, completionHandler: nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    private func createWindow() {
        let win = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false
        self.window = win
    }
}

final class RotatingImageView: NSImageView {
    var isRotating: Bool = false {
        didSet {
            updateRotation()
        }
    }
    
    override func layout() {
        super.layout()
        if self.wantsLayer, let layer = self.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: self.frame.midX, y: self.frame.midY)
        }
    }
    
    private func updateRotation() {
        self.wantsLayer = true
        self.layer?.removeAnimation(forKey: "loadingRotation")
        if isRotating {
            let rotation = CABasicAnimation(keyPath: "transform.rotation")
            rotation.fromValue = 0
            rotation.toValue = -Double.pi * 2.0
            rotation.duration = 1.0
            rotation.repeatCount = .infinity
            self.layer?.add(rotation, forKey: "loadingRotation")
        }
    }
}
