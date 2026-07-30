import AppKit
import CoreGraphics

enum ScreenCapturePermission {
    /// Returns true when Screen Recording access is already granted. Otherwise
    /// triggers the one-time system prompt and shows an explainer pointing at
    /// System Settings — macOS only applies the grant on relaunch.
    static func ensureGranted() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        if CGRequestScreenCaptureAccess() {
            return true
        }
        showExplainer()
        return false
    }

    private static func showExplainer() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SnipText needs Screen Recording access"
        alert.informativeText = """
        SnipText reads the pixels you select to recognize text — entirely on this Mac, nothing is uploaded.

        Enable SnipText in System Settings → Privacy & Security → Screen Recording, then relaunch SnipText.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
