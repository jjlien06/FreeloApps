import CoreGraphics
import CoreText
import Testing
@testable import SnipTextCore

@Suite struct RecognitionServiceTests {
    /// Renders known text into a bitmap and runs the real Vision pipeline on it —
    /// exercises OCR end-to-end headlessly, no screen capture or TCC involved.
    @Test func recognizesRenderedText() async throws {
        let image = try #require(Self.render(text: "HELLO WORLD 42", width: 800, height: 200))
        let result = try await RecognitionService.recognize(image)
        let text = result.lines.joined(separator: " ")
        #expect(text.localizedCaseInsensitiveContains("HELLO WORLD"))
        #expect(text.contains("42"))
    }

    @Test func emptyImageYieldsNoText() async throws {
        let image = try #require(Self.render(text: "", width: 400, height: 200))
        let result = try await RecognitionService.recognize(image)
        #expect(result.lines.isEmpty)
        #expect(result.barcodePayloads.isEmpty)
        #expect(result.isEmpty)
    }

    private static func render(text: String, width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if !text.isEmpty {
            let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
            let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: 40, y: CGFloat(height) / 2 - 20)
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()
    }
}
