import Foundation

struct ImageEmbedding: Codable, Equatable, Sendable {
    enum ComponentType: String, Codable, Sendable {
        case float32
        case float64
    }

    let modelIdentifier: String
    let payload: Data
    let componentType: ComponentType
    let componentCount: Int

    func distance(
        to other: ImageEmbedding,
        expectedModel: String
    ) throws -> Double {
        guard modelIdentifier == other.modelIdentifier,
              modelIdentifier == expectedModel,
              componentType == other.componentType,
              componentCount == other.componentCount else {
            throw ImageEmbeddingError.incompatibleModels
        }

        let componentSize = componentType == .float32
            ? MemoryLayout<Float>.size
            : MemoryLayout<Double>.size
        let expectedBytes = componentCount * componentSize
        guard componentCount > 0,
              payload.count == expectedBytes,
              other.payload.count == expectedBytes else {
            throw ImageEmbeddingError.invalidPayload
        }

        var squaredDistance = 0.0
        for index in 0..<componentCount {
            let offset = index * componentSize
            let difference = component(at: offset)
                - other.component(at: offset)
            squaredDistance += difference * difference
        }
        return squaredDistance.squareRoot()
    }

    private func component(at offset: Int) -> Double {
        switch componentType {
        case .float32:
            var bits: UInt32 = 0
            _ = Swift.withUnsafeMutableBytes(of: &bits) {
                payload.copyBytes(to: $0, from: offset..<(offset + 4))
            }
            return Double(Float(bitPattern: UInt32(littleEndian: bits)))
        case .float64:
            var bits: UInt64 = 0
            _ = Swift.withUnsafeMutableBytes(of: &bits) {
                payload.copyBytes(to: $0, from: offset..<(offset + 8))
            }
            return Double(bitPattern: UInt64(littleEndian: bits))
        }
    }
}

protocol ImageEmbedder: Sendable {
    var modelIdentifier: String { get }

    func embed(_ image: CapturedImage) async throws -> ImageEmbedding
    func distance(
        between first: ImageEmbedding,
        and second: ImageEmbedding
    ) throws -> Double
}

enum ImageEmbedderFactory {
    static func makeDefault() -> any ImageEmbedder {
#if targetEnvironment(simulator)
        PixelGridEmbedder()
#else
        VisionFeaturePrintEmbedder()
#endif
    }
}

enum ImageEmbeddingError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding
{
    case incompatibleModels
    case invalidPayload

    var appMessage: AppMessage {
        switch self {
        case .incompatibleModels:
            AppMessage(.errorEmbeddingIncompatible)
        case .invalidPayload:
            AppMessage(.errorEmbeddingInvalid)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}
