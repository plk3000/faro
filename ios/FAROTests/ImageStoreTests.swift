import Foundation
import Testing
@testable import FARO

struct ImageStoreTests {
    @Test
    func savesFixturesAsPersistentJPEGs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let source = FixtureImageSource(resourceNames: ["kitchen-a"])
        let store = ImageStore(directoryURL: directory)
        let image = try await source.capture()

        let stored = try await store.save(image)
        let reloaded = try await store.list()
        let data = try await store.load(stored)

        #expect(stored.url.pathExtension == "jpg")
        #expect(reloaded.map(\.filename) == [stored.filename])
        #expect(data.starts(with: [0xFF, 0xD8]))
    }
}
