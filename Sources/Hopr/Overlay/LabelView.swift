import Cocoa

enum LabelPosition {
    case above  // pointer points down, label above element
    case below  // pointer points up, label below element
    case left   // pointer points right, label to the left of element
    case right  // pointer points left, label to the right of element
}

/// Memoized text/label measurement for hint bubbles.
///
/// `NSString.size(withAttributes:)` runs a full text-layout pass. It was being called
/// ~5× per element on every overlay build (4× in auto-placement + once for the view's
/// intrinsic size), and overlay builds happen on every keystroke while filtering hints.
/// Hint labels are short and there are only a handful of distinct ones, so a tiny memo
/// keyed by font size + text collapses all of that to a single measurement each.
/// Main-thread only — all overlay/label work runs on the main thread.
enum LabelMetrics {
    private static var textSizeCache: [String: CGSize] = [:]

    /// Font size for a label, matching the rule used everywhere the bubble is drawn/measured.
    static func fontSize(for label: String) -> CGFloat {
        let base = CGFloat(AppSettings.shared.labelSize)
        return label.count <= 2 ? max(8.5, base * 0.65) : max(7.5, base * 0.57)
    }

    /// Cached bare text size (depends only on the text and font size).
    static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let key = "\(fontSize)|\(text)"
        if let cached = textSizeCache[key] { return cached }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        textSizeCache[key] = size
        return size
    }

    /// Full label bubble size (text + padding + pointer) for a given placement.
    static func labelSize(for label: String, position: LabelPosition) -> CGSize {
        guard !label.isEmpty else { return CGSize(width: 14, height: 14) }
        let ts = textSize(label, fontSize: fontSize(for: label))
        let bubbleW = ts.width + 5      // Compact horizontal padding
        let bubbleH = ts.height + 2.5   // Compact vertical padding
        let pointerH: CGFloat = 5.5     // Shortened pointer
        switch position {
        case .above, .below:
            return CGSize(width: max(bubbleW, 14), height: bubbleH + pointerH)
        case .left, .right:
            return CGSize(width: max(bubbleW + pointerH, 14), height: bubbleH)
        }
    }
}

class LabelView: NSView {

    let label: String
    private let position: LabelPosition
    var isHit = false {
        didSet { needsDisplay = true }
    }
    var typedPrefix: String = "" {
        didSet { if typedPrefix != oldValue { needsDisplay = true } }
    }

    init(label: String, position: LabelPosition = .above) {
        self.label = label
        self.position = position
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        // Drop shadow — colored glow is drawn in draw() via NSGraphicsContext
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 5
    }

    // MARK: - Animations

    func animateIn() {
        guard let layer = self.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = CATransform3DMakeScale(0.55, 0.55, 1.0)
        CATransaction.commit()

        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.55
        scale.toValue = 1.0
        scale.damping = 16
        scale.initialVelocity = 8
        scale.mass = 0.55
        scale.duration = scale.settlingDuration
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1.0
        fade.duration = 0.09
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false

        layer.add(scale, forKey: "animIn_scale")
        layer.add(fade,  forKey: "animIn_opacity")

        DispatchQueue.main.asyncAfter(deadline: .now() + scale.settlingDuration) { [weak layer] in
            layer?.removeAnimation(forKey: "animIn_scale")
            layer?.removeAnimation(forKey: "animIn_opacity")
            layer?.opacity = 1
            layer?.transform = CATransform3DIdentity
        }
    }

    func animatePulse() {
        guard let layer = self.layer else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.78
        spring.toValue = 1.0
        spring.damping = 11
        spring.initialVelocity = 6
        spring.mass = 0.5
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pulse")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func drawText(in rect: NSRect, fontSize: CGFloat) {
        let textColor: NSColor = isHit ? .white : AppSettings.shared.labelThemeColors.text
        let isLight = isHit ? false : AppSettings.shared.labelThemeColors.background.isPerceptuallyLight

        let baseShadow = NSShadow()
        baseShadow.shadowColor = isLight ? NSColor.white.withAlphaComponent(0.6) : NSColor.black.withAlphaComponent(0.5)
        baseShadow.shadowOffset = CGSize(width: 0, height: -0.75)
        baseShadow.shadowBlurRadius = 0.5

        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let textSize = LabelMetrics.textSize(label, fontSize: fontSize)
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2 - 0.5,
            width: textSize.width,
            height: textSize.height
        )

        let prefixLen = typedPrefix.count
        let hasActivePrefix = !isHit && prefixLen > 0 && prefixLen < label.count
            && label.uppercased().hasPrefix(typedPrefix.uppercased())

