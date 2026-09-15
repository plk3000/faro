import Foundation
import ImageIO
import UniformTypeIdentifiers

struct StoredImage: Identifiable, Equatable, Sendable {
    let filename: String
    let createdAt: Date
    let url: URL

    var id: String { filename }
}

enum ImageStoreError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding
{
    case cannotCreateDirectory
    case invalidImage
    case cannotCreateJPEG
    case cannotWriteImage
    case cannotListImages

    var appMessage: AppMessage {
        switch self {
        case .cannotCreateDirectory:
            AppMessage(.errorStoreDirectory)
        case .invalidImage:
            AppMessage(.errorStoreInvalidImage)
        case .cannotCreateJPEG:
            AppMessage(.errorStoreJPEG)
        case .cannotWriteImage:
            AppMessage(.errorStoreWrite)
        case .cannotListImages:
            AppMessage(.errorStoreList)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}

actor ImageStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.directoryURL = applicationSupport
                .appendingPathComponent("FARO", isDirectory: true)
                .appendingPathComponent("Captures", isDirectory: true)
        }
    }

    func save(_ image: CapturedImage) throws -> StoredImage {
        try createDirectoryIfNeeded()

        let filename = "capture-\(UUID().uuidString.lowercased()).jpg"
        let url = directoryURL.appendingPathComponent(filename)
        try writeJPEG(from: image.data, to: url)

        return StoredImage(
            filename: filename,
            createdAt: image.capturedAt,
            url: url
        )
    }

    func list() throws -> [StoredImage] {
        try createDirectoryIfNeeded()

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ImageStoreError.cannotListImages
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .map { url in
                let values = try? url.resourceValues(
                    forKeys: [.creationDateKey]
                )
                return StoredImage(
                    filename: url.lastPathComponent,
                    createdAt: values?.creationDate ?? .distantPast,
                    url: url
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func load(_ storedImage: StoredImage) throws -> Data {
        try load(filename: storedImage.filename)
    }

    func load(filename: String) throws -> Data {
        let url = directoryURL.appendingPathComponent(filename)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ImageStoreError.invalidImage
        }
    }

    func delete(filename: String) throws {
        let url = directoryURL.appendingPathComponent(filename)
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw ImageStoreError.cannotWriteImage
        }
    }

    private func createDirectoryIfNeeded() throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ImageStoreError.cannotCreateDirectory
        }
    }

    private func writeJPEG(from data: Data, to url: URL) throws {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageStoreError.invalidImage
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageStoreError.cannotCreateJPEG
        }

        let properties = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageStoreError.cannotWriteImage
        }
    }
}
