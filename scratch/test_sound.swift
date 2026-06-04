import Cocoa

let soundNames = ["Pop", "Tink", "Glass", "Ping"]
for name in soundNames {
    if let sound = NSSound(named: name) {
        sound.volume = 0.2
        print("Playing \(name) at volume \(sound.volume)...")
        sound.play()
        Thread.sleep(forTimeInterval: 0.5)
    } else {
        print("Sound \(name) not found")
    }
}
