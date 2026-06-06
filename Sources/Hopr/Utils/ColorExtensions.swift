import Cocoa
import SwiftUI

// MARK: - NSColor ↔ Hex String

extension NSColor {

    /// Initialize from a "#RRGGBB" or "#RRGGBBAA" hex string.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&int) else { return nil }
        let a, r, g, b: UInt64
        switch s.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: return nil
        }
        self.init(
            calibratedRed: CGFloat(r) / 255,
            green:         CGFloat(g) / 255,
            blue:          CGFloat(b) / 255,
            alpha:         CGFloat(a) / 255
        )
    }

    /// Serialize to "#RRGGBB" hex string (sRGB, no alpha).
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#007AFF" }
        let r = Int((c.redComponent   * 255).rounded().clamped(to: 0...255))
        let g = Int((c.greenComponent * 255).rounded().clamped(to: 0...255))
        let b = Int((c.blueComponent  * 255).rounded().clamped(to: 0...255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// True when the color is perceptually light (relative luminance > 0.5).
    var isPerceptuallyLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        // WCAG relative luminance approximation
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.55
    }
}

// MARK: - SwiftUI Color ↔ Hex String

extension Color {

    /// Initialize from a "#RRGGBB" hex string.
    init(hex: String) {
        if let ns = NSColor(hex: hex) {
            self.init(nsColor: ns)
        } else {
            self = .accentColor
        }
    }

    /// Serialize to "#RRGGBB" hex string.
    var hexString: String {
        NSColor(self).hexString
    }
}

// MARK: - Comparable clamping helper

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