        if hasActivePrefix {
            // Remaining chars get a warm glow so they pop against the dimmed prefix
            let remainingGlow = NSShadow()
            remainingGlow.shadowColor = textColor.withAlphaComponent(0.65)
            remainingGlow.shadowOffset = .zero
            remainingGlow.shadowBlurRadius = 4.0

            let attrStr = NSMutableAttributedString(string: label)
            attrStr.addAttributes([
                .font: font,
                .foregroundColor: textColor.withAlphaComponent(0.22),
                .shadow: baseShadow,
            ], range: NSRange(location: 0, length: prefixLen))
            attrStr.addAttributes([
                .font: font,
                .foregroundColor: textColor,
                .shadow: remainingGlow,
            ], range: NSRange(location: prefixLen, length: label.count - prefixLen))
            attrStr.draw(in: textRect)
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .shadow: baseShadow,
            .paragraphStyle: {
                let ps = NSMutableParagraphStyle()
                ps.alignment = .center
                return ps
            }(),
        ]
        (label as NSString).draw(in: textRect, withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !label.isEmpty, bounds.width > 1, bounds.height > 1 else { return }

        // Base font size from user setting; clamp for tiny multi-char labels
        let fontSize = LabelMetrics.fontSize(for: label)
        let pointerH: CGFloat = 5.5 // Shortened pointer
        let pointerW: CGFloat = 8
        let radius: CGFloat = 2.5 // Sharper corners for compact labels

        let bubbleW: CGFloat
        let bubbleH: CGFloat
        switch position {
        case .above, .below:
            bubbleW = bounds.width
            bubbleH = bounds.height - pointerH
        case .left, .right:
            bubbleW = bounds.width - pointerH
            bubbleH = bounds.height
        }

        let bubbleRect: NSRect
        let pointerPath = NSBezierPath()

        switch position {
        case .above:
            // Label above element, pointer points DOWN
            bubbleRect = NSRect(
                x: 0,
                y: pointerH,
                width: bubbleW,
                height: bubbleH
            )
            let triCenterX = bounds.midX
            pointerPath.move(to: NSPoint(x: triCenterX - pointerW / 2, y: bubbleRect.minY))
            pointerPath.line(to: NSPoint(x: triCenterX, y: 0))
            pointerPath.line(to: NSPoint(x: triCenterX + pointerW / 2, y: bubbleRect.minY))

        case .below:
            // Label below element, pointer points UP
            bubbleRect = NSRect(
                x: 0,
                y: 0,
                width: bubbleW,
                height: bubbleH
            )
            let triCenterX = bounds.midX
            pointerPath.move(to: NSPoint(x: triCenterX - pointerW / 2, y: bubbleRect.maxY))
            pointerPath.line(to: NSPoint(x: triCenterX, y: bounds.height))
            pointerPath.line(to: NSPoint(x: triCenterX + pointerW / 2, y: bubbleRect.maxY))

        case .left:
            // Label left of element, pointer points RIGHT
            bubbleRect = NSRect(
                x: 0,
                y: 0,
                width: bubbleW,
                height: bubbleH
            )
            let triCenterY = bounds.midY
            pointerPath.move(to: NSPoint(x: bubbleRect.maxX, y: triCenterY - pointerW / 2))
            pointerPath.line(to: NSPoint(x: bounds.width, y: triCenterY))
            pointerPath.line(to: NSPoint(x: bubbleRect.maxX, y: triCenterY + pointerW / 2))

        case .right:
            // Label right of element, pointer points LEFT
            bubbleRect = NSRect(
                x: pointerH,
                y: 0,
                width: bubbleW,
                height: bubbleH
            )
            let triCenterY = bounds.midY
            pointerPath.move(to: NSPoint(x: bubbleRect.minX, y: triCenterY - pointerW / 2))
            pointerPath.line(to: NSPoint(x: 0, y: triCenterY))
            pointerPath.line(to: NSPoint(x: bubbleRect.minX, y: triCenterY + pointerW / 2))
        }

        // Bubble body
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: radius, yRadius: radius)

        // Combine bubble + pointer
        let fullPath = NSBezierPath()
        fullPath.append(bubblePath)
        fullPath.move(to: pointerPath.currentPoint)
        // Trace pointer
        switch position {
        case .above:
            let triCenterX = bounds.midX
            fullPath.move(to: NSPoint(x: triCenterX - pointerW / 2, y: bubbleRect.minY))
            fullPath.line(to: NSPoint(x: triCenterX, y: 0))
            fullPath.line(to: NSPoint(x: triCenterX + pointerW / 2, y: bubbleRect.minY))
        case .below:
            let triCenterX = bounds.midX
            fullPath.move(to: NSPoint(x: triCenterX - pointerW / 2, y: bubbleRect.maxY))
            fullPath.line(to: NSPoint(x: triCenterX, y: bounds.height))
            fullPath.line(to: NSPoint(x: triCenterX + pointerW / 2, y: bubbleRect.maxY))
        case .left:
            let triCenterY = bounds.midY
            fullPath.move(to: NSPoint(x: bubbleRect.maxX, y: triCenterY - pointerW / 2))
            fullPath.line(to: NSPoint(x: bounds.width, y: triCenterY))
            fullPath.line(to: NSPoint(x: bubbleRect.maxX, y: triCenterY + pointerW / 2))
        case .right:
            let triCenterY = bounds.midY
            fullPath.move(to: NSPoint(x: bubbleRect.minX, y: triCenterY - pointerW / 2))
            fullPath.line(to: NSPoint(x: 0, y: triCenterY))
            fullPath.line(to: NSPoint(x: bubbleRect.minX, y: triCenterY + pointerW / 2))
        }

