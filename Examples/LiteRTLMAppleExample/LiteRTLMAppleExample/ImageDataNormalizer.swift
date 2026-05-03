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
                return "Could not re-encode the selected image as PNG."
            }
        }
    }

    /// Apply image orientation, downscale large picker bytes, and re-encode as
    /// PNG so the LiteRT-LM stb_image-based decoder can ingest them.
    static func makePNGData(
        from rawData: Data,
        maxPixelDimension: Int = 1024
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else {
            throw NormalizationError.decodeFailed
        }

        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let sourceWidth = sourceProperties?[kCGImagePropertyPixelWidth] as? Int
        let sourceHeight = sourceProperties?[kCGImagePropertyPixelHeight] as? Int
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw NormalizationError.decodeFailed
        }
        let normalizedWidth = cgImage.width
        let normalizedHeight = cgImage.height

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NormalizationError.encodeFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw NormalizationError.encodeFailed
        }

        let normalizedData = mutableData as Data
        let sourceDimensions: String
        if let sourceWidth, let sourceHeight {
            sourceDimensions = "\(sourceWidth)x\(sourceHeight)"
        } else {
            sourceDimensions = "unknown"
        }
        ConsoleLog.info(
            "Normalized attached image raw_bytes=\(rawData.count) png_bytes=\(normalizedData.count) source_dimensions=\(sourceDimensions) png_dimensions=\(normalizedWidth)x\(normalizedHeight) max_pixel_dimension=\(maxPixelDimension).",
            category: "ImageNormalizer"
        )
        return normalizedData
    }
}
