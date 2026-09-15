import CoreML
import Foundation
import Vision

struct VisionFeaturePrintEmbedder: ImageEmbedder {
    static let identifier =
        "apple-vision-feature-print-revision-2-codable-v1"

    let modelIdentifier = Self.identifier

    func embed(_ image: CapturedImage) async throws -> ImageEmbedding {
        let handler = ImageRequestHandler(image.data)
        var request = GenerateImageFeaturePrintRequest(.revision2)
#if targetEnvironment(simulator)
        if let cpu = MLComputeDevice.allComputeDevices.first(where: {
            if case .cpu = $0 {
                return true
            }
            return false
        }) {
            request.setComputeDevice(cpu, for: .main)
        }
#endif
        let observation = try await handler.perform(request)
        return ImageEmbedding(
            modelIdentifier: modelIdentifier,
            payload: try JSONEncoder().encode(observation),
            componentType: observation.elementType == .float
                ? .float32
                : .float64,
            componentCount: observation.elementCount
        )
    }

    func distance(
        between first: ImageEmbedding,
        and second: ImageEmbedding
    ) throws -> Double {
        guard first.modelIdentifier == modelIdentifier,
              second.modelIdentifier == modelIdentifier,
              first.componentType == second.componentType,
              first.componentCount == second.componentCount else {
            throw ImageEmbeddingError.incompatibleModels
        }

        do {
            let decoder = JSONDecoder()
            let firstObservation = try decoder.decode(
                FeaturePrintObservation.self,
                from: first.payload
            )
            let secondObservation = try decoder.decode(
                FeaturePrintObservation.self,
                from: second.payload
            )
            return try firstObservation.distance(to: secondObservation)
        } catch let error as ImageEmbeddingError {
            throw error
        } catch {
            throw ImageEmbeddingError.invalidPayload
        }
    }
}
