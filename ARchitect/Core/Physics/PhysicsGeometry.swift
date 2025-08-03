import Foundation
import simd
import RealityKit

// MARK: - Collider Geometry

public protocol ColliderGeometry {
    var type: GeometryType { get }
    var bounds: BoundingBox { get }
}

public enum GeometryType: String, CaseIterable {
    case sphere = "sphere"
    case box = "box"
    case plane = "plane"
    case mesh = "mesh"
}

// MARK: - Sphere Geometry

public struct SphereGeometry: ColliderGeometry {
    public let radius: Float
    public let center: SIMD3<Float>
    
    public var type: GeometryType { .sphere }
    
    public var bounds: BoundingBox {
        return BoundingBox(
            min: center - SIMD3<Float>(radius, radius, radius),
            max: center + SIMD3<Float>(radius, radius, radius)
        )
    }
    
    public init(radius: Float, center: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) {
        self.radius = radius
        self.center = center
    }
    
    public func contains(point: SIMD3<Float>) -> Bool {
        let distance = simd_distance(point, center)
        return distance <= radius
    }
    
    public func intersects(sphere: SphereGeometry) -> Bool {
        let distance = simd_distance(center, sphere.center)
        return distance <= (radius + sphere.radius)
    }
    
    public func intersects(box: BoxGeometry) -> Bool {
        // Find closest point on box to sphere center
        let closestPoint = SIMD3<Float>(
            max(box.bounds.min.x, min(center.x, box.bounds.max.x)),
            max(box.bounds.min.y, min(center.y, box.bounds.max.y)),
            max(box.bounds.min.z, min(center.z, box.bounds.max.z))
        )
        
        let distance = simd_distance(center, closestPoint)
        return distance <= radius
    }
}

// MARK: - Box Geometry

public struct BoxGeometry: ColliderGeometry {
    public let size: SIMD3<Float>
    public let center: SIMD3<Float>
    
    public var type: GeometryType { .box }
    
    public var bounds: BoundingBox {
        let halfSize = size * 0.5
        return BoundingBox(
            min: center - halfSize,
            max: center + halfSize
        )
    }
    
    public init(size: SIMD3<Float>, center: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) {
        self.size = size
        self.center = center
    }
    
    public func contains(point: SIMD3<Float>) -> Bool {
        let halfSize = size * 0.5
        let localPoint = point - center
        
        return abs(localPoint.x) <= halfSize.x &&
               abs(localPoint.y) <= halfSize.y &&
               abs(localPoint.z) <= halfSize.z
    }
    
    public func intersects(box: BoxGeometry) -> Bool {
        let halfSizeA = size * 0.5
        let halfSizeB = box.size * 0.5
        
        let distance = abs(center - box.center)
        let combinedHalfSizes = halfSizeA + halfSizeB
        
        return distance.x <= combinedHalfSizes.x &&
               distance.y <= combinedHalfSizes.y &&
               distance.z <= combinedHalfSizes.z
    }
    
    public func intersects(sphere: SphereGeometry) -> Bool {
        return sphere.intersects(box: self)
    }
    
    public func getVertices() -> [SIMD3<Float>] {
        let halfSize = size * 0.5
        
        return [
            center + SIMD3<Float>(-halfSize.x, -halfSize.y, -halfSize.z),
            center + SIMD3<Float>( halfSize.x, -halfSize.y, -halfSize.z),
            center + SIMD3<Float>(-halfSize.x,  halfSize.y, -halfSize.z),
            center + SIMD3<Float>( halfSize.x,  halfSize.y, -halfSize.z),
            center + SIMD3<Float>(-halfSize.x, -halfSize.y,  halfSize.z),
            center + SIMD3<Float>( halfSize.x, -halfSize.y,  halfSize.z),
            center + SIMD3<Float>(-halfSize.x,  halfSize.y,  halfSize.z),
            center + SIMD3<Float>( halfSize.x,  halfSize.y,  halfSize.z)
        ]
    }
}

// MARK: - Plane Geometry

public struct PlaneGeometry: ColliderGeometry {
    public let normal: SIMD3<Float>
    public let distance: Float // Distance from origin along normal
    public let bounds: BoundingBox
    
