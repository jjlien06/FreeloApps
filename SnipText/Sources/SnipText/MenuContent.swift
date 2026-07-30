import AppKit
import SwiftUI

struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Capture Text") {
            AppController.shared.coordinator.begin(speak: false)
        }
        Button("Capture & Speak") {
            AppController.shared.coordinator.begin(speak: true)
        }
        Divider()
        Button("Copy All History") {
            AppController.shared.copyHistory()
        }
        Button("Clear History…") {
            AppController.shared.confirmClearHistory()
        }
        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit SnipText") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
