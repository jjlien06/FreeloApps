import AppKit

enum SoundPlayer {
    // The system's real screenshot shutter sound; falls back to a bundled-with-macOS
    // named sound if the private path ever moves.
    private static let shutterPath =
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"

    static func playShutter() {
        if let sound = NSSound(contentsOfFile: shutterPath, byReference: true) {
            sound.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
    }
}
