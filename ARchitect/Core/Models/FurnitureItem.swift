import Foundation
import RealityKit

struct FurnitureItem {
    let id: UUID
    let name: String
    let category: FurnitureCategory
    let dimensions: FurnitureDimensions
    let modelResource: String
    let position: SIMD3<Float>
    let rotation: SIMD3<Float>
    let scale: SIMD3<Float>
    let isPlaced: Bool
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        category: FurnitureCategory,
        dimensions: FurnitureDimensions,
        modelResource: String,
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        rotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.dimensions = dimensions
        self.modelResource = modelResource
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.isPlaced = false
        self.createdAt = Date()
    }
}

enum FurnitureCategory: String, CaseIterable {
    case chair = "Chair"
    case table = "Table"
    case sofa = "Sofa"
    case bed = "Bed"
    case desk = "Desk"
    case bookshelf = "Bookshelf"
    case lamp = "Lamp"
    case plant = "Plant"
    case artwork = "Artwork"
    case storage = "Storage"
}

struct FurnitureDimensions {
    let width: Float
    let height: Float
    let depth: Float
}