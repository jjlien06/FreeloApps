import AppKit
import Foundation

/// Handles folders handed to the app from outside: `open -a Cull <folder>`,
/// Finder's "Open With", and dropping a folder on the Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NotificationCenter.default.post(name: .cullOpenSpecificFolder, object: folder(for: url))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// A photo resolves to its containing folder, so dropping one frame on the
    /// icon culls the shoot it came from.
    private func folder(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }
}
