import CoreGraphics
import ScreenCaptureKit

enum ScreenshotService {
    enum CaptureError: Error {
        case displayNotFound
    }

    /// Captures a region of one display. `sourceRect` is display-relative with a
    /// top-left origin, in points; the output is sized in pixels so Retina
    /// captures stay sharp for OCR. All ScreenCaptureKit types stay inside this
    /// function — only the CGImage crosses back to the main actor.
    nonisolated static func capture(
        displayID: CGDirectDisplayID,
        sourceRect: CGRect,
        pixelWidth: Int,
        pixelHeight: Int
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
