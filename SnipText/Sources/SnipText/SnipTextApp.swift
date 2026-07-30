import AppKit
import SwiftUI

@main
struct SnipTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("SnipText", systemImage: "text.viewfinder") {
            MenuContent()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        AppController.shared.start()
        if CommandLine.arguments.contains("--selftest") {
            Task { await SelfTest.run() }
        }
    }
}
