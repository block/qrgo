import AppKit
import Vision

class QRCodeDecoder {
    static func decode(imagePath: String) -> [String] {
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let request = VNDetectBarcodesRequest()
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try requestHandler.perform([request])
            guard let results = request.results else { return [] }

            return results.compactMap { $0.payloadStringValue }
        } catch {
            printError("Failed to detect QR codes: \(error)")
            return []
        }
    }
}
