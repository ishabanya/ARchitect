import Foundation
import RealityKit
import ARKit
import simd

// MARK: - Occlusion Manager

@MainActor
public class OcclusionManager: ObservableObject {
    
    // MARK: - Properties
    private var arView: ARView?
    private var occludingEntities: [UUID: OccludingEntity] = [:]
    private var occludedEntities: [UUID: OccludedEntity] = [:]
    
    // Occlusion detection
    private var depthBuffer: CVPixelBuffer?
    private var occlusionQueries: [OcclusionQuery] = []
    private var lastUpdateTime: TimeInterval = 0
    
    // Performance settings
    private let updateInterval: TimeInterval = 1.0/30.0 // 30 FPS for occlusion updates
    private let maxOcclusionQueries = 50
    private let occlusionThreshold: Float = 0.8 // 80% occluded = hidden
    
    // Statistics
    private var occlusionUpdates: Int = 0
    private var hiddenObjects: Int = 0
    private var frameTime: TimeInterval = 0
    
    public init() {
        logDebug("Occlusion manager initialized", category: .general)
    }
    
    // MARK: - Initialization
    
    public func initialize(with arView: ARView) async {
        self.arView = arView
        
        // Enable occlusion in RealityKit
        setupRealityKitOcclusion(arView)
        
        // Start occlusion update loop
        startOcclusionUpdates()
        
        logInfo("Occlusion manager initialized with AR view", category: .general)
    }
    
    private func setupRealityKitOcclusion(_ arView: ARView) {
        // Enable depth-based occlusion
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        
        // Setup environment for better occlusion
        arView.environment.lighting.intensityExponent = 1.0
        arView.environment.background = .color(.clear)
        
        logDebug("RealityKit occlusion configured", category: .general)
    }
    