    public var type: GeometryType { .plane }
    
    public init(normal: SIMD3<Float>, distance: Float, bounds: BoundingBox) {
        self.normal = simd_normalize(normal)
        self.distance = distance
        self.bounds = bounds
    }
    
    public init(point: SIMD3<Float>, normal: SIMD3<Float>, size: SIMD2<Float>) {
        self.normal = simd_normalize(normal)
        self.distance = simd_dot(point, self.normal)
        
        // Create bounds for finite plane
        let halfSize = SIMD3<Float>(size.x * 0.5, 0.01, size.y * 0.5) // Thin plane
        self.bounds = BoundingBox(
            min: point - halfSize,
            max: point + halfSize
        )
    }
    
    public func distanceToPoint(_ point: SIMD3<Float>) -> Float {
        return simd_dot(point, normal) - distance
    }
    
    public func contains(point: SIMD3<Float>) -> Bool {
        return abs(distanceToPoint(point)) < 0.001 // Very thin tolerance
    }
    
    public func projectPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let distanceToPlane = distanceToPoint(point)
        return point - normal * distanceToPlane
    }
    
    public func intersects(sphere: SphereGeometry) -> Bool {
        let distanceToCenter = abs(distanceToPoint(sphere.center))
        return distanceToCenter <= sphere.radius
    }
    
    public func intersects(box: BoxGeometry) -> Bool {
        // Check if box intersects plane by testing vertices
        let vertices = box.getVertices()
        var positiveCount = 0
        var negativeCount = 0
        
        for vertex in vertices {
            let distance = distanceToPoint(vertex)
            if distance > 0 {
                positiveCount += 1
            } else {
                negativeCount += 1
            }
        }
        
        // If vertices are on both sides of the plane, there's an intersection
        return positiveCount > 0 && negativeCount > 0
    }
}

// MARK: - Mesh Geometry

public struct MeshGeometry: ColliderGeometry {
    public let vertices: [SIMD3<Float>]
    public let indices: [UInt32]
    public let bounds: BoundingBox
    
    public var type: GeometryType { .mesh }
    
    public init(vertices: [SIMD3<Float>], indices: [UInt32]) {
        self.vertices = vertices
        self.indices = indices
        
        // Calculate bounds
        if vertices.isEmpty {
            self.bounds = BoundingBox(min: SIMD3<Float>(0, 0, 0), max: SIMD3<Float>(0, 0, 0))
        } else {
            var minPoint = vertices[0]
            var maxPoint = vertices[0]
            
            for vertex in vertices {
                minPoint = simd_min(minPoint, vertex)
                maxPoint = simd_max(maxPoint, vertex)
            }
            
            self.bounds = BoundingBox(min: minPoint, max: maxPoint)
        }
    }
    
    public init(mesh: MeshResource) {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Extract vertices and indices from RealityKit mesh
        // This is a simplified extraction - real implementation would need more complex mesh parsing
        
        // For now, create a bounding box representation
        let bounds = mesh.bounds
        let boxGeometry = BoxGeometry(size: bounds.extents, center: bounds.center)
        let boxVertices = boxGeometry.getVertices()
        
        vertices = boxVertices
        indices = [
            // Front face
            0, 1, 2, 1, 3, 2,
            // Back face
            4, 6, 5, 5, 6, 7,
            // Left face
            0, 2, 4, 2, 6, 4,
            // Right face
            1, 5, 3, 3, 5, 7,
            // Top face
            2, 3, 6, 3, 7, 6,
            // Bottom face
            0, 4, 1, 1, 4, 5
        ]
        
        self.vertices = vertices
        self.indices = indices
        self.bounds = BoundingBox(min: bounds.min, max: bounds.max)
    }
    
    public func contains(point: SIMD3<Float>) -> Bool {
        // Simplified point-in-mesh test using ray casting
        return raycastIntersection(from: point, direction: SIMD3<Float>(1, 0, 0)) % 2 == 1
    }
    
