import Foundation

enum AppSettings {
    static let joinLineBreaksKey = "joinLineBreaks"
    static let autoOpenLinksKey = "autoOpenLinks"
    static let playShutterSoundKey = "playShutterSound"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            joinLineBreaksKey: true,
            autoOpenLinksKey: false,
            playShutterSoundKey: true,
        ])
    }

    static var joinLineBreaks: Bool { UserDefaults.standard.bool(forKey: joinLineBreaksKey) }
    static var autoOpenLinks: Bool { UserDefaults.standard.bool(forKey: autoOpenLinksKey) }
    static var playShutterSound: Bool { UserDefaults.standard.bool(forKey: playShutterSoundKey) }
}
