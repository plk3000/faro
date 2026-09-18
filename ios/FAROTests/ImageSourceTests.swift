import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FARO

struct ImageSourceTests {
    @Test
    func fixtureSourceCapturesWithoutCamera() async throws {
        let source = FixtureImageSource(resourceNames: ["kitchen-a"])

        let image = try await source.capture()

        #expect(!image.data.isEmpty)
        #expect(image.format == .png)
        #expect(
            try CapturedImage.Format.detect(from: image.data) == .png
        )
    }

    @Test
    func detectsPNGFromFixtureBytes() async throws {
        let image = try await TestImageFixture.capturedPNG()

        #expect(
            try CapturedImage.Format.detect(from: image.data) == .png
        )
    }

    @Test
    func detectsJPEGFromEncodedFixtureBytes() async throws {
        let jpegData = try await TestImageFixture.encoded(as: .jpeg)

        #expect(
            try CapturedImage.Format.detect(from: jpegData) == .jpeg
        )
    }

    @Test
    func detectsHEICFromEncodedFixtureBytes() async throws {
        let heicData = try await TestImageFixture.encoded(as: .heic)

        #expect(
            try CapturedImage.Format.detect(from: heicData) == .heic
        )
    }

    @Test
    func cameraProcessorNormalizesJPEGAndKeepsJPEGMetadata() async throws {
        let jpegData = try await TestImageFixture.encoded(as: .jpeg)

        let image = try CameraPhotoProcessor.process(jpegData)

        #expect(image.format == .jpeg)
        #expect(image.format.mimeType == "image/jpeg")
        #expect(image.data.starts(with: [0xFF, 0xD8]))
        #expect(
            try CapturedImage.Format.detect(from: image.data) == .jpeg
        )
    }

    @Test
    func cameraProcessorKeepsHEICBytesAndMetadata() async throws {
        let heicData = try await TestImageFixture.encoded(as: .heic)

        let image = try CameraPhotoProcessor.process(heicData)

        #expect(image.data == heicData)
        #expect(image.format == .heic)
        #expect(image.format.mimeType == "image/heic")
    }

    @Test(arguments: [
        Data(),
        Data("not an image".utf8),
        Data([0xFF, 0xD8])
    ])
    func rejectsEmptyUnknownAndIncompleteImageData(
        data: Data
    ) {
        #expect(throws: ImageSourceError.invalidImageData) {
            _ = try CapturedImage.Format.detect(from: data)
        }
    }

    @Test
    func rejectsValidButUnsupportedImageContainer() async throws {
        let gifData = try await TestImageFixture.encoded(as: .gif)

        #expect(throws: ImageSourceError.invalidImageData) {
            _ = try CapturedImage.Format.detect(from: gifData)
        }
    }
}