        // Fill and Stroke Colors — driven by AppSettings.theme
        let bgColor: NSColor
        let borderColor: NSColor
        if isHit {
            bgColor = NSColor(calibratedRed: 0.15, green: 0.85, blue: 0.35, alpha: 0.95)
            borderColor = NSColor.white.withAlphaComponent(0.2)
        } else {
            let themeColors = AppSettings.shared.labelThemeColors
            bgColor = themeColors.background.withAlphaComponent(0.95)
            borderColor = themeColors.background.blended(withFraction: 0.35, of: .black)?.withAlphaComponent(0.45)
                ?? NSColor.black.withAlphaComponent(0.2)
        }

        // Colored glow — drawn BEFORE the bubble so it sits behind it.
        // Uses an NSShadow with zero offset so it spreads as a halo.
        NSGraphicsContext.saveGraphicsState()
        let glowShadow = NSShadow()
        glowShadow.shadowColor = bgColor.withAlphaComponent(isHit ? 0.75 : 0.55)
        glowShadow.shadowBlurRadius = isHit ? 11 : 8
        glowShadow.shadowOffset = .zero
        glowShadow.set()
        // Draw near-transparent fill — only the shadow (glow) is visible
        bgColor.withAlphaComponent(0.01).setFill()
        fullPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 3D vertical gradient (lighter at top, darker at bottom)
        let isLight = bgColor.isPerceptuallyLight
        let topBlend: CGFloat = isLight ? 0.25 : 0.38
        let bottomBlend: CGFloat = isLight ? 0.15 : 0.22
        let topColor = bgColor.blended(withFraction: topBlend, of: .white) ?? bgColor
        let bottomColor = bgColor.blended(withFraction: bottomBlend, of: .black) ?? bgColor

        if let gradient = NSGradient(starting: bottomColor, ending: topColor) {
            gradient.draw(in: fullPath, angle: 90)
        } else {
            bgColor.setFill()
            fullPath.fill()
        }

        // Inner 3D Bevel/Highlight inside the bubble body
        let innerHighlightColor = NSColor.white.withAlphaComponent(isLight ? 0.50 : 0.25)
        let innerShadowColor = NSColor.black.withAlphaComponent(isLight ? 0.14 : 0.30)
        let bevelRect = bubbleRect.insetBy(dx: 0.75, dy: 0.75)
        let bevelRadius = max(0.5, radius - 0.5)

        // 1. Draw bottom shadow offset slightly down
        let shadowPath = NSBezierPath(roundedRect: bevelRect.offsetBy(dx: 0, dy: -0.5), xRadius: bevelRadius, yRadius: bevelRadius)
        innerShadowColor.setStroke()
        shadowPath.lineWidth = 0.5
        shadowPath.stroke()

        // 2. Draw top highlight offset slightly up
        let highlightPath = NSBezierPath(roundedRect: bevelRect.offsetBy(dx: 0, dy: 0.5), xRadius: bevelRadius, yRadius: bevelRadius)
        innerHighlightColor.setStroke()
        highlightPath.lineWidth = 0.5
        highlightPath.stroke()

        // 3. Draw outer border on top to clean up edges
        borderColor.setStroke()
        fullPath.lineWidth = 0.75
        fullPath.stroke()

        // Text
        drawText(in: bubbleRect, fontSize: fontSize)
    }

    override var intrinsicContentSize: NSSize {
        LabelMetrics.labelSize(for: label, position: position)
    }

    func animateHit(completion: @escaping () -> Void) {
        isHit = true
        
        // Play hit sound effect
        SoundManager.shared.playActivate()
        
        guard let layer = self.layer else {
            completion()
            return
        }
        
        let oldFrame = self.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: oldFrame.midX, y: oldFrame.midY)
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock {
            completion()
        }
        
        // Scale to 1.4x
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 1.4
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false
        layer.add(scaleAnim, forKey: "scale")
        
        // Fade out
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 1.0
        opacityAnim.toValue = 0.0
        opacityAnim.fillMode = .forwards
        opacityAnim.isRemovedOnCompletion = false
        layer.add(opacityAnim, forKey: "opacity")
        
        CATransaction.commit()
    }
}
