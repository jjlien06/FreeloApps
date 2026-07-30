import AppKit

final class SelectionView: NSView {
    private unowned let controller: SelectionOverlayController
    private let screen: NSScreen
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var dragging = false

    init(frame: NSRect, screen: NSScreen, controller: SelectionOverlayController) {
        self.screen = screen
        self.controller = controller
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        dragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging, let window else { return }
        dragging = false
        // Full-size content view of a borderless window: view == window coords.
        let globalRect = currentRect.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        controller.didSelect(rect: globalRect, on: screen)
    }

    override func rightMouseDown(with event: NSEvent) {
        controller.cancel()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        if dragging, currentRect.width > 0, currentRect.height > 0 {
            NSColor.clear.setFill()
            currentRect.fill(using: .copy)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: currentRect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
        }
        drawCaption()
    }

    private func drawCaption() {
        let caption = NSAttributedString(
            string: controller.captionText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
        let textSize = caption.size()
        let padding: CGFloat = 10
        let box = NSRect(
            x: (bounds.width - textSize.width) / 2 - padding,
            y: bounds.height - 80,
            width: textSize.width + padding * 2,
            height: textSize.height + 12
        )
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        caption.draw(at: NSPoint(x: box.minX + padding, y: box.minY + 6))
    }
}
