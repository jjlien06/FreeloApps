import AppKit
import SnipTextCore
import os

/// Headless verification path (`open SnipText.app --args --selftest`):
/// captures a fixed region of the main display, OCRs it, writes the result to
/// the clipboard, logs it, and quits. Lets the capture→OCR→clipboard pipeline
/// be verified from the CLI with `pbpaste` — no overlay interaction needed.
enum SelfTest {
    static func run() async {
        let log = Logger(subsystem: "com.jeremylien.SnipText", category: "selftest")
        defer { NSApp.terminate(nil) }

        guard let screen = NSScreen.main else {
            log.error("selftest: no main screen")
            return
        }
        let region = CGRect(x: 0, y: 0, width: 800, height: 400) // top-left, incl. menu bar
        let scale = screen.backingScaleFactor
        do {
            let image = try await ScreenshotService.capture(
                displayID: CGMainDisplayID(),
                sourceRect: region,
                pixelWidth: Int(region.width * scale),
                pixelHeight: Int(region.height * scale)
            )
            let result = try await RecognitionService.recognize(image)
            let text = TextPostProcessor.process(lines: result.lines, joinLines: false)
            ClipboardWriter.copy(text.isEmpty ? "<selftest: no text recognized>" : text)
            log.info("selftest OK: \(text, privacy: .public)")
        } catch {
            ClipboardWriter.copy("<selftest failed: \(error)>")
            log.error("selftest failed: \(String(describing: error), privacy: .public)")
        }
    }
}
