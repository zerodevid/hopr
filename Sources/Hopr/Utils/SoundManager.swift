import Cocoa

final class SoundManager {
    static let shared = SoundManager()

    private init() {}

    func playEnterMode() {
        playSound(named: "click7.m4a", volume: 0.05)
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
        playSound(named: "click1.m4a", volume: 0.08)
    }

    func playScrollTick() {
        // Silent as requested
    }

    private func playSound(named name: String, volume: Float) {
        let fm = FileManager.default
        
        // Try current working directory first
        let localPath = fm.currentDirectoryPath + "/Resources/\(name)"
        if fm.fileExists(atPath: localPath), let sound = NSSound(contentsOfFile: localPath, byReference: true) {
            sound.volume = volume
            sound.play()
            return
        }
        
        // Fallback to absolute workspace path
        let absolutePath = "/Users/macbook/Documents/Project/clone_hopr/Resources/\(name)"
        if let sound = NSSound(contentsOfFile: absolutePath, byReference: true) {
            sound.volume = volume
            sound.play()
        }
    }
}
