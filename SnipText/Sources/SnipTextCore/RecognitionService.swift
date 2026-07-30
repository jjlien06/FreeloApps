import CoreGraphics
import Vision

public struct RecognitionResult: Sendable {
    public let lines: [String]
    public let barcodePayloads: [String]

    public init(lines: [String], barcodePayloads: [String]) {
        self.lines = lines
        self.barcodePayloads = barcodePayloads
    }

    public var isEmpty: Bool { lines.isEmpty && barcodePayloads.isEmpty }
}

public enum RecognitionService {
    /// Runs text recognition and barcode detection on the image in one pass.
    /// Lines are returned in visual reading order (top-to-bottom, left-to-right).
    public static func recognize(_ image: CGImage) async throws -> RecognitionResult {
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.automaticallyDetectsLanguage = true
        textRequest.usesLanguageCorrection = true

        let barcodeRequest = DetectBarcodesRequest()

        async let textTask = textRequest.perform(on: image)
        async let barcodeTask = barcodeRequest.perform(on: image)

        let textObservations = try await textTask
        // Barcode detection failing should never sink the whole capture.
        let barcodeObservations = (try? await barcodeTask) ?? []

        let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let sorted = textObservations.sorted { a, b in
            let ra = a.boundingBox.toImageCoordinates(imageSize, origin: .upperLeft)
            let rb = b.boundingBox.toImageCoordinates(imageSize, origin: .upperLeft)
            // Same visual line when vertical centers overlap; then order by x.
            if abs(ra.midY - rb.midY) < min(ra.height, rb.height) / 2 {
                return ra.minX < rb.minX
            }
            return ra.midY < rb.midY
        }

        let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
        let payloads = barcodeObservations.compactMap { $0.payloadString }
        return RecognitionResult(lines: lines, barcodePayloads: payloads)
    }
}
