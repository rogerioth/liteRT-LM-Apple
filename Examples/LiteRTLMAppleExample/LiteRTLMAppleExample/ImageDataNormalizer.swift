import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageDataNormalizer {
    enum NormalizationError: LocalizedError {
        case decodeFailed
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .decodeFailed:
                return "Could not decode the selected image."
            case .encodeFailed:
                return "Could not re-encode the selected image as JPEG."
            }
        }
    }

    /// Re-encode arbitrary picker bytes (HEIC, PNG, JPEG, …) as JPEG so the
    /// LiteRT-LM stb_image-based decoder can ingest them.
    static func makeJPEGData(
        from rawData: Data,
        compressionQuality: Double = 0.9
    ) throws -> Data {
        guard
            let source = CGImageSourceCreateWithData(rawData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NormalizationError.decodeFailed
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NormalizationError.encodeFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw NormalizationError.encodeFailed
        }

        return mutableData as Data
    }
}
