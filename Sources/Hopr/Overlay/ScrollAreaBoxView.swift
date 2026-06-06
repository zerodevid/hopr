import Cocoa

class ScrollAreaBoxView: NSView {

    let number: String
    private(set) var highlighted: Bool

    init(number: String, highlighted: Bool = false) {
        self.number = number
        self.highlighted = highlighted
        super.init(frame: .zero)
        wantsLayer = true
    }

    func setHighlighted(_ highlighted: Bool) {
        guard self.highlighted != highlighted else { return }
        self.highlighted = highlighted
        needsDisplay = true
        
        if highlighted {
            wantsLayer = true
            let originalAnchor = layer?.anchorPoint ?? CGPoint(x: 0, y: 0)
            let originalPosition = layer?.position ?? .zero
            
            layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.position = CGPoint(x: frame.midX, y: frame.midY)
            
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                self?.layer?.anchorPoint = originalAnchor
                self?.layer?.position = originalPosition
            }
            
            let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
            bounce.values = [1.0, 1.06, 1.0]
            bounce.keyTimes = [0.0, 0.5, 1.0]
            bounce.duration = 0.2
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(bounce, forKey: "bounce")
            
            CATransaction.commit()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderRect = bounds.insetBy(dx: 1, dy: 1)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 6, yRadius: 6)

        let accentColor: NSColor = highlighted ? NSColor.systemGreen : NSColor.controlAccentColor

        // Subtle fill when highlighted
        if highlighted {
            accentColor.withAlphaComponent(0.08).setFill()
            borderPath.fill()
        }

        // Border
        accentColor.withAlphaComponent(highlighted ? 0.8 : 0.5).setStroke()
        borderPath.lineWidth = highlighted ? 2.5 : 2.0
        borderPath.stroke()

        // Number badge — native pill style
        let badgeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let badgeTextSize = (number as NSString).size(withAttributes: [.font: badgeFont])
        let badgeW = max(badgeTextSize.width + 12, 20)
        let badgeH: CGFloat = 18
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
            y: badgeRect.midY - badgeTextSize.height / 2
        )
        (number as NSString).draw(at: textPoint, withAttributes: textAttrs)
    }
}
