import Cocoa

/// Draws the Hollow Knight menu-bar icon with animated expressions.
/// Uses CGContext with .clear compositing to punch transparent eye holes
/// in the template image (since isTemplate=true uses alpha only).
final class MenubarAnimator {

    // MARK: - Expression types

    enum Expression: CaseIterable {
        case normal
        case blink
        case halfBlink
        case happy
        case angry
        case sleepy
        case surprised
        case wink
    }

    // MARK: - Public state

    private(set) var currentExpression: Expression = .normal
    private weak var button: NSStatusBarButton?
    private var idleTimer: Timer?
    private var animationTimer: Timer?
    private var mouseTrackingTimer: Timer?
    private var lastMouseLocation: NSPoint = .zero

    // Icon dimensions (menu-bar native)
    private let iconSize = NSSize(width: 18, height: 18)

    // MARK: - Init

    init(button: NSStatusBarButton) {
        self.button = button
        setExpression(.normal)
        startIdleLoop()
        startMouseTracking()
    }

    deinit {
        idleTimer?.invalidate()
        animationTimer?.invalidate()
        mouseTrackingTimer?.invalidate()
    }

    // MARK: - Public API

    /// Show a specific expression, optionally returning to normal after a delay.
    func setExpression(_ expr: Expression, revertAfter: TimeInterval? = nil) {
        currentExpression = expr
        button?.image = renderIcon(expression: expr)

        if let delay = revertAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.setExpression(.normal)
            }
        }
    }

    /// Play a blink animation (halfBlink → blink → halfBlink → normal).
    func playBlink() {
        let sequence: [(Expression, TimeInterval)] = [
            (.halfBlink, 0.06),
            (.blink,     0.10),
            (.halfBlink, 0.06),
            (.normal,    0.0),
        ]
        playSequence(sequence)
    }

    /// Play an angry flash (angry for 1.5s → normal).
    func playAngry() {
        setExpression(.angry, revertAfter: 1.5)
    }

    /// Play a happy expression (happy for 1.5s → normal).
    func playHappy() {
        setExpression(.happy, revertAfter: 1.5)
    }

    /// Play a surprised expression (surprised for 1s → normal).
    func playSurprised() {
        setExpression(.surprised, revertAfter: 1.0)
    }

    /// Play a sleepy expression (sleepy for 2s → normal).
    func playSleepy() {
        setExpression(.sleepy, revertAfter: 2.0)
    }

    /// Play a wink animation.
    func playWink() {
        let sequence: [(Expression, TimeInterval)] = [
            (.wink,   0.30),
            (.normal, 0.0),
        ]
        playSequence(sequence)
    }

    // MARK: - Idle loop (random blinks)

    private func startIdleLoop() {
        scheduleNextIdle()
    }

    private func scheduleNextIdle() {
        let interval = TimeInterval.random(in: 3.0...8.0)
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, self.currentExpression == .normal else {
                self?.scheduleNextIdle()
                return
            }
            // 80% chance blink, 10% wink, 10% sleepy blink
            let roll = Int.random(in: 0..<10)
            if roll < 8 {
                self.playBlink()
            } else if roll < 9 {
                self.playWink()
            } else {
                let seq: [(Expression, TimeInterval)] = [
                    (.sleepy,    0.40),
                    (.blink,     0.15),
                    (.sleepy,    0.20),
                    (.normal,    0.0),
                ]
                self.playSequence(seq)
            }
            self.scheduleNextIdle()
        }
    }

    private func startMouseTracking() {
        mouseTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let currentLoc = NSEvent.mouseLocation
            if currentLoc != self.lastMouseLocation {
                self.lastMouseLocation = currentLoc
                self.button?.image = self.renderIcon(expression: self.currentExpression)
            }
        }
    }

    // MARK: - Sequence player

    private func playSequence(_ sequence: [(Expression, TimeInterval)]) {
        animationTimer?.invalidate()
        guard !sequence.isEmpty else { return }

        var remaining = sequence
        let first = remaining.removeFirst()
        setExpression(first.0)

        if remaining.isEmpty { return }
        let second = remaining.removeFirst()
        animationTimer = Timer.scheduledTimer(withTimeInterval: first.1, repeats: false) { [weak self] _ in
            self?.setExpression(second.0)
            self?.playRemainingSequence(remaining)
        }
    }

    private func playRemainingSequence(_ sequence: [(Expression, TimeInterval)]) {
        guard !sequence.isEmpty else { return }
        var remaining = sequence
        let next = remaining.removeFirst()
        if next.1 == 0 && remaining.isEmpty {
            setExpression(next.0)
            return
        }
        setExpression(next.0)
        animationTimer = Timer.scheduledTimer(withTimeInterval: max(next.1, 0.01), repeats: false) { [weak self] _ in
            if remaining.isEmpty { return }
            let after = remaining.removeFirst()
            self?.setExpression(after.0)
            self?.playRemainingSequence(remaining)
        }
    }

    // MARK: - Drawing (SVG base + animated eyes)

    /// Cached base SVG image (head + horns, no eyes)
    private var cachedBaseCGImage: CGImage?

    /// Load and cache the SVG without eyes as a CGImage for compositing
    private func loadBaseSVG() -> CGImage? {
        if let cached = cachedBaseCGImage { return cached }

        // Try to load the SVG file
        let fm = FileManager.default
        let localPath = fm.currentDirectoryPath + "/Resources/icon.svg"
        let absolutePath = "/Users/macbook/Documents/Project/clone_hopr/Resources/icon.svg"

        var path: String? = nil
        if fm.fileExists(atPath: localPath) {
            path = localPath
        } else if fm.fileExists(atPath: absolutePath) {
            path = absolutePath
        }

        guard let imagePath = path, let svgImage = NSImage(contentsOfFile: imagePath) else {
            return nil
        }

        // Render the SVG into a bitmap at 2x scale
        let scale: CGFloat = 2.0
        let w = Int(iconSize.width * scale)
        let h = Int(iconSize.height * scale)

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: w * 4,
            bitsPerPixel: 32
        ) else { return nil }

        let gfxCtx = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gfxCtx

        let drawRect = NSRect(origin: .zero, size: NSSize(width: w, height: h))
        svgImage.draw(in: drawRect)

        NSGraphicsContext.restoreGraphicsState()

        cachedBaseCGImage = bitmapRep.cgImage
        return cachedBaseCGImage
    }

    private func renderIcon(expression: Expression) -> NSImage {
        let scale: CGFloat = 2.0
        let w = Int(iconSize.width * scale)
        let h = Int(iconSize.height * scale)
        let s = CGSize(width: CGFloat(w), height: CGFloat(h))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: iconSize)
        }

        // Start fully transparent
        ctx.clear(CGRect(origin: .zero, size: s))

        // Draw the base SVG (head + horns + original eyes) WITHOUT vertical flip in CGContext.
        // This makes it upside down in CGContext, which renders right-side up in the flipped menu bar.
        if let baseCG = loadBaseSVG() {
            ctx.draw(baseCG, in: CGRect(origin: .zero, size: s))
        }

        // Calculate eye offset based on mouse position
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let mouseLocation = NSEvent.mouseLocation
        
        let centerX = screenFrame.midX
        let centerY = screenFrame.midY
        
        // Normalize coordinates to [-1, 1] relative to screen center
        let dx = max(-1.0, min(1.0, (mouseLocation.x - centerX) / max(100.0, screenFrame.width / 2)))
        let dy = max(-1.0, min(1.0, (mouseLocation.y - centerY) / max(100.0, screenFrame.height / 2)))
        
        // maximum displacement in CGContext pixels (at 2x scale, head width is 36px)
        let maxOffsetX: CGFloat = 1.4
        let maxOffsetY: CGFloat = 1.8
        
        // Since only the vertical coordinate space is flipped in CGContext rendering relative to screen coordinates, keep dx positive and dy positive
        let offset = CGPoint(x: dx * maxOffsetX, y: dy * maxOffsetY)

        // Always fill and redraw eyes to apply the offset dynamically
        fillOriginalEyes(ctx: ctx, size: s)
        drawEyes(ctx: ctx, expression: expression, size: s, offset: offset)

        // Create NSImage from context
        guard let cgImage = ctx.makeImage() else {
            return NSImage(size: iconSize)
        }

        let img = NSImage(cgImage: cgImage, size: iconSize)
        img.isTemplate = true
        return img
    }

    /// Fill the original eye areas with solid white (body color) to hide them.
    private func fillOriginalEyes(ctx: CGContext, size s: CGSize) {
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1) // Solid white

        // Exact ratios from SVG viewBox (614x726)
        // Since Y is flipped on screen, the eyes center Y in CGContext is 0.5048 * s.height.
        let leftRect = CGRect(
            x: s.width * 0.3575 - (s.width * 0.2362) / 2,
            y: s.height * 0.5048 - (s.height * 0.3127) / 2,
            width: s.width * 0.2362,
            height: s.height * 0.3127
        )
        ctx.fillEllipse(in: leftRect)

        let rightRect = CGRect(
            x: s.width * 0.7614 - (s.width * 0.2362) / 2,
            y: s.height * 0.5048 - (s.height * 0.3127) / 2,
            width: s.width * 0.2362,
            height: s.height * 0.3127
        )
        ctx.fillEllipse(in: rightRect)

        ctx.restoreGState()
    }

    // MARK: - Eye drawing (punches transparent holes using .clear blend mode)

    private func drawEyes(ctx: CGContext, expression: Expression, size s: CGSize, offset: CGPoint) {
        let leftCenter = CGPoint(x: s.width * 0.3575 + offset.x, y: s.height * 0.5048 + offset.y)
        let rightCenter = CGPoint(x: s.width * 0.7614 + offset.x, y: s.height * 0.5048 + offset.y)
        let eyeW: CGFloat = s.width * 0.2362
        let eyeH: CGFloat = s.height * 0.3127

        switch expression {
        case .normal:
            clearOvalEye(ctx: ctx, center: leftCenter, w: eyeW, h: eyeH)
            clearOvalEye(ctx: ctx, center: rightCenter, w: eyeW, h: eyeH)

        case .blink:
            clearLineEye(ctx: ctx, center: leftCenter, w: eyeW)
            clearLineEye(ctx: ctx, center: rightCenter, w: eyeW)

        case .halfBlink:
            clearOvalEye(ctx: ctx, center: leftCenter, w: eyeW, h: eyeH * 0.30)
            clearOvalEye(ctx: ctx, center: rightCenter, w: eyeW, h: eyeH * 0.30)

        case .happy:
            clearHappyEye(ctx: ctx, center: leftCenter, w: eyeW, h: eyeH)
            clearHappyEye(ctx: ctx, center: rightCenter, w: eyeW, h: eyeH)

        case .angry:
            clearAngryEye(ctx: ctx, center: leftCenter, w: eyeW, h: eyeH, left: true)
            clearAngryEye(ctx: ctx, center: rightCenter, w: eyeW, h: eyeH, left: false)

        case .sleepy:
            clearOvalEye(ctx: ctx, center: leftCenter, w: eyeW, h: eyeH * 0.40)
            clearOvalEye(ctx: ctx, center: rightCenter, w: eyeW, h: eyeH * 0.40)

        case .surprised:
            clearOvalEye(ctx: ctx, center: leftCenter, w: eyeW * 1.15, h: eyeH * 1.05)
            clearOvalEye(ctx: ctx, center: rightCenter, w: eyeW * 1.15, h: eyeH * 1.05)

        case .wink:
            clearOvalEye(ctx: ctx, center: leftCenter, w: eyeW, h: eyeH)
            clearLineEye(ctx: ctx, center: rightCenter, w: eyeW)
        }
    }

    // --- Eye primitives (all use .clear blend to punch transparent holes) ---

    /// Punch a transparent oval hole
    private func clearOvalEye(ctx: CGContext, center: CGPoint, w: CGFloat, h: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()
    }

    /// Punch a thin transparent line (closed eye)
    private func clearLineEye(ctx: CGContext, center: CGPoint, w: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        let lineH: CGFloat = max(1.5, w * 0.12)
        let rect = CGRect(x: center.x - w / 2, y: center.y - lineH / 2, width: w, height: lineH)
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()
    }

    /// Punch a happy eye (upward arc ^ on screen)
    private func clearHappyEye(ctx: CGContext, center: CGPoint, w: CGFloat, h: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.setLineWidth(max(2.0, w * 0.20))
        ctx.setLineCap(.round)

        // Flipped vertically because CGContext draws upside down relative to the screen.
        // Happy eye is an upward arc on screen, so it must be a downward arc in CGContext.
        let left = center.x - w / 2
        let right = center.x + w / 2
        let baseY = center.y + h * 0.10
        let peakY = center.y - h * 0.40

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: baseY))
        path.addCurve(to: CGPoint(x: right, y: baseY),
                      control1: CGPoint(x: left + w * 0.15, y: peakY),
                      control2: CGPoint(x: right - w * 0.15, y: peakY))
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Punch angry eye: smaller oval + opaque brow line on top
    private func clearAngryEye(ctx: CGContext, center: CGPoint, w: CGFloat, h: CGFloat, left: Bool) {
        // First punch the eye hole
        clearOvalEye(ctx: ctx, center: center, w: w, h: h * 0.75)

        // Flipped vertically:
        // Brow line is below the eye center (closer to forehead at Y=0)
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1) // Solid white to blend with body
        ctx.setLineWidth(max(2.0, w * 0.22))
        ctx.setLineCap(.round)

        let browY = center.y - h * 0.35
        let browDelta: CGFloat = h * 0.30

        let path = CGMutablePath()
        if left {
            // \ angle on screen
            path.move(to: CGPoint(x: center.x - w * 0.65, y: browY - browDelta))
            path.addLine(to: CGPoint(x: center.x + w * 0.65, y: browY + browDelta * 0.4))
        } else {
            // / angle on screen
            path.move(to: CGPoint(x: center.x - w * 0.65, y: browY + browDelta * 0.4))
            path.addLine(to: CGPoint(x: center.x + w * 0.65, y: browY - browDelta))
        }
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
