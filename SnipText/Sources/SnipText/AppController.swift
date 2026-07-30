import AppKit
import KeyboardShortcuts
import SnipTextCore

final class AppController {
    static let shared = AppController()

    let coordinator = CaptureCoordinator()

    private init() {}

    func start() {
        KeyboardShortcuts.onKeyUp(for: .captureText) { [coordinator] in
            coordinator.begin(speak: false)
        }
        KeyboardShortcuts.onKeyUp(for: .captureAndSpeak) { [coordinator] in
            coordinator.begin(speak: true)
        }
    }

    func copyHistory() {
        let all = coordinator.history.loadAll()
        guard !all.isEmpty else {
            HUDPresenter.show("History is empty", success: false)
            return
        }
        ClipboardWriter.copy(all)
        HUDPresenter.show("History copied", success: true)
    }

    func confirmClearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear capture history?"
        alert.informativeText = "This permanently deletes all captured text. It cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            try? coordinator.history.clear()
            HUDPresenter.show("History cleared", success: true)
        }
    }
}
