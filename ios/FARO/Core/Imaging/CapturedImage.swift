import Foundation

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
