import AppKit
import SwiftUI

/// Brief floating confirmation (👍 Copied / ⚠︎ No text found) that fades out.
enum HUDPresenter {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(_ message: String, success: Bool) {
        dismissTask?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let hosting = NSHostingView(rootView: HUDView(message: message, success: success))
        hosting.frame.size = hosting.fittingSize

        let hud = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.hasShadow = false
        hud.level = .screenSaver
        hud.sharingType = .none
        hud.ignoresMouseEvents = true
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hud.contentView = hosting

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            hud.setFrameOrigin(NSPoint(
                x: visible.midX - hosting.frame.width / 2,
                y: visible.minY + visible.height * 0.16
            ))
        }
        hud.alphaValue = 1
        hud.orderFrontRegardless()
        panel = hud

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            fadeOut(hud)
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            hud.orderOut(nil)
            if panel === hud { panel = nil }
        }
    }

    private static func fadeOut(_ hud: NSPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            hud.animator().alphaValue = 0
        }
    }
}

private struct HUDView: View {
    let message: String
    let success: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: success ? "hand.thumbsup.fill" : "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 11))
    }
}
