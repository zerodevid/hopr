import Cocoa

/// Draws the Hollow Knight menu-bar icon with animated expressions.
/// All drawing is done programmatically so no external assets are needed
/// beyond the base SVG (which is only used as a fallback).
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
    private var blinkSequenceIndex = 0

    // Icon dimensions (menu-bar native)
    private let iconSize = NSSize(width: 18, height: 18)

    // MARK: - Init

    init(button: NSStatusBarButton) {
        self.button = button
        setExpression(.normal)
        startIdleLoop()
    }

    deinit {
        idleTimer?.invalidate()
        animationTimer?.invalidate()
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

    // MARK: - Sequence player

    private func playSequence(_ sequence: [(Expression, TimeInterval)]) {
        animationTimer?.invalidate()
        guard !sequence.isEmpty else { return }

        var remaining = sequence
        let first = remaining.removeFirst()
        setExpression(first.0)

        func playNext() {
            guard !remaining.isEmpty else { return }
            let next = remaining.removeFirst()
            animationTimer = Timer.scheduledTimer(withTimeInterval: first.1, repeats: false) { [weak self] _ in
                self?.setExpression(next.0)
                if !remaining.isEmpty {
                    let afterThis = next.1
                    self?.animationTimer = Timer.scheduledTimer(withTimeInterval: afterThis, repeats: false) { _ in
                        playNext()
                    }
                }
            }
        }
        // Kick off recursive playback
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
        animationTimer = Timer.scheduledTimer(withTimeInterval: max(next.1, 0.01), repeats: false) { [weak self] _ in
            if remaining.isEmpty {
                // This was the last with a delay, expression already set
                return
            }
            let after = remaining.removeFirst()
            self?.setExpression(after.0)
            self?.playRemainingSequence(remaining)
        }
        setExpression(next.0)
    }

    // MARK: - Drawing

    private func renderIcon(expression: Expression) -> NSImage {
        let img = NSImage(size: iconSize, flipped: false) { rect in
            // All drawing in a normalized 0…1 coordinate space
            let s = rect.size

            // --- Head (rounded rect) ---
            let headRect = NSRect(x: s.width * 0.12, y: s.height * 0.02,
                                  width: s.width * 0.76, height: s.height * 0.72)
            let headPath = NSBezierPath(roundedRect: headRect, xRadius: s.width * 0.15, yRadius: s.height * 0.15)

            NSColor.black.setFill()
            headPath.fill()

            // --- Horns ---
            self.drawHorn(left: true, in: rect)
            self.drawHorn(left: false, in: rect)

            // --- Eyes (expression-dependent) ---
            self.drawEyes(expression: expression, in: rect)

            return true
        }

        img.isTemplate = true
        return img
    }

    // MARK: - Horn drawing

    private func drawHorn(left: Bool, in rect: NSRect) {
        let s = rect.size
        let path = NSBezierPath()

        if left {
            // Left horn
            path.move(to: NSPoint(x: s.width * 0.20, y: s.height * 0.60))
            path.curve(to: NSPoint(x: s.width * 0.12, y: s.height * 0.95),
                       controlPoint1: NSPoint(x: s.width * 0.10, y: s.height * 0.70),
                       controlPoint2: NSPoint(x: s.width * 0.05, y: s.height * 0.88))
            path.curve(to: NSPoint(x: s.width * 0.35, y: s.height * 0.72),
                       controlPoint1: NSPoint(x: s.width * 0.20, y: s.height * 0.90),
                       controlPoint2: NSPoint(x: s.width * 0.30, y: s.height * 0.80))
        } else {
            // Right horn (mirrored)
            path.move(to: NSPoint(x: s.width * 0.80, y: s.height * 0.60))
            path.curve(to: NSPoint(x: s.width * 0.88, y: s.height * 0.95),
                       controlPoint1: NSPoint(x: s.width * 0.90, y: s.height * 0.70),
                       controlPoint2: NSPoint(x: s.width * 0.95, y: s.height * 0.88))
            path.curve(to: NSPoint(x: s.width * 0.65, y: s.height * 0.72),
                       controlPoint1: NSPoint(x: s.width * 0.80, y: s.height * 0.90),
                       controlPoint2: NSPoint(x: s.width * 0.70, y: s.height * 0.80))
        }

        path.close()
        NSColor.black.setFill()
        path.fill()
    }

    // MARK: - Eye drawing

    private func drawEyes(expression: Expression, in rect: NSRect) {
        let s = rect.size

        // Base eye positions & sizes
        let leftEyeCenter = NSPoint(x: s.width * 0.38, y: s.height * 0.34)
        let rightEyeCenter = NSPoint(x: s.width * 0.62, y: s.height * 0.34)
        let eyeWidth: CGFloat = s.width * 0.14
        let eyeHeight: CGFloat = s.height * 0.22

        switch expression {
        case .normal:
            drawOvalEye(center: leftEyeCenter, width: eyeWidth, height: eyeHeight, in: rect)
            drawOvalEye(center: rightEyeCenter, width: eyeWidth, height: eyeHeight, in: rect)

        case .blink:
            // Fully closed — thin horizontal lines
            drawClosedEye(center: leftEyeCenter, width: eyeWidth, in: rect)
            drawClosedEye(center: rightEyeCenter, width: eyeWidth, in: rect)

        case .halfBlink:
            // Half-closed — squished ovals
            drawOvalEye(center: leftEyeCenter, width: eyeWidth, height: eyeHeight * 0.35, in: rect)
            drawOvalEye(center: rightEyeCenter, width: eyeWidth, height: eyeHeight * 0.35, in: rect)

        case .happy:
            // Upside-down arcs (^  ^)
            drawHappyEye(center: leftEyeCenter, width: eyeWidth, height: eyeHeight, in: rect)
            drawHappyEye(center: rightEyeCenter, width: eyeWidth, height: eyeHeight, in: rect)

        case .angry:
            // Angled angry eyes with slanted brow
            drawAngryEye(center: leftEyeCenter, width: eyeWidth, height: eyeHeight, left: true, in: rect)
            drawAngryEye(center: rightEyeCenter, width: eyeWidth, height: eyeHeight, left: false, in: rect)

        case .sleepy:
            // Droopy half-open eyes
            drawSleepyEye(center: leftEyeCenter, width: eyeWidth, height: eyeHeight, in: rect)
            drawSleepyEye(center: rightEyeCenter, width: eyeWidth, height: eyeHeight, in: rect)

        case .surprised:
            // Big round eyes
            let bigW = eyeWidth * 1.2
            let bigH = eyeHeight * 1.1
            drawOvalEye(center: leftEyeCenter, width: bigW, height: bigH, in: rect)
            drawOvalEye(center: rightEyeCenter, width: bigW, height: bigH, in: rect)

        case .wink:
            // Left eye normal, right eye closed
            drawOvalEye(center: leftEyeCenter, width: eyeWidth, height: eyeHeight, in: rect)
            drawClosedEye(center: rightEyeCenter, width: eyeWidth, in: rect)
        }
    }

    // --- Eye primitives ---

    /// Standard oval eye (cut out of black head = draw white oval)
    private func drawOvalEye(center: NSPoint, width: CGFloat, height: CGFloat, in rect: NSRect) {
        let eyeRect = NSRect(x: center.x - width / 2, y: center.y - height / 2,
                             width: width, height: height)
        let path = NSBezierPath(ovalIn: eyeRect)
        // We use the head as black, eyes are "holes" — draw as white for template
        NSColor.white.setFill()
        path.fill()
    }

    /// Closed eye — thin horizontal line
    private func drawClosedEye(center: NSPoint, width: CGFloat, in rect: NSRect) {
        let lineRect = NSRect(x: center.x - width / 2, y: center.y - 0.5,
                              width: width, height: 1.0)
        let path = NSBezierPath(roundedRect: lineRect, xRadius: 0.5, yRadius: 0.5)
        NSColor.white.setFill()
        path.fill()
    }

    /// Happy eye — upward arc (like ^)
    private func drawHappyEye(center: NSPoint, width: CGFloat, height: CGFloat, in rect: NSRect) {
        let path = NSBezierPath()
        let left = center.x - width / 2
        let right = center.x + width / 2
        let baseY = center.y - height * 0.1
        let peakY = center.y + height * 0.4

        path.move(to: NSPoint(x: left, y: baseY))
        path.curve(to: NSPoint(x: right, y: baseY),
                   controlPoint1: NSPoint(x: left + width * 0.15, y: peakY),
                   controlPoint2: NSPoint(x: right - width * 0.15, y: peakY))

        path.lineWidth = 1.5
        NSColor.white.setStroke()
        path.stroke()
    }

    /// Angry eye — normal oval with an angled brow line cutting across the top
    private func drawAngryEye(center: NSPoint, width: CGFloat, height: CGFloat, left: Bool, in rect: NSRect) {
        // Draw the base oval eye
        drawOvalEye(center: center, width: eyeWidth(width), height: height * 0.75, in: rect)

        // Draw angry eyebrow (angled line above eye)
        let path = NSBezierPath()
        let browY = center.y + height * 0.40
        let browOffsetY: CGFloat = height * 0.25

        if left {
            // Left eye: brow goes from upper-left down to lower-right (\ shape)
            path.move(to: NSPoint(x: center.x - width * 0.6, y: browY + browOffsetY))
            path.line(to: NSPoint(x: center.x + width * 0.6, y: browY - browOffsetY * 0.3))
        } else {
            // Right eye: brow goes from lower-left up to upper-right (/ shape)
            path.move(to: NSPoint(x: center.x - width * 0.6, y: browY - browOffsetY * 0.3))
            path.line(to: NSPoint(x: center.x + width * 0.6, y: browY + browOffsetY))
        }

        path.lineWidth = 1.8
        path.lineCapStyle = .round
        NSColor.black.setStroke()
        path.stroke()
    }

    private func eyeWidth(_ w: CGFloat) -> CGFloat { w }

    /// Sleepy eye — half-lidded droopy oval
    private func drawSleepyEye(center: NSPoint, width: CGFloat, height: CGFloat, in rect: NSRect) {
        // Draw bottom half of the oval
        let eyeRect = NSRect(x: center.x - width / 2, y: center.y - height * 0.3,
                             width: width, height: height * 0.45)
        let path = NSBezierPath(ovalIn: eyeRect)
        NSColor.white.setFill()
        path.fill()
    }
}