    private func startOcclusionUpdates() {
        Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateOcclusion()
            }
        }
    }
    
    // MARK: - Entity Management
    
    public func addOccludingEntity(_ entity: Entity, geometry: OccludingGeometry) {
        let occludingEntity = OccludingEntity(
            id: entity.id,
            entity: entity,
            geometry: geometry,
            bounds: entity.visualBounds(relativeTo: nil)
        )
        
        occludingEntities[entity.id] = occludingEntity
        
        // Add occlusion component to RealityKit entity
        entity.components.set(OcclusionComponent())
        
        logDebug("Added occluding entity", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString,
            "geometry_type": geometry.type.rawValue
        ]))
    }
    
    public func removeOccludingEntity(_ entityID: UUID) {
        if let entity = occludingEntities[entityID] {
            // Remove occlusion component
            entity.entity.components.remove(OcclusionComponent.self)
            occludingEntities.removeValue(forKey: entityID)
        }
    }
    
    public func addOccludedEntity(_ entity: Entity, priority: OcclusionPriority = .normal) {
        let occludedEntity = OccludedEntity(
            id: entity.id,
            entity: entity,
            priority: priority,
            bounds: entity.visualBounds(relativeTo: nil),
            isOccluded: false,
            occlusionAmount: 0.0
        )
        
        occludedEntities[entity.id] = occludedEntity
        
        logDebug("Added occluded entity", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString,
            "priority": priority.rawValue
        ]))
    }
    
    public func removeOccludedEntity(_ entityID: UUID) {
        occludedEntities.removeValue(forKey: entityID)
    }
    
    // MARK: - Occlusion Updates
    
    public func updateOcclusion() async {
        let startTime = CACurrentMediaTime()
        
        guard let arView = arView else { return }
        
        // Get current frame
        guard let frame = arView.session.currentFrame else { return }
        
        // Update depth buffer
        await updateDepthBuffer(frame)
        
        // Perform occlusion queries
        await performOcclusionQueries()
        
        // Update entity visibility
        await updateEntityVisibility()
        
        // Update statistics
        occlusionUpdates += 1
        frameTime = CACurrentMediaTime() - startTime
        lastUpdateTime = startTime
        
        if occlusionUpdates % 300 == 0 { // Log every 10 seconds at 30fps
            logDebug("Occlusion update completed", category: .general, context: LogContext(customData: [
                "frame_time": frameTime * 1000,
                "hidden_objects": hiddenObjects,
                "total_entities": occludedEntities.count
            ]))
        }
    }
    
    private func updateDepthBuffer(_ frame: ARFrame) async {
        // Get depth data from ARFrame
        if let depthData = frame.sceneDepth?.depthMap {
            depthBuffer = depthData
        } else if let depthData = frame.smoothedSceneDepth?.depthMap {
            depthBuffer = depthData
        }
    }
    
    private func performOcclusionQueries() async {
        guard let arView = arView,
              let camera = arView.session.currentFrame?.camera else { return }
        
        occlusionQueries.removeAll()
        
        // Create occlusion queries for entities
        var queryCount = 0
        
        for entity in occludedEntities.values {
            guard queryCount < maxOcclusionQueries else { break }
            
            let query = createOcclusionQuery(entity: entity, camera: camera)
            occlusionQueries.append(query)
            queryCount += 1
        }
        
        // Process queries
        for query in occlusionQueries {
            await processOcclusionQuery(query)
        }
    }
    
    private func createOcclusionQuery(entity: OccludedEntity, camera: ARCamera) -> OcclusionQuery {
        let worldPosition = entity.entity.position(relativeTo: nil)
        let bounds = entity.bounds
        
        // Project entity bounds to screen space
        let screenBounds = projectBoundsToScreen(bounds: bounds, worldPosition: worldPosition, camera: camera)
        
        return OcclusionQuery(
            entityID: entity.id,
            worldBounds: bounds,
            screenBounds: screenBounds,
            worldPosition: worldPosition,
            priority: entity.priority
        )
    }
    
    private func processOcclusionQuery(_ query: OcclusionQuery) async {
        guard let depthBuffer = depthBuffer else { return }
        
        // Sample depth buffer at entity position
        let occlusionAmount = await calculateOcclusionAmount(query: query, depthBuffer: depthBuffer)
        
        // Update entity occlusion state
        if var entity = occludedEntities[query.entityID] {
            entity.occlusionAmount = occlusionAmount
            entity.isOccluded = occlusionAmount > occlusionThreshold
            occludedEntities[query.entityID] = entity
        }
    }
    
    private func calculateOcclusionAmount(query: OcclusionQuery, depthBuffer: CVPixelBuffer) async -> Float {
        // Lock pixel buffer
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return 0.0 }
        
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        
        // Sample points within screen bounds
        let sampleCount = 16 // 4x4 grid
        var occludedSamples = 0
        
        let bounds = query.screenBounds
        let stepX = bounds.width / 4.0
        let stepY = bounds.height / 4.0
        
        for x in 0..<4 {
            for y in 0..<4 {
                let sampleX = Int(bounds.minX + Float(x) * stepX)
                let sampleY = Int(bounds.minY + Float(y) * stepY)
                
                // Clamp to buffer bounds
                let clampedX = max(0, min(width - 1, sampleX))
                let clampedY = max(0, min(height - 1, sampleY))
                
                // Get depth value (assuming 32-bit float depth)
                let pixelAddress = baseAddress + clampedY * bytesPerRow + clampedX * 4
                let depthValue = pixelAddress.assumingMemoryBound(to: Float32.self).pointee
                
                // Compare with entity depth
                let entityDepth = simd_length(query.worldPosition) // Simplified depth calculation
                
                if depthValue < entityDepth - 0.1 { // 10cm threshold
                    occludedSamples += 1
                }
            }
        }
        
        return Float(occludedSamples) / Float(sampleCount)
    }
    
    private func updateEntityVisibility() async {
        var hiddenCount = 0
        
        for entity in occludedEntities.values {
            let shouldBeVisible = !entity.isOccluded || entity.priority == .alwaysVisible
            
            // Update entity visibility
            if entity.entity.isEnabled != shouldBeVisible {
                entity.entity.isEnabled = shouldBeVisible
                
                if !shouldBeVisible {
                    hiddenCount += 1
                }
                
                logDebug("Entity visibility changed", category: .general, context: LogContext(customData: [
                    "entity_id": entity.id.uuidString,
                    "visible": shouldBeVisible,
                    "occlusion_amount": entity.occlusionAmount
                ]))
            }
        }
        
        hiddenObjects = hiddenCount
    }
    
    // MARK: - Utility Functions
    
    private func projectBoundsToScreen(bounds: BoundingBox, worldPosition: SIMD3<Float>, camera: ARCamera) -> ScreenBounds {
        let viewMatrix = camera.viewMatrix(for: .portrait)
        let projectionMatrix = camera.projectionMatrix(for: .portrait, viewportSize: CGSize(width: 1920, height: 1440), zNear: 0.001, zFar: 1000)
        
        // Project 8 corners of bounding box
        let corners = [
            worldPosition + SIMD3<Float>(bounds.min.x, bounds.min.y, bounds.min.z),
            worldPosition + SIMD3<Float>(bounds.max.x, bounds.min.y, bounds.min.z),
            worldPosition + SIMD3<Float>(bounds.min.x, bounds.max.y, bounds.min.z),
            worldPosition + SIMD3<Float>(bounds.max.x, bounds.max.y, bounds.min.z),
            worldPosition + SIMD3<Float>(bounds.min.x, bounds.min.y, bounds.max.z),
            worldPosition + SIMD3<Float>(bounds.max.x, bounds.min.y, bounds.max.z),
            worldPosition + SIMD3<Float>(bounds.min.x, bounds.max.y, bounds.max.z),
            worldPosition + SIMD3<Float>(bounds.max.x, bounds.max.y, bounds.max.z)
        ]
        
        var screenPoints: [SIMD2<Float>] = []
        
        for corner in corners {
            let viewSpacePoint = viewMatrix * SIMD4<Float>(corner, 1.0)
            let clipSpacePoint = projectionMatrix * viewSpacePoint
            
            if clipSpacePoint.w > 0 {
                let ndcPoint = SIMD2<Float>(clipSpacePoint.x / clipSpacePoint.w, clipSpacePoint.y / clipSpacePoint.w)
                let screenPoint = SIMD2<Float>(
                    (ndcPoint.x + 1.0) * 0.5 * 1920, // Assuming 1920 width
                    (1.0 - ndcPoint.y) * 0.5 * 1440  // Assuming 1440 height
                )
                screenPoints.append(screenPoint)
            }
        }
        
        // Calculate screen bounds
        if screenPoints.isEmpty {
            return ScreenBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
        }
        
        let minX = screenPoints.map { $0.x }.min() ?? 0
        let maxX = screenPoints.map { $0.x }.max() ?? 0
        let minY = screenPoints.map { $0.y }.min() ?? 0
        let maxY = screenPoints.map { $0.y }.max() ?? 0
        
        return ScreenBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
    
    // MARK: - Manual Occlusion Testing
    
    public func testOcclusion(entity: Entity, against occluders: [Entity]) async -> Float {
        // Manual occlusion testing for specific cases
        let entityPosition = entity.position(relativeTo: nil)
        let entityBounds = entity.visualBounds(relativeTo: nil)
        
        var totalOcclusion: Float = 0.0
        
        for occluder in occluders {
            let occluderBounds = occluder.visualBounds(relativeTo: nil)
            let occluderPosition = occluder.position(relativeTo: nil)
            
            // Simple sphere-sphere occlusion test
            let distance = simd_distance(entityPosition, occluderPosition)
            let entityRadius = simd_length(entityBounds.extents) * 0.5
            let occluderRadius = simd_length(occluderBounds.extents) * 0.5
            
            if distance < occluderRadius + entityRadius {
                // Calculate occlusion amount based on overlap
                let overlap = (occluderRadius + entityRadius - distance) / (entityRadius * 2)
                totalOcclusion += max(0, min(1, overlap))
            }
        }
        
        return min(1.0, totalOcclusion)
    }
    
    // MARK: - Configuration
    
    public func setOcclusionEnabled(_ enabled: Bool) {
        guard let arView = arView else { return }
        
        if enabled {
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        } else {
            arView.environment.sceneUnderstanding.options.remove(.occlusion)
            
            // Make all entities visible
            for entity in occludedEntities.values {
                entity.entity.isEnabled = true
            }
        }
        
        logInfo("Occlusion \(enabled ? "enabled" : "disabled")", category: .general)
    }
    
    public func setOcclusionThreshold(_ threshold: Float) {
        // Update occlusion threshold (0.0 to 1.0)
        // This would update the internal threshold and re-evaluate visibility
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> OcclusionStatistics {
        return OcclusionStatistics(
            occlusionUpdates: occlusionUpdates,
            frameTime: frameTime,
            occludingEntities: occludingEntities.count,
            occludedEntities: occludedEntities.count,
            hiddenObjects: hiddenObjects,
            occlusionQueries: occlusionQueries.count
        )
    }
}

// MARK: - Supporting Types

public struct OccludingEntity {
    public let id: UUID
    public let entity: Entity
    public let geometry: OccludingGeometry
    public let bounds: BoundingBox
    
    public init(id: UUID, entity: Entity, geometry: OccludingGeometry, bounds: BoundingBox) {
        self.id = id
        self.entity = entity
        self.geometry = geometry
        self.bounds = bounds
    }
}

public struct OccludedEntity {
    public let id: UUID
    public let entity: Entity
    public let priority: OcclusionPriority
    public let bounds: BoundingBox
    public var isOccluded: Bool
    public var occlusionAmount: Float
    
    public init(id: UUID, entity: Entity, priority: OcclusionPriority, bounds: BoundingBox, isOccluded: Bool, occlusionAmount: Float) {
        self.id = id
        self.entity = entity
        self.priority = priority
        self.bounds = bounds
        self.isOccluded = isOccluded
        self.occlusionAmount = occlusionAmount
    }
}

public struct OccludingGeometry {
    public let type: GeometryType
    public let data: GeometryData
    
    public enum GeometryType: String {
        case plane = "plane"
        case box = "box"
        case sphere = "sphere"
        case mesh = "mesh"
    }
    
    public enum GeometryData {
        case plane(normal: SIMD3<Float>, size: SIMD2<Float>)
        case box(size: SIMD3<Float>)
        case sphere(radius: Float)
        case mesh(vertices: [SIMD3<Float>], indices: [UInt32])
    }
    
    public init(type: GeometryType, data: GeometryData) {
        self.type = type
        self.data = data
    }
}

public enum OcclusionPriority: String, CaseIterable {
    case low = "low"           // Hidden when 50% occluded
    case normal = "normal"     // Hidden when 80% occluded
    case high = "high"         // Hidden when 95% occluded
    case alwaysVisible = "always_visible" // Never hidden
}

public struct OcclusionQuery {
    public let entityID: UUID
    public let worldBounds: BoundingBox
    public let screenBounds: ScreenBounds
    public let worldPosition: SIMD3<Float>
    public let priority: OcclusionPriority
    
    public init(entityID: UUID, worldBounds: BoundingBox, screenBounds: ScreenBounds, worldPosition: SIMD3<Float>, priority: OcclusionPriority) {
        self.entityID = entityID
        self.worldBounds = worldBounds
        self.screenBounds = screenBounds
        self.worldPosition = worldPosition
        self.priority = priority
    }
}

public struct ScreenBounds {
    public let minX: Float
    public let minY: Float
    public let maxX: Float
    public let maxY: Float
    
    public var width: Float { maxX - minX }
    public var height: Float { maxY - minY }
    
    public init(minX: Float, minY: Float, maxX: Float, maxY: Float) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

public struct OcclusionStatistics {
    public let occlusionUpdates: Int
    public let frameTime: TimeInterval
    public let occludingEntities: Int
    public let occludedEntities: Int
    public let hiddenObjects: Int
    public let occlusionQueries: Int
    
    public init(occlusionUpdates: Int, frameTime: TimeInterval, occludingEntities: Int, occludedEntities: Int, hiddenObjects: Int, occlusionQueries: Int) {
        self.occlusionUpdates = occlusionUpdates
        self.frameTime = frameTime
        self.occludingEntities = occludingEntities
        self.occludedEntities = occludedEntities
        self.hiddenObjects = hiddenObjects
        self.occlusionQueries = occlusionQueries
    }
}