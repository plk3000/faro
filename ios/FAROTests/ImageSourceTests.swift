import Testing
@testable import FARO

struct ImageSourceTests {
    @Test
    func fixtureSourceCapturesWithoutCamera() async throws {
        let source = FixtureImageSource(resourceNames: ["kitchen-a"])

        let image = try await source.capture()

        #expect(!image.data.isEmpty)
        #expect(image.format == .png)
        #expect(CapturedImage.Format.detect(from: image.data) == .png)
    }
}
