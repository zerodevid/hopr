import Cocoa

enum LabelPosition {
    case above  // pointer points down, label above element
    case below  // pointer points up, label below element
    case left   // pointer points right, label to the left of element
    case right  // pointer points left, label to the right of element
}

class LabelView: NSView {

    let label: String
    private let position: LabelPosition
    var isHit = false {
        didSet {
            needsDisplay = true
        }
    }

    init(label: String, position: LabelPosition = .above) {
        self.label = label
        self.position = position
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowOffset = CGSize(width: 0, height: -2.5)
        layer?.shadowRadius = 3.5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func drawText(in rect: NSRect, fontSize: CGFloat) {
        let textColor: NSColor
        if isHit {
            textColor = .white
        } else {
            textColor = AppSettings.shared.labelThemeColors.text
        }

        let isLight = isHit ? false : AppSettings.shared.labelThemeColors.background.isPerceptuallyLight
        let textShadow = NSShadow()
        textShadow.shadowColor = isLight ? NSColor.white.withAlphaComponent(0.6) : NSColor.black.withAlphaComponent(0.5)
        textShadow.shadowOffset = CGSize(width: 0, height: -0.75)
        textShadow.shadowBlurRadius = 0.5

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: textColor,
            .shadow: textShadow,
            .paragraphStyle: {
                let ps = NSMutableParagraphStyle()
                ps.alignment = .center
                return ps
            }(),
        ]

        let textSize = (label as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2 - 0.5, // Shift down slightly for optical centering
            width: textSize.width,
            height: textSize.height
        )
        (label as NSString).draw(in: textRect, withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !label.isEmpty, bounds.width > 1, bounds.height > 1 else { return }

        // Base font size from user setting; clamp for tiny multi-char labels
        let baseFontSize = CGFloat(AppSettings.shared.labelSize)
        let fontSize: CGFloat = label.count <= 2 ? max(8.5, baseFontSize * 0.65) : max(7.5, baseFontSize * 0.57)
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
            bgColor = NSColor(calibratedRed: 0.15, green: 0.85, blue: 0.35, alpha: 0.95) // Green on hit
            borderColor = NSColor.white.withAlphaComponent(0.2)
        } else {
            let themeColors = AppSettings.shared.labelThemeColors
            bgColor = themeColors.background.withAlphaComponent(0.95)
            borderColor = themeColors.background.blended(withFraction: 0.35, of: .black)?.withAlphaComponent(0.45)
                ?? NSColor.black.withAlphaComponent(0.2)
        }

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
        guard !label.isEmpty else { return NSSize(width: 14, height: 14) }
        let baseFontSize = CGFloat(AppSettings.shared.labelSize)
        let fontSize: CGFloat = label.count <= 2 ? max(8.5, baseFontSize * 0.65) : max(7.5, baseFontSize * 0.57)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        ]
        let textSize = (label as NSString).size(withAttributes: attrs)
        let bubbleW = textSize.width + 5 // Compact horizontal padding
        let bubbleH = textSize.height + 2.5 // Compact vertical padding
        let pointerH: CGFloat = 5.5 // Shortened pointer
        
        switch position {
        case .above, .below:
            let totalH = bubbleH + pointerH
            return NSSize(width: max(bubbleW, 14), height: totalH)
        case .left, .right:
            let totalW = bubbleW + pointerH
            return NSSize(width: max(totalW, 14), height: bubbleH)
        }
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
