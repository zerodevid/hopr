import Foundation
import Cocoa

enum KeyMapper {

    /// Character set used to generate labels — driven by AppSettings.labelCharacters
    static var chars: String { AppSettings.shared.labelCharacters.isEmpty ? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" : AppSettings.shared.labelCharacters.uppercased() }

    // MARK: - Sticky Label Cache

    /// Cache structure: [bundleID: [fingerprint: label]]
    /// Labels stay consistent for the same element across hint mode activations.
    private static var labelCache: [String: [String: String]] = [:]

    /// Round position to nearest 20px to tolerate minor layout shifts
    private static let positionRounding: CGFloat = 20.0

    /// Max cached entries per app before eviction
    private static let maxCachePerApp = 500

    /// Generate a stable fingerprint for a UIElement based on its identity.
    /// Combines role + title + rounded position so the same button at the same
    /// spot always produces the same fingerprint.
    static func fingerprint(for element: UIElement) -> String {
        let rx = Int((element.frame.origin.x / positionRounding).rounded()) * Int(positionRounding)
        let ry = Int((element.frame.origin.y / positionRounding).rounded()) * Int(positionRounding)
        return "\(element.role)|\(element.title)|\(rx),\(ry)"
    }

    // MARK: - Uniform-Length Labels

    /// Determine the minimum label length so ALL labels have equal character count.
    /// ≤26 elements → 1 char (A-Z), ≤676 → 2 chars (AA-ZZ), etc.
    static func labelLength(for count: Int) -> Int {
        if count <= 0 { return 1 }
        let base = chars.count
        var length = 1
        var capacity = base
        while capacity < count {
            length += 1
            capacity = Int(pow(Double(base), Double(length)))
        }
        return length
    }

    /// Generate a fixed-length label from an index using base-26 encoding.
    /// index 0 → "AA", index 1 → "AB", ..., index 25 → "AZ", index 26 → "BA", etc.
    static func uniformLabel(index: Int, length: Int) -> String {
        let charArray = Array(chars)
        let base = charArray.count
        var label = ""
        var remaining = index
        for _ in 0..<length {
            let charIndex = remaining % base
            label = String(charArray[charIndex]) + label
            remaining /= base
        }
        return label
    }

    /// Generate labels with sticky caching per app. All labels have uniform length
    /// so pressing a single key never auto-activates when labels are multi-char.
    static func assignLabels(to elements: [UIElement], for bundleID: String? = nil) -> [UIElement] {
        let bundleID = bundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let requiredLength = labelLength(for: elements.count)
        var result = elements
        var appCache = labelCache[bundleID] ?? [:]
        var usedLabels = Set<String>()

        // First pass: assign cached labels (only if length matches current requirement)
        for i in 0..<result.count {
            let fp = fingerprint(for: result[i])
            if let cachedLabel = appCache[fp], cachedLabel.count == requiredLength {
                if usedLabels.contains(cachedLabel) {
                    continue // Fingerprint collision — let second pass handle it
                }
                result[i].label = cachedLabel
                usedLabels.insert(cachedLabel)
            }
        }

        let cachedCount = usedLabels.count

        // Second pass: assign new uniform-length labels to uncached elements
        var nextIndex = 0
        for i in 0..<result.count {
            if result[i].label.isEmpty {
                // Skip indices whose labels are already taken
                while usedLabels.contains(uniformLabel(index: nextIndex, length: requiredLength)) {
                    nextIndex += 1
                }
                let newLabel = uniformLabel(index: nextIndex, length: requiredLength)
                result[i].label = newLabel
                usedLabels.insert(newLabel)

                // Cache this new assignment
                let fp = fingerprint(for: result[i])
                appCache[fp] = newLabel
                nextIndex += 1
            }
        }

        // Evict oldest entries if cache grows too large
        if appCache.count > maxCachePerApp {
            let activeFingerprints = Set(result.map { fingerprint(for: $0) })
            appCache = appCache.filter { activeFingerprints.contains($0.key) }
        }

        labelCache[bundleID] = appCache

        Log.debug("StickyLabels: \(cachedCount) cached, \(result.count - cachedCount) new (len=\(requiredLength)) for [\(bundleID)]")

        return result
    }

    /// Check if typed prefix matches the start of any label
    static func matchingLabels(prefix: String, in elements: [UIElement]) -> [UIElement] {
        let upper = prefix.uppercased()
        return elements.filter { $0.label.hasPrefix(upper) }
    }

    /// Clear cache for a specific app or all apps
    static func clearCache(forApp bundleID: String? = nil) {
        if let bundleID = bundleID {
            labelCache.removeValue(forKey: bundleID)
        } else {
            labelCache.removeAll()
        }
        Log.info("StickyLabels: cache cleared\(bundleID.map { " for \($0)" } ?? "")")
    }
}