    public func raycastIntersection(from origin: SIMD3<Float>, direction: SIMD3<Float>) -> Int {
        var intersectionCount = 0
        
        // Test ray against all triangles
        for i in stride(from: 0, to: indices.count, by: 3) {
            let v0 = vertices[Int(indices[i])]
            let v1 = vertices[Int(indices[i + 1])]
            let v2 = vertices[Int(indices[i + 2])]
            
            if rayTriangleIntersection(origin: origin, direction: direction, v0: v0, v1: v1, v2: v2) {
                intersectionCount += 1
            }
        }
        
        return intersectionCount
    }
    
    private func rayTriangleIntersection(origin: SIMD3<Float>, direction: SIMD3<Float>, v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>) -> Bool {
        // Möller-Trumbore ray-triangle intersection algorithm
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = simd_cross(direction, edge2)
        let a = simd_dot(edge1, h)
        
        if a > -0.00001 && a < 0.00001 {
            return false // Ray is parallel to triangle
        }
        
        let f = 1.0 / a
        let s = origin - v0
        let u = f * simd_dot(s, h)
        
        if u < 0.0 || u > 1.0 {
            return false
        }
        
        let q = simd_cross(s, edge1)
        let v = f * simd_dot(direction, q)
        
        if v < 0.0 || u + v > 1.0 {
            return false
        }
        
        let t = f * simd_dot(edge2, q)
        
        return t > 0.00001 // Ray intersection
    }
    
    public func getTriangles() -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            let v0 = vertices[Int(indices[i])]
            let v1 = vertices[Int(indices[i + 1])]
            let v2 = vertices[Int(indices[i + 2])]
            triangles.append((v0, v1, v2))
        }
        
        return triangles
    }
}

// MARK: - Bounding Box

public struct BoundingBox: Codable, Equatable {
    public let min: SIMD3<Float>
    public let max: SIMD3<Float>
    
    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }
    
    public var center: SIMD3<Float> {
        return (min + max) * 0.5
    }
    
    public var extents: SIMD3<Float> {
        return max - min
    }
    
    public var volume: Float {
        let size = extents
        return size.x * size.y * size.z
    }
    
    public func contains(point: SIMD3<Float>) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }
    
    public func intersects(_ other: BoundingBox) -> Bool {
        return min.x <= other.max.x && max.x >= other.min.x &&
               min.y <= other.max.y && max.y >= other.min.y &&
               min.z <= other.max.z && max.z >= other.min.z
    }
    
    public func union(with other: BoundingBox) -> BoundingBox {
        return BoundingBox(
            min: simd_min(min, other.min),
            max: simd_max(max, other.max)
        )
    }
    
    public func intersection(with other: BoundingBox) -> BoundingBox? {
        let newMin = simd_max(min, other.min)
        let newMax = simd_min(max, other.max)
        
        if newMin.x <= newMax.x && newMin.y <= newMax.y && newMin.z <= newMax.z {
            return BoundingBox(min: newMin, max: newMax)
        }
        
        return nil
    }
    
    public func expanded(by amount: Float) -> BoundingBox {
        let expansion = SIMD3<Float>(amount, amount, amount)
        return BoundingBox(min: min - expansion, max: max + expansion)
    }
    
    public func getVertices() -> [SIMD3<Float>] {
        return [
            SIMD3<Float>(min.x, min.y, min.z),
            SIMD3<Float>(max.x, min.y, min.z),
            SIMD3<Float>(min.x, max.y, min.z),
            SIMD3<Float>(max.x, max.y, min.z),
            SIMD3<Float>(min.x, min.y, max.z),
            SIMD3<Float>(max.x, min.y, max.z),
            SIMD3<Float>(min.x, max.y, max.z),
            SIMD3<Float>(max.x, max.y, max.z)
        ]
    }
}

// MARK: - Geometry Utilities

public class GeometryUtils {
    
    public static func createBoxFromEntity(_ entity: Entity) -> BoxGeometry {
        let bounds = entity.visualBounds(relativeTo: nil)
        return BoxGeometry(size: bounds.extents, center: bounds.center)
    }
    
    public static func createSphereFromEntity(_ entity: Entity) -> SphereGeometry {
        let bounds = entity.visualBounds(relativeTo: nil)
        let radius = simd_length(bounds.extents) * 0.5
        return SphereGeometry(radius: radius, center: bounds.center)
    }
    
