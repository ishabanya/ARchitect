import Foundation
import SceneKit
import ARKit

// MARK: - AR Object Model

public struct ARObject: Identifiable, Codable, Equatable {
    public let id: UUID
    public let name: String
    public let type: ObjectType
    public let modelPath: String?
    public var transform: ObjectTransform
    public var material: String
    public var metadata: [String: String]
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        type: ObjectType,
        modelPath: String? = nil,
        transform: ObjectTransform = ObjectTransform(),
        material: String = "default",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.modelPath = modelPath
        self.transform = transform
        self.material = material
        self.metadata = metadata
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    public static func == (lhs: ARObject, rhs: ARObject) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Object Transform

public struct ObjectTransform: Codable {
    public var position: SIMD3<Float>
    public var rotation: SIMD3<Float>
    public var scale: SIMD3<Float>
    
    public init(
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        rotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

// MARK: - Object Type

public enum ObjectType: String, CaseIterable, Codable {
    case furniture = "furniture"
    case decoration = "decoration"
    case lighting = "lighting"
    case plant = "plant"
    case art = "art"
    case structural = "structural"
    case measurement = "measurement"
    case custom = "custom"
}