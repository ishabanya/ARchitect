import Foundation
import ARKit
import RealityKit

struct Room {
    let id: UUID
    let name: String
    let dimensions: RoomDimensions
    let floorPlan: [SIMD3<Float>]
    let walls: [Wall]
    let furniture: [FurnitureItem]
    let createdAt: Date
    let updatedAt: Date
    
    init(id: UUID = UUID(), name: String, dimensions: RoomDimensions) {
        self.id = id
        self.name = name
        self.dimensions = dimensions
        self.floorPlan = []
        self.walls = []
        self.furniture = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct RoomDimensions {
    let width: Float
    let length: Float
    let height: Float
}

struct Wall {
    let id: UUID
    let startPoint: SIMD3<Float>
    let endPoint: SIMD3<Float>
    let height: Float
    let thickness: Float
    
    init(startPoint: SIMD3<Float>, endPoint: SIMD3<Float>, height: Float, thickness: Float = 0.1) {
        self.id = UUID()
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.height = height
        self.thickness = thickness
    }
}