import Foundation
import SceneKit
import RealityKit
import ARKit
import simd
import Combine

// MARK: - Frustum Culling System

@MainActor
public class FrustumCullingSystem: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var cullingStats: CullingStatistics = CullingStatistics()
    @Published public var isEnabled: Bool = true
    @Published public var cullingMode: CullingMode = .aggressive
    @Published public var processedObjects: Int = 0
    @Published public var visibleObjects: Int = 0
    
    // MARK: - Culling Configuration
    public enum CullingMode {
        case disabled
        case conservative  // Only cull objects clearly outside frustum
        case normal       // Standard frustum culling
        case aggressive   // Aggressive culling with occlusion hints
        
        var cullingDistance: Float {
            switch self {
            case .disabled: return Float.infinity
            case .conservative: return 100.0
            case .normal: return 50.0
            case .aggressive: return 30.0
            }
        }
        
        var occlusionCullingEnabled: Bool {
            switch self {
            case .aggressive: return true
            default: return false
            }
        }
    }
    
    // MARK: - Private Properties
    private var frustumPlanes: [simd_float4] = []
    private var cameraTransform: simd_float4x4 = matrix_identity_float4x4
    private var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
    private var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    
    // Spatial partitioning for efficient culling
    private var spatialGrid: SpatialGrid<CullableObject>
    private var octree: Octree<CullableObject>
    
    // Object tracking
    private var trackedObjects: [ObjectIdentifier: CullableObject] = [:]
    private var visibilityCache: [ObjectIdentifier: VisibilityInfo] = [:]
    
    // Performance monitoring
    private var performanceProfiler: InstrumentsProfiler
    private var lastCullingTime: TimeInterval = 0
    private var cullingFrequency: TimeInterval = 1.0 / 60.0 // 60 FPS
    
    // Async processing
    private let cullingQueue = DispatchQueue(label: "com.architectar.frustumculling", qos: .userInteractive)
    private var cullingTask: Task<Void, Never>?
    
    public init(performanceProfiler: InstrumentsProfiler) {
        self.performanceProfiler = performanceProfiler
        self.spatialGrid = SpatialGrid<CullableObject>(cellSize: 5.0)
        self.octree = Octree<CullableObject>(
            center: simd_float3(0, 0, 0),
            halfSize: 50.0,
            maxDepth: 6
        )
        
        setupFrustumCulling()
        
        logDebug("Frustum culling system initialized", category: .performance)
    }
    
    // MARK: - Setup
    
    private func setupFrustumCulling() {
        // Initialize frustum planes
        frustumPlanes = Array(repeating: simd_float4(0, 0, 0, 0), count: 6)
        
        // Start continuous culling process
        startContinuousCulling()
    }
    
    private func startContinuousCulling() {
        cullingTask = Task {
            while !Task.isCancelled {
                await performCullingPass()
                
                // Wait for next frame
                try? await Task.sleep(nanoseconds: UInt64(cullingFrequency * 1_000_000_000))
            }
        }
    }
    
    // MARK: - Camera Update
    
    public func updateCamera(arFrame: ARFrame) {
        let camera = arFrame.camera
        
        // Update camera matrices
        cameraTransform = camera.transform
        projectionMatrix = camera.projectionMatrix(for: .landscapeRight, viewportSize: CGSize(width: 1920, height: 1080), zNear: 0.1, zFar: 1000.0)
        viewMatrix = camera.viewMatrix(for: .landscapeRight)
        
        // Extract frustum planes from combined view-projection matrix
        extractFrustumPlanes()
        
        // Update culling statistics
        updateCullingStats()
    }
    
    public func updateCamera(scnCamera: SCNCamera, transform: SCNMatrix4) {
        // Convert SCN matrices to simd
        cameraTransform = simd_float4x4(transform)
        
        // Create projection matrix from SCN camera
        let fov = scnCamera.fieldOfView * Float.pi / 180.0
        let aspect = Float(scnCamera.projectionDirection == .vertical ? 16.0/9.0 : 9.0/16.0)
        let near = Float(scnCamera.zNear)
        let far = Float(scnCamera.zFar)
        
        projectionMatrix = createProjectionMatrix(fov: fov, aspect: aspect, near: near, far: far)
        viewMatrix = cameraTransform.inverse
        
        extractFrustumPlanes()
        updateCullingStats()
    }
    
    // MARK: - Object Registration
    
    public func registerObject(_ object: SCNNode, identifier: String) {
        let cullableObject = CullableObject(
            identifier: identifier,
            scnNode: object,
            boundingBox: calculateBoundingBox(for: object),
            lastVisibilityCheck: Date()
        )
        
        let objectID = ObjectIdentifier(object)
        trackedObjects[objectID] = cullableObject
        
        // Add to spatial data structures
        spatialGrid.insert(cullableObject, at: cullableObject.worldPosition)
        octree.insert(cullableObject, at: cullableObject.worldPosition)
        
        logDebug("Registered object for culling", category: .performance, context: LogContext(customData: [
            "identifier": identifier,
            "position": "\(cullableObject.worldPosition)"
        ]))
    }
    
    public func registerEntity(_ entity: Entity, identifier: String) {
        let cullableObject = CullableObject(
            identifier: identifier,
            realityKitEntity: entity,
            boundingBox: calculateBoundingBox(for: entity),
            lastVisibilityCheck: Date()
        )
        
        let objectID = ObjectIdentifier(entity)
        trackedObjects[objectID] = cullableObject
        
        spatialGrid.insert(cullableObject, at: cullableObject.worldPosition)
        octree.insert(cullableObject, at: cullableObject.worldPosition)
        
        logDebug("Registered RealityKit entity for culling", category: .performance, context: LogContext(customData: [
            "identifier": identifier,
            "position": "\(cullableObject.worldPosition)"
        ]))
    }
    
    public func unregisterObject(_ object: Any) {
        let objectID = ObjectIdentifier(object)
        
        if let cullableObject = trackedObjects[objectID] {
            trackedObjects.removeValue(forKey: objectID)
            visibilityCache.removeValue(forKey: objectID)
            
            spatialGrid.remove(cullableObject, from: cullableObject.worldPosition)
            octree.remove(cullableObject, from: cullableObject.worldPosition)
            
            logDebug("Unregistered object from culling", category: .performance, context: LogContext(customData: [
                "identifier": cullableObject.identifier
            ]))
        }
    }
    
    // MARK: - Culling Pass
    
    private func performCullingPass() async {
        guard isEnabled && !trackedObjects.isEmpty else { return }
        
        let startTime = Date()
        performanceProfiler.recordPerformancePoint(PerformancePoint(
            metric: "frustum_culling_start",
            value: startTime.timeIntervalSince1970
        ))
        
        await cullingQueue.run {
            var visibleCount = 0
            var processedCount = 0
            
            // Use spatial partitioning to get potentially visible objects
            let potentiallyVisible = self.getPotentiallyVisibleObjects()
            
            for cullableObject in potentiallyVisible {
                processedCount += 1
                
                let isVisible = self.isObjectVisible(cullableObject)
                let objectID = cullableObject.objectIdentifier
                
                // Update visibility cache
                self.visibilityCache[objectID] = VisibilityInfo(
                    isVisible: isVisible,
                    lastChecked: Date(),
                    framesSinceVisible: isVisible ? 0 : (self.visibilityCache[objectID]?.framesSinceVisible ?? 0) + 1
                )
                
                if isVisible {
                    visibleCount += 1
                }
                
                // Apply culling result
                await MainActor.run {
                    self.applyCullingResult(cullableObject, isVisible: isVisible)
                }
            }
            
            // Update statistics
            await MainActor.run {
                self.processedObjects = processedCount
                self.visibleObjects = visibleCount
                self.cullingStats.updateStats(
                    processed: processedCount,
                    visible: visibleCount,
                    culled: processedCount - visibleCount
                )
            }
        }
        
        let endTime = Date()
        let cullingTime = endTime.timeIntervalSince(startTime)
        lastCullingTime = cullingTime
        
        performanceProfiler.recordPerformancePoint(PerformancePoint(
            metric: "frustum_culling_time",
            value: cullingTime * 1000, // Convert to milliseconds
            threshold: 16.67 // 60 FPS target
        ))
        
        logDebug("Culling pass completed", category: .performance, context: LogContext(customData: [
            "processed_objects": processedObjects,
            "visible_objects": visibleObjects,
            "culling_time_ms": cullingTime * 1000
        ]))
    }
    
    // MARK: - Visibility Testing
    
    private func isObjectVisible(_ object: CullableObject) -> Bool {
        guard cullingMode != .disabled else { return true }
        
        // Distance culling
        let distance = simd_distance(object.worldPosition, getCameraPosition())
        if distance > cullingMode.cullingDistance {
            return false
        }
        
        // Frustum culling
        if !isInFrustum(object.boundingBox, at: object.worldPosition) {
            return false
        }
        
        // Occlusion culling (if enabled)
        if cullingMode.occlusionCullingEnabled {
            if isOccluded(object) {
                return false
            }
        }
        
        // Temporal coherence - objects visible in recent frames are likely still visible
        if let visibilityInfo = visibilityCache[object.objectIdentifier],
           visibilityInfo.framesSinceVisible < 3 {
            return true
        }
        
        return true
    }
    
    private func isInFrustum(_ boundingBox: BoundingBox, at position: simd_float3) -> Bool {
        let worldBounds = transformBoundingBox(boundingBox, to: position)
        
        // Test against all 6 frustum planes
        for plane in frustumPlanes {
            let planeNormal = simd_float3(plane.x, plane.y, plane.z)
            let planeDistance = plane.w
            
            // Get the positive vertex (farthest point in the direction of the plane normal)
            let positiveVertex = simd_float3(
                planeNormal.x >= 0 ? worldBounds.max.x : worldBounds.min.x,
                planeNormal.y >= 0 ? worldBounds.max.y : worldBounds.min.y,
                planeNormal.z >= 0 ? worldBounds.max.z : worldBounds.min.z
            )
            
            // If the positive vertex is behind the plane, the box is completely outside
            if simd_dot(planeNormal, positiveVertex) + planeDistance < 0 {
                return false
            }
        }
        
        return true
    }
    
    private func isOccluded(_ object: CullableObject) -> Bool {
        // Simple occlusion test using spatial grid
        let cameraPos = getCameraPosition()
        let objectPos = object.worldPosition
        let direction = simd_normalize(objectPos - cameraPos)
        let distance = simd_distance(cameraPos, objectPos)
        
        // Ray march from camera to object
        let stepSize: Float = 1.0
        let steps = Int(distance / stepSize)
        
        for i in 1..<steps {
            let testPoint = cameraPos + direction * (Float(i) * stepSize)
            
            // Check for occluding objects at this point
            let nearbyObjects = spatialGrid.query(around: testPoint, radius: 2.0)
            
            for nearbyObject in nearbyObjects {
                if nearbyObject.identifier != object.identifier &&
                   nearbyObject.isOpaque &&
                   isPointInBounds(testPoint, bounds: nearbyObject.worldBoundingBox) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Spatial Queries
    
    private func getPotentiallyVisibleObjects() -> [CullableObject] {
        let cameraPos = getCameraPosition()
        let queryRadius = cullingMode.cullingDistance
        
        // Use spatial grid for initial filtering
        let nearbyObjects = spatialGrid.query(around: cameraPos, radius: queryRadius)
        
        // Further filter using octree for hierarchical culling
        let frustumBounds = calculateFrustumBounds()
        let octreeObjects = octree.query(in: frustumBounds)
        
        // Combine results and deduplicate
        let combined = Set(nearbyObjects.map { $0.identifier })
            .union(Set(octreeObjects.map { $0.identifier }))
        
        return trackedObjects.values.filter { combined.contains($0.identifier) }
    }
    
    // MARK: - Culling Application
    
    private func applyCullingResult(_ object: CullableObject, isVisible: Bool) {
        // Apply to SceneKit node
        if let scnNode = object.scnNode {
            scnNode.isHidden = !isVisible
            
            // Additional optimizations for invisible objects
            if !isVisible {
                // Disable physics for invisible objects
                scnNode.physicsBody?.type = .static
                
                // Disable animations
                scnNode.removeAllAnimations()
            }
        }
        
        // Apply to RealityKit entity
        if let entity = object.realityKitEntity {
            entity.isEnabled = isVisible
            
            // Additional optimizations
            if !isVisible {
                // Remove temporary components
                entity.components.set(OpacityComponent(opacity: 0.0))
            } else {
                entity.components.set(OpacityComponent(opacity: 1.0))
            }
        }
    }
    
    // MARK: - Frustum Calculation
    
    private func extractFrustumPlanes() {
        let viewProj = projectionMatrix * viewMatrix
        
        // Extract the 6 frustum planes from the combined matrix
        // Left plane
        frustumPlanes[0] = normalizePlane(simd_float4(
            viewProj[0][3] + viewProj[0][0],
            viewProj[1][3] + viewProj[1][0],
            viewProj[2][3] + viewProj[2][0],
            viewProj[3][3] + viewProj[3][0]
        ))
        
        // Right plane
        frustumPlanes[1] = normalizePlane(simd_float4(
            viewProj[0][3] - viewProj[0][0],
            viewProj[1][3] - viewProj[1][0],
            viewProj[2][3] - viewProj[2][0],
            viewProj[3][3] - viewProj[3][0]
        ))
        
        // Bottom plane
        frustumPlanes[2] = normalizePlane(simd_float4(
            viewProj[0][3] + viewProj[0][1],
            viewProj[1][3] + viewProj[1][1],
            viewProj[2][3] + viewProj[2][1],
            viewProj[3][3] + viewProj[3][1]
        ))
        
        // Top plane
        frustumPlanes[3] = normalizePlane(simd_float4(
            viewProj[0][3] - viewProj[0][1],
            viewProj[1][3] - viewProj[1][1],
            viewProj[2][3] - viewProj[2][1],
            viewProj[3][3] - viewProj[3][1]
        ))
        
        // Near plane
        frustumPlanes[4] = normalizePlane(simd_float4(
            viewProj[0][3] + viewProj[0][2],
            viewProj[1][3] + viewProj[1][2],
            viewProj[2][3] + viewProj[2][2],
            viewProj[3][3] + viewProj[3][2]
        ))
        
        // Far plane
        frustumPlanes[5] = normalizePlane(simd_float4(
            viewProj[0][3] - viewProj[0][2],
            viewProj[1][3] - viewProj[1][2],
            viewProj[2][3] - viewProj[2][2],
            viewProj[3][3] - viewProj[3][2]
        ))
    }
    
    private func normalizePlane(_ plane: simd_float4) -> simd_float4 {
        let normal = simd_float3(plane.x, plane.y, plane.z)
        let length = simd_length(normal)
        return plane / length
    }
    
    private func calculateFrustumBounds() -> BoundingBox {
        // Calculate approximate bounding box that encompasses the view frustum
        let cameraPos = getCameraPosition()
        let distance = cullingMode.cullingDistance
        
        return BoundingBox(
            min: cameraPos - simd_float3(distance, distance, distance),
            max: cameraPos + simd_float3(distance, distance, distance)
        )
    }
    
    // MARK: - Utility Methods
    
    private func getCameraPosition() -> simd_float3 {
        return simd_float3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
    }
    
    private func calculateBoundingBox(for node: SCNNode) -> BoundingBox {
        let (min, max) = node.boundingBox
        return BoundingBox(
            min: simd_float3(min.x, min.y, min.z),
            max: simd_float3(max.x, max.y, max.z)
        )
    }
    
    private func calculateBoundingBox(for entity: Entity) -> BoundingBox {
        let bounds = entity.visualBounds(relativeTo: nil)
        return BoundingBox(
            min: simd_float3(bounds.min.x, bounds.min.y, bounds.min.z),
            max: simd_float3(bounds.max.x, bounds.max.y, bounds.max.z)
        )
    }
    
    private func transformBoundingBox(_ boundingBox: BoundingBox, to position: simd_float3) -> BoundingBox {
        return BoundingBox(
            min: boundingBox.min + position,
            max: boundingBox.max + position
        )
    }
    
    private func isPointInBounds(_ point: simd_float3, bounds: BoundingBox) -> Bool {
        return point.x >= bounds.min.x && point.x <= bounds.max.x &&
               point.y >= bounds.min.y && point.y <= bounds.max.y &&
               point.z >= bounds.min.z && point.z <= bounds.max.z
    }
    
    private func createProjectionMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let f = 1.0 / tan(fov * 0.5)
        let rangeInv = 1.0 / (near - far)
        
        return simd_float4x4(
            simd_float4(f / aspect, 0, 0, 0),
            simd_float4(0, f, 0, 0),
            simd_float4(0, 0, (near + far) * rangeInv, -1),
            simd_float4(0, 0, near * far * rangeInv * 2, 0)
        )
    }
    
    private func updateCullingStats() {
        cullingStats.lastUpdateTime = Date()
        cullingStats.cullingTime = lastCullingTime
    }
    
    // MARK: - Public Interface
    
    public func setCullingMode(_ mode: CullingMode) {
        cullingMode = mode
        
        logInfo("Culling mode changed", category: .performance, context: LogContext(customData: [
            "mode": String(describing: mode)
        ]))
    }
    
    public func setCullingFrequency(_ frequency: TimeInterval) {
        cullingFrequency = frequency
        
        // Restart culling task with new frequency
        cullingTask?.cancel()
        startContinuousCulling()
    }
    
    public func forceUpdate() {
        Task {
            await performCullingPass()
        }
    }
    
    public func getCullingStatistics() -> [String: Any] {
        return [
            "processed_objects": processedObjects,
            "visible_objects": visibleObjects,
            "culled_objects": processedObjects - visibleObjects,
            "culling_time_ms": lastCullingTime * 1000,
            "tracked_objects": trackedObjects.count,
            "culling_mode": String(describing: cullingMode),
            "is_enabled": isEnabled
        ]
    }
    
    public func getDetailedStats() -> CullingDetailedStats {
        return CullingDetailedStats(
            totalTracked: trackedObjects.count,
            processedThisFrame: processedObjects,
            visibleThisFrame: visibleObjects,
            culledThisFrame: processedObjects - visibleObjects,
            averageCullingTime: lastCullingTime,
            spatialGridCells: spatialGrid.activeCells,
            octreeNodes: octree.nodeCount,
            cacheHitRate: calculateCacheHitRate()
        )
    }
    
    private func calculateCacheHitRate() -> Double {
        guard !visibilityCache.isEmpty else { return 0.0 }
        
        let recentEntries = visibilityCache.values.filter {
            Date().timeIntervalSince($0.lastChecked) < 1.0
        }
        
        return Double(recentEntries.count) / Double(visibilityCache.count)
    }
    
    deinit {
        cullingTask?.cancel()
        logDebug("Frustum culling system deinitialized", category: .performance)
    }
}

// MARK: - Supporting Data Structures

public struct BoundingBox {
    public let min: simd_float3
    public let max: simd_float3
    
    public var center: simd_float3 {
        return (min + max) * 0.5
    }
    
    public var size: simd_float3 {
        return max - min
    }
}

public class CullableObject {
    public let identifier: String
    public let objectIdentifier: ObjectIdentifier
    public weak var scnNode: SCNNode?
    public weak var realityKitEntity: Entity?
    public let boundingBox: BoundingBox
    public var lastVisibilityCheck: Date
    public var isOpaque: Bool = true
    
    public var worldPosition: simd_float3 {
        if let node = scnNode {
            let pos = node.worldPosition
            return simd_float3(pos.x, pos.y, pos.z)
        } else if let entity = realityKitEntity {
            let pos = entity.position(relativeTo: nil)
            return pos
        }
        return simd_float3(0, 0, 0)
    }
    
    public var worldBoundingBox: BoundingBox {
        let position = worldPosition
        return BoundingBox(
            min: boundingBox.min + position,
            max: boundingBox.max + position
        )
    }
    
    init(identifier: String, scnNode: SCNNode, boundingBox: BoundingBox, lastVisibilityCheck: Date) {
        self.identifier = identifier
        self.objectIdentifier = ObjectIdentifier(scnNode)
        self.scnNode = scnNode
        self.realityKitEntity = nil
        self.boundingBox = boundingBox
        self.lastVisibilityCheck = lastVisibilityCheck
    }
    
    init(identifier: String, realityKitEntity: Entity, boundingBox: BoundingBox, lastVisibilityCheck: Date) {
        self.identifier = identifier
        self.objectIdentifier = ObjectIdentifier(realityKitEntity)
        self.scnNode = nil
        self.realityKitEntity = realityKitEntity
        self.boundingBox = boundingBox
        self.lastVisibilityCheck = lastVisibilityCheck
    }
}

public struct VisibilityInfo {
    public let isVisible: Bool
    public let lastChecked: Date
    public let framesSinceVisible: Int
}

public class CullingStatistics: ObservableObject {
    @Published public var totalProcessed: Int = 0
    @Published public var totalVisible: Int = 0
    @Published public var totalCulled: Int = 0
    @Published public var cullingTime: TimeInterval = 0
    @Published public var lastUpdateTime: Date = Date()
    
    public func updateStats(processed: Int, visible: Int, culled: Int) {
        totalProcessed = processed
        totalVisible = visible
        totalCulled = culled
        lastUpdateTime = Date()
    }
}

public struct CullingDetailedStats {
    public let totalTracked: Int
    public let processedThisFrame: Int
    public let visibleThisFrame: Int
    public let culledThisFrame: Int
    public let averageCullingTime: TimeInterval
    public let spatialGridCells: Int
    public let octreeNodes: Int
    public let cacheHitRate: Double
}

// MARK: - Spatial Data Structures

public class SpatialGrid<T: AnyObject> {
    private var cells: [GridCoordinate: [T]] = [:]
    private let cellSize: Float
    
    public var activeCells: Int { cells.count }
    
    public init(cellSize: Float) {
        self.cellSize = cellSize
    }
    
    public func insert(_ object: T, at position: simd_float3) {
        let coord = getGridCoordinate(for: position)
        
        if cells[coord] == nil {
            cells[coord] = []
        }
        
        cells[coord]?.append(object)
    }
    
    public func remove(_ object: T, from position: simd_float3) {
        let coord = getGridCoordinate(for: position)
        
        cells[coord]?.removeAll { ObjectIdentifier($0) == ObjectIdentifier(object) }
        
        if cells[coord]?.isEmpty == true {
            cells.removeValue(forKey: coord)
        }
    }
    
    public func query(around position: simd_float3, radius: Float) -> [T] {
        var results: [T] = []
        let cellRadius = Int(ceil(radius / cellSize))
        let centerCoord = getGridCoordinate(for: position)
        
        for x in (centerCoord.x - cellRadius)...(centerCoord.x + cellRadius) {
            for y in (centerCoord.y - cellRadius)...(centerCoord.y + cellRadius) {
                for z in (centerCoord.z - cellRadius)...(centerCoord.z + cellRadius) {
                    let coord = GridCoordinate(x: x, y: y, z: z)
                    if let cellObjects = cells[coord] {
                        results.append(contentsOf: cellObjects)
                    }
                }
            }
        }
        
        return results
    }
    
    private func getGridCoordinate(for position: simd_float3) -> GridCoordinate {
        return GridCoordinate(
            x: Int(floor(position.x / cellSize)),
            y: Int(floor(position.y / cellSize)),
            z: Int(floor(position.z / cellSize))
        )
    }
}

public struct GridCoordinate: Hashable {
    public let x: Int
    public let y: Int
    public let z: Int
}

public class Octree<T: AnyObject> {
    private var root: OctreeNode<T>
    
    public var nodeCount: Int { root.nodeCount }
    
    public init(center: simd_float3, halfSize: Float, maxDepth: Int) {
        self.root = OctreeNode<T>(center: center, halfSize: halfSize, maxDepth: maxDepth)
    }
    
    public func insert(_ object: T, at position: simd_float3) {
        root.insert(object, at: position)
    }
    
    public func remove(_ object: T, from position: simd_float3) {
        root.remove(object, from: position)
    }
    
    public func query(in bounds: BoundingBox) -> [T] {
        return root.query(in: bounds)
    }
}

public class OctreeNode<T: AnyObject> {
    private let center: simd_float3
    private let halfSize: Float
    private let maxDepth: Int
    private let depth: Int
    
    private var objects: [T] = []
    private var children: [OctreeNode<T>] = []
    
    private let maxObjectsPerNode = 10
    
    public var nodeCount: Int {
        return 1 + children.reduce(0) { $0 + $1.nodeCount }
    }
    
    public init(center: simd_float3, halfSize: Float, maxDepth: Int, depth: Int = 0) {
        self.center = center
        self.halfSize = halfSize
        self.maxDepth = maxDepth
        self.depth = depth
    }
    
    public func insert(_ object: T, at position: simd_float3) {
        if !contains(position) { return }
        
        if children.isEmpty && (objects.count < maxObjectsPerNode || depth >= maxDepth) {
            objects.append(object)
        } else {
            if children.isEmpty {
                subdivide()
            }
            
            for child in children {
                child.insert(object, at: position)
            }
        }
    }
    
    public func remove(_ object: T, from position: simd_float3) {
        if !contains(position) { return }
        
        objects.removeAll { ObjectIdentifier($0) == ObjectIdentifier(object) }
        
        for child in children {
            child.remove(object, from: position)
        }
    }
    
    public func query(in bounds: BoundingBox) -> [T] {
        if !intersects(bounds) { return [] }
        
        var results = objects
        
        for child in children {
            results.append(contentsOf: child.query(in: bounds))
        }
        
        return results
    }
    
    private func contains(_ position: simd_float3) -> Bool {
        return position.x >= center.x - halfSize && position.x <= center.x + halfSize &&
               position.y >= center.y - halfSize && position.y <= center.y + halfSize &&
               position.z >= center.z - halfSize && position.z <= center.z + halfSize
    }
    
    private func intersects(_ bounds: BoundingBox) -> Bool {
        let nodeMin = center - simd_float3(halfSize, halfSize, halfSize)
        let nodeMax = center + simd_float3(halfSize, halfSize, halfSize)
        
        return nodeMin.x <= bounds.max.x && nodeMax.x >= bounds.min.x &&
               nodeMin.y <= bounds.max.y && nodeMax.y >= bounds.min.y &&
               nodeMin.z <= bounds.max.z && nodeMax.z >= bounds.min.z
    }
    
    private func subdivide() {
        let quarterSize = halfSize * 0.5
        
        children = [
            OctreeNode(center: center + simd_float3(-quarterSize, -quarterSize, -quarterSize), halfSize: quarterSize, maxDepth: maxDepth, depth: depth + 1),
            OctreeNode(center: center + simd_float3(quarterSize, -quarterSize, -quarterSize), halfSize: quarterSize, maxDepth: maxDepth, depth: depth + 1),
            OctreeNode(center: center + simd_float3(-quarterSize, quarterSize, -quarterSize), halfSize: quarterSize, maxDepth: maxDepth, depth: depth + 1),
            OctreeNode(center: center + simd_float3(quarterSize, quarterSize, -quarterSize), halfSize: quarterSize, maxDepth: maxDepth, depth: depth + 1),
            OctreeNode(center: center + simd_float3(-quarterSize, -quarterSize, quarterSize), halfSize: quarterSize, maxDepth: maxDepth, depth: depth + 1),
            OctreeNode(center: center + simd_float3(quarterSize, -quarterSize, quarterSize), halfSize: quarterSize, maxDepth: maxDepth, depth: depth + 1),
            OctreeNode(center: center + simd_float3(-quarterSize, quarterSize, quarterSize), halfSize: quarterSize, maxDepth: maxDepth, depth: depth + 1),
            OctreeNode(center: center + simd_float3(quarterSize, quarterSize, quarterSize), halfSize: quarterSize, maxDepth: maxDepth, depth: depth + 1)
        ]
    }
}