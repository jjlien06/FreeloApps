import AppKit
import SnipTextCore
import os

final class CaptureCoordinator {
    private let log = Logger(subsystem: "com.jeremylien.SnipText", category: "capture")
    private let overlay = SelectionOverlayController()
    private let speech = SpeechService()
    let history = HistoryStore.default
    private var isCapturing = false

    func begin(speak: Bool) {
        guard !isCapturing else { return }
        guard ScreenCapturePermission.ensureGranted() else { return }
        isCapturing = true
        overlay.present(joinLinesDefault: AppSettings.joinLineBreaks) { [weak self] selection in
            guard let self else { return }
            guard let selection else {
                self.isCapturing = false
                return
            }
            Task { await self.process(selection, speak: speak) }
        }
    }

    private func process(_ selection: SelectionResult, speak: Bool) async {
        defer { isCapturing = false }
        do {
            let image = try await ScreenshotService.capture(
                displayID: selection.displayID,
                sourceRect: selection.displayRelativeRect,
                pixelWidth: selection.pixelWidth,
                pixelHeight: selection.pixelHeight
            )
            let result = try await RecognitionService.recognize(image)
            deliver(result, optionHeld: selection.optionHeld, speak: speak)
        } catch {
            log.error("capture failed: \(String(describing: error), privacy: .public)")
            HUDPresenter.show("Capture failed", success: false)
        }
    }

    private func deliver(_ result: RecognitionResult, optionHeld: Bool, speak: Bool) {
        // XOR: holding ⌥ during the capture inverts the line-break setting once.
        let joinLines = AppSettings.joinLineBreaks != optionHeld
        var text = TextPostProcessor.process(lines: result.lines, joinLines: joinLines)
        if !result.barcodePayloads.isEmpty {
            let payloads = result.barcodePayloads.joined(separator: "\n")
            text = text.isEmpty ? payloads : text + "\n" + payloads
        }
        guard !text.isEmpty else {
            HUDPresenter.show("No text found", success: false)
            return
        }

        ClipboardWriter.copy(text)
        try? history.append(text)
        if AppSettings.autoOpenLinks {
            for url in LinkDetector.urls(in: text) {
                NSWorkspace.shared.open(url)
            }
        }
        if AppSettings.playShutterSound {
            SoundPlayer.playShutter()
        }
        HUDPresenter.show("Copied", success: true)
        if speak {
            speech.speak(text)
        }
        log.info("captured \(text.count) characters")
    }
}
