import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

struct CapturedImage: Sendable, Equatable {
    enum Format: String, Sendable {
        private static let logger = Logger(
            subsystem: "com.jdsolissmith.faro",
            category: "ImageFormat"
        )

        case jpeg
        case png
        case heic

        var mimeType: String {
            switch self {
            case .jpeg:
                "image/jpeg"
            case .png:
                "image/png"
            case .heic:
                "image/heic"
            }
        }

        static func detect(from data: Data) throws -> Self {
            guard !data.isEmpty,
                  let source = CGImageSourceCreateWithData(
                      data as CFData,
                      nil
                  ),
                  CGImageSourceGetCount(source) > 0,
                  CGImageSourceGetStatus(source) == .statusComplete,
                  CGImageSourceGetStatusAtIndex(source, 0)
                      == .statusComplete,
                  let typeIdentifier = CGImageSourceGetType(source)
            else {
                throw ImageSourceError.invalidImageData
            }

            let identifier = typeIdentifier as String
            Self.logger.info(
                "Validated image container type=\(identifier, privacy: .public) size_bytes=\(data.count)"
            )

            let format: Self
            switch identifier {
            case UTType.jpeg.identifier:
                format = .jpeg
            case UTType.png.identifier:
                format = .png
            case UTType.heic.identifier, UTType.heif.identifier:
                format = .heic
            default:
                guard let type = UTType(identifier),
                      type.conforms(to: .heif) else {
                    throw ImageSourceError.invalidImageData
                }
                format = .heic
            }
            return format
        }
    }

    let data: Data
    let format: Format
    let capturedAt: Date

    init(
        data: Data,
        format: Format,
        capturedAt: Date = .now
    ) {
        self.data = data
        self.format = format
        self.capturedAt = capturedAt
    }
}

enum CameraPhotoProcessor {
    static func process(_ data: Data) throws -> CapturedImage {
        let detectedFormat = try CapturedImage.Format.detect(from: data)
        guard detectedFormat == .jpeg else {
            return CapturedImage(data: data, format: detectedFormat)
        }

        let normalizedData = try normalizeJPEG(data)
        let normalizedFormat = try CapturedImage.Format.detect(
            from: normalizedData
        )
        guard normalizedFormat == .jpeg else {
            throw ImageSourceError.invalidImageData
        }
        return CapturedImage(
            data: normalizedData,
            format: normalizedFormat
        )
    }

    private static func normalizeJPEG(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageSourceError.invalidImageData
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageSourceError.invalidImageData
        }

        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]
        if let sourceProperties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any],
        let orientation = sourceProperties[kCGImagePropertyOrientation] {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw ImageSourceError.invalidImageData
        }
        return output as Data
    }
}
