import AppKit

final class SelectionPanel: NSPanel {
    let selectionView: SelectionView

    init(screen: NSScreen, controller: SelectionOverlayController) {
        selectionView = SelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            controller: controller
        )
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Invisible to ScreenCaptureKit — the capture never contains the overlay.
        sharingType = .none
        isFloatingPanel = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        contentView = selectionView
    }

    // Borderless panels refuse key status by default; without this the Esc/⌥
    // event monitors never fire.
    override var canBecomeKey: Bool { true }
}
