import Cocoa

final class SoundManager {
    static let shared = SoundManager()

    private init() {}

    func playEnterMode() {
        playSound(named: "click7.m4a", volume: 0.22)
    }

    func playExitMode() {
        // Silent as requested
    }

    func playKeyPress() {
        // Silent as requested
    }

    func playKeyMiss() {
        // Silent as requested
    }

    func playActivate() {
        playSound(named: "click1.m4a", volume: 0.30)
    }

    func playScrollTick() {
        // Silent as requested
    }

    private func playSound(named name: String, volume: Float) {
        let fm = FileManager.default

        // Try current working directory first (development builds)
        let localPath = fm.currentDirectoryPath + "/Resources/\(name)"
        if fm.fileExists(atPath: localPath), let sound = NSSound(contentsOfFile: localPath, byReference: true) {
            sound.volume = volume
            sound.play()
            return
        }

        // Fallback to Bundle resource path
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = (resourcePath as NSString).appendingPathComponent(name)
            if let sound = NSSound(contentsOfFile: bundlePath, byReference: true) {
                sound.volume = volume
                sound.play()
            }
        }
    }
}
