import Foundation
import ImageIO
import Vision

class QRCodeDecoder {
    static func decode(imagePath: String) -> [String] {
        let imageURL = URL(fileURLWithPath: imagePath)
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
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
