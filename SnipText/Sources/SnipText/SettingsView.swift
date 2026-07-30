import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.joinLineBreaksKey) private var joinLineBreaks = true
    @AppStorage(AppSettings.autoOpenLinksKey) private var autoOpenLinks = false
    @AppStorage(AppSettings.playShutterSoundKey) private var playShutterSound = true

    var body: some View {
        TabView {
            Form {
                Toggle("Join line breaks into spaces", isOn: $joinLineBreaks)
                Text("OCR inserts a hard break wherever a visual line ends, which is rarely wanted in prose. Hold ⌥ during a capture to invert this once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Automatically open captured links", isOn: $autoOpenLinks)
                Toggle("Play shutter sound", isOn: $playShutterSound)
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                KeyboardShortcuts.Recorder("Capture text:", name: .captureText)
                KeyboardShortcuts.Recorder("Capture & speak:", name: .captureAndSpeak)
            }
            .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 280)
    }
}
