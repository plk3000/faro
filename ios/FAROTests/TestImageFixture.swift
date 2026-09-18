import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import FARO

enum TestImageFixture {
    static func capturedPNG() async throws -> CapturedImage {
        try await FixtureImageSource(
            resourceNames: ["kitchen-a"]
        ).capture()
    }

    static func encoded(as type: UTType) async throws -> Data {
        let fixture = try await capturedPNG()
        guard let source = CGImageSourceCreateWithData(
            fixture.data as CFData,
            nil
        ),
        let image = CGImageSourceCreateImageAtIndex(
            source,
            0,
            nil
        ) else {
            throw ImageSourceError.invalidImageData
        }

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageSourceError.invalidImageData
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageSourceError.invalidImageData
        }
        return encodedData as Data
    }
}
