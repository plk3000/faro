import Foundation

private final class FixtureResourceMarker {}

actor FixtureImageSource: ImageSource {
    private let resourceNames: [String]
    private let bundle: Bundle
    private var nextIndex = 0

    init(
        resourceNames: [String] = [
            "kitchen-a",
            "kitchen-b",
            "bedroom-a"
        ],
        bundle: Bundle? = nil
    ) {
        precondition(!resourceNames.isEmpty)
        self.resourceNames = resourceNames
        self.bundle = bundle ?? Bundle(for: FixtureResourceMarker.self)
    }

    func capture() async throws -> CapturedImage {
        let name = resourceNames[nextIndex]
        nextIndex = (nextIndex + 1) % resourceNames.count

        guard let url = bundle.url(forResource: name, withExtension: "png") else {
            throw ImageSourceError.fixtureNotFound(name)
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ImageSourceError.invalidImageData
        }

        return CapturedImage(data: data, format: .png)
    }
}
