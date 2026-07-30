import AppKit

struct SelectionResult {
    /// Global AppKit coordinates (bottom-left origin) — for HUD placement.
    let globalRect: NSRect
    let displayID: CGDirectDisplayID
    /// Display-relative, top-left origin, in points — what ScreenCaptureKit wants.
    let displayRelativeRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let optionHeld: Bool
}

/// Shows one dimmed drag-to-select panel per screen. Esc or right-click
/// cancels; holding ⌥ inverts the line-break setting for this capture only.
final class SelectionOverlayController {
    private var panels: [SelectionPanel] = []
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var completion: ((SelectionResult?) -> Void)?
    private var joinLinesDefault = true
    private(set) var optionHeld = false

    var isActive: Bool { !panels.isEmpty }

    var captionText: String {
        let joining = joinLinesDefault != optionHeld
        return joining
            ? "Drag to capture text · line breaks joined (hold ⌥ to preserve) · esc cancels"
            : "Drag to capture text · line breaks preserved (hold ⌥ to join) · esc cancels"
    }

    func present(joinLinesDefault: Bool, completion: @escaping (SelectionResult?) -> Void) {
        guard panels.isEmpty else {
            completion(nil)
            return
        }
        self.completion = completion
        self.joinLinesDefault = joinLinesDefault
        optionHeld = NSEvent.modifierFlags.contains(.option)

        for screen in NSScreen.screens {
            let panel = SelectionPanel(screen: screen, controller: self)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        // Key status lets the local monitors below receive Esc / ⌥ events.
        let mouseLocation = NSEvent.mouseLocation
        let panelUnderMouse = panels.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        (panelUnderMouse ?? panels.first)?.makeKey()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.finish(nil)
                return nil
            }
            return event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            self.optionHeld = event.modifierFlags.contains(.option)
            self.refreshCaptions()
            return event
        }
        refreshCaptions()
    }

    func cancel() {
        finish(nil)
    }

    func didSelect(rect globalRect: NSRect, on screen: NSScreen) {
        guard globalRect.width >= 3, globalRect.height >= 3 else {
            finish(nil)
            return
        }
        let screenFrame = screen.frame
        let scale = screen.backingScaleFactor
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()

        // AppKit global (bottom-left origin) → display-relative top-left origin.
        let sourceRect = CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: screenFrame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
        let result = SelectionResult(
            globalRect: globalRect,
            displayID: displayID,
            displayRelativeRect: sourceRect,
            pixelWidth: Int(globalRect.width * scale),
            pixelHeight: Int(globalRect.height * scale),
            optionHeld: optionHeld
        )
        finish(result)
    }

    private func refreshCaptions() {
        panels.forEach { $0.selectionView.needsDisplay = true }
    }

    private func finish(_ result: SelectionResult?) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        let callback = completion
        completion = nil
        callback?(result)
    }
}
