import Foundation
import SwiftData

@Model
final class Place {
    @Attribute(.unique) var id: UUID
    var label: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlaceSnapshot.place)
    var snapshots: [PlaceSnapshot]

    init(
        id: UUID = UUID(),
        label: String,
        createdAt: Date = .now,
        snapshots: [PlaceSnapshot] = []
    ) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
        self.snapshots = snapshots
    }
}

@Model
final class PlaceSnapshot {
    @Attribute(.unique) var id: UUID
    var imageFilename: String
    var embeddingData: Data
    var embeddingModel: String
    var embeddingComponentType: String
    var embeddingComponentCount: Int
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var headingDegrees: Double?
    var place: Place?

    init(
        id: UUID = UUID(),
        imageFilename: String,
        embeddingData: Data,
        embeddingModel: String,
        embeddingComponentType: String,
        embeddingComponentCount: Int,
        capturedAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        headingDegrees: Double? = nil
    ) {
        self.id = id
        self.imageFilename = imageFilename
        self.embeddingData = embeddingData
        self.embeddingModel = embeddingModel
        self.embeddingComponentType = embeddingComponentType
        self.embeddingComponentCount = embeddingComponentCount
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.headingDegrees = headingDegrees
    }

    convenience init(
        imageFilename: String,
        embedding: ImageEmbedding,
        capturedAt: Date = .now,
        location: LocationSnapshot? = nil
    ) {
        self.init(
            imageFilename: imageFilename,
            embeddingData: embedding.payload,
            embeddingModel: embedding.modelIdentifier,
            embeddingComponentType: embedding.componentType.rawValue,
            embeddingComponentCount: embedding.componentCount,
            capturedAt: capturedAt,
            latitude: location?.latitude,
            longitude: location?.longitude,
            horizontalAccuracy: location?.horizontalAccuracy,
            headingDegrees: location?.headingDegrees
        )
    }

    func imageEmbedding() throws -> ImageEmbedding {
        guard let componentType = ImageEmbedding.ComponentType(
            rawValue: embeddingComponentType
        ),
        embeddingComponentCount > 0 else {
            throw ImageEmbeddingError.invalidPayload
        }

        return ImageEmbedding(
            modelIdentifier: embeddingModel,
            payload: embeddingData,
            componentType: componentType,
            componentCount: embeddingComponentCount
        )
    }

    var locationSnapshot: LocationSnapshot? {
        guard let latitude,
              let longitude,
              let horizontalAccuracy else {
            return nil
        }
        return LocationSnapshot(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            headingDegrees: headingDegrees
        )
    }
}
