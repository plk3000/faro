import CoreGraphics
import Foundation
import ImageIO

/// Deterministic simulator implementation; physical devices use Vision FeaturePrint.
struct PixelGridEmbedder: ImageEmbedder {
    static let identifier = "faro-pixel-grid-16-v1"
    let modelIdentifier = Self.identifier

    func embed(_ image: CapturedImage) async throws -> ImageEmbedding {
        guard let source = CGImageSourceCreateWithData(
            image.data as CFData,
            nil
        ),
        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageSourceError.invalidImageData
        }

        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageSourceError.invalidImageData
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var payload = Data(capacity: side * side * MemoryLayout<Float>.size)
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let luminance = (
                0.2126 * Float(pixels[pixel])
                + 0.7152 * Float(pixels[pixel + 1])
                + 0.0722 * Float(pixels[pixel + 2])
            ) / 255
            var bits = luminance.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) {
                payload.append(contentsOf: $0)
            }
        }

        return ImageEmbedding(
            modelIdentifier: modelIdentifier,
            payload: payload,
            componentType: .float32,
            componentCount: side * side
        )
    }

    func distance(
        between first: ImageEmbedding,
        and second: ImageEmbedding
    ) throws -> Double {
        try first.distance(to: second, expectedModel: modelIdentifier)
    }
}
