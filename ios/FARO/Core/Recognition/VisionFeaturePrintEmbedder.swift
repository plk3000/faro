import CoreML
import Foundation
import Vision

struct VisionFeaturePrintEmbedder: ImageEmbedder {
    let modelIdentifier = "apple-vision-feature-print-revision-2"

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
            payload: observation.data,
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
        try first.distance(to: second, expectedModel: modelIdentifier)
    }
}
