import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CapturedImage: Sendable, Equatable {
    enum Format: String, Sendable {
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

        static func detect(from data: Data) -> Self? {
            guard let imageSource = CGImageSourceCreateWithData(
                data as CFData,
                nil
            ), let typeIdentifier = CGImageSourceGetType(imageSource) as String? else {
                return nil
            }

            switch typeIdentifier {
            case UTType.jpeg.identifier:
                .jpeg
            case UTType.png.identifier:
                .png
            case UTType.heic.identifier, UTType.heif.identifier:
                .heic
            default:
                nil
            }
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