    public static func createMeshFromEntity(_ entity: Entity) -> MeshGeometry? {
        guard let modelEntity = entity as? ModelEntity,
              let mesh = modelEntity.model?.mesh else {
            return nil
        }
        
        return MeshGeometry(mesh: mesh)
    }
    
    public static func calculateVolume(of geometry: ColliderGeometry) -> Float {
        switch geometry.type {
        case .sphere:
            if let sphere = geometry as? SphereGeometry {
                return (4.0 / 3.0) * Float.pi * pow(sphere.radius, 3)
            }
            
        case .box:
            if let box = geometry as? BoxGeometry {
                return box.size.x * box.size.y * box.size.z
            }
            
        case .plane:
            return 0.0 // Planes have no volume
            
        case .mesh:
            if let mesh = geometry as? MeshGeometry {
                return calculateMeshVolume(mesh)
            }
        }
        
        return 0.0
    }
    
    public static func calculateSurfaceArea(of geometry: ColliderGeometry) -> Float {
        switch geometry.type {
        case .sphere:
            if let sphere = geometry as? SphereGeometry {
                return 4.0 * Float.pi * pow(sphere.radius, 2)
            }
            
        case .box:
            if let box = geometry as? BoxGeometry {
                let size = box.size
                return 2.0 * (size.x * size.y + size.y * size.z + size.z * size.x)
            }
            
        case .plane:
            if let plane = geometry as? PlaneGeometry {
                let extents = plane.bounds.extents
                return extents.x * extents.z // Assume plane is in XZ plane
            }
            
        case .mesh:
            if let mesh = geometry as? MeshGeometry {
                return calculateMeshSurfaceArea(mesh)
            }
        }
        
        return 0.0
    }
    
    private static func calculateMeshVolume(_ mesh: MeshGeometry) -> Float {
        // Simplified volume calculation using divergence theorem
        var volume: Float = 0.0
        let triangles = mesh.getTriangles()
        
        for (v0, v1, v2) in triangles {
            // Calculate signed volume of tetrahedron formed by triangle and origin
            let signedVolume = simd_dot(v0, simd_cross(v1, v2)) / 6.0
            volume += signedVolume
        }
        
        return abs(volume)
    }
    
    private static func calculateMeshSurfaceArea(_ mesh: MeshGeometry) -> Float {
        var area: Float = 0.0
        let triangles = mesh.getTriangles()
        
        for (v0, v1, v2) in triangles {
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let cross = simd_cross(edge1, edge2)
            area += simd_length(cross) * 0.5
        }
        
        return area
    }
}

// MARK: - Geometry Factory

public class GeometryFactory {
    
    public static func createSphere(radius: Float) -> SphereGeometry {
        return SphereGeometry(radius: radius)
    }
    
    public static func createBox(width: Float, height: Float, depth: Float) -> BoxGeometry {
        return BoxGeometry(size: SIMD3<Float>(width, height, depth))
    }
    
    public static func createPlane(normal: SIMD3<Float>, point: SIMD3<Float>, size: SIMD2<Float>) -> PlaneGeometry {
        return PlaneGeometry(point: point, normal: normal, size: size)
    }
    
    public static func createFloorPlane(at height: Float, size: SIMD2<Float>) -> PlaneGeometry {
        return PlaneGeometry(
            point: SIMD3<Float>(0, height, 0),
            normal: SIMD3<Float>(0, 1, 0),
            size: size
        )
    }
    
    public static func createWallPlane(normal: SIMD3<Float>, distance: Float, size: SIMD2<Float>) -> PlaneGeometry {
        let point = normal * distance
        return PlaneGeometry(point: point, normal: normal, size: size)
    }
    
    public static func createMeshFromVertices(_ vertices: [SIMD3<Float>], indices: [UInt32]) -> MeshGeometry {
        return MeshGeometry(vertices: vertices, indices: indices)
    }
}

// MARK: - SIMD Extensions for Codable

extension SIMD3: Codable where Scalar: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Scalar.self)
        let y = try container.decode(Scalar.self)
        let z = try container.decode(Scalar.self)
        self.init(x, y, z)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}