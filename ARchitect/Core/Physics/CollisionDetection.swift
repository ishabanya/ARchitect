import Foundation
import RealityKit
import simd

// MARK: - Collision Detector

public class CollisionDetector {
    
    // MARK: - Properties
    private let configuration: PhysicsSystem.PhysicsConfiguration
    private var physicsEntities: [UUID: PhysicsEntity] = [:]
    private var staticColliders: [UUID: StaticCollider] = [:]
    
    // Collision tracking
    private var currentCollisions: Set<CollisionPair> = []
    private var previousCollisions: Set<CollisionPair> = []
    
    // Performance optimization
    private var spatialGrid: SpatialGrid
    private var broadPhaseCollisions: [(PhysicsEntity, PhysicsEntity)] = []
    private var staticCollisionCache: [UUID: Set<UUID>] = [:]
    
    // Statistics
    private var collisionChecks: Int = 0
    private var lastFrameCollisionChecks: Int = 0
    
    public init(configuration: PhysicsSystem.PhysicsConfiguration) {
        self.configuration = configuration
        self.spatialGrid = SpatialGrid(cellSize: 1.0) // 1 meter cells
        
        logDebug("Collision detector initialized", category: .general)
    }
    
    // MARK: - Entity Management
    
    public func addEntity(_ entity: PhysicsEntity) {
        physicsEntities[entity.id] = entity
        spatialGrid.addEntity(entity)
        
        logDebug("Added entity to collision detector", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    public func removeEntity(_ entity: PhysicsEntity) {
        physicsEntities.removeValue(forKey: entity.id)
        spatialGrid.removeEntity(entity)
        staticCollisionCache.removeValue(forKey: entity.id)
        
        // Remove any collisions involving this entity
        currentCollisions = currentCollisions.filter { collision in
            collision.entityA != entity.id && collision.entityB != entity.id
        }
        
        logDebug("Removed entity from collision detector", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    public func addStaticCollider(_ collider: StaticCollider) {
        staticColliders[collider.id] = collider
        spatialGrid.addStaticCollider(collider)
        
        logDebug("Added static collider", category: .general, context: LogContext(customData: [
            "collider_id": collider.id.uuidString
        ]))
    }
    
    public func updateStaticCollider(_ collider: StaticCollider) {
        staticColliders[collider.id] = collider
        spatialGrid.updateStaticCollider(collider)
        
        // Clear cache for this collider
        for entityID in staticCollisionCache.keys {
            staticCollisionCache[entityID]?.remove(collider.id)
        }
    }
    
    public func removeStaticCollider(_ collider: StaticCollider) {
        staticColliders.removeValue(forKey: collider.id)
        spatialGrid.removeStaticCollider(collider)
        
        // Clear cache entries
        for entityID in staticCollisionCache.keys {
            staticCollisionCache[entityID]?.remove(collider.id)
        }
    }
    
    // MARK: - Collision Detection
    
    public func detectCollisions() async {
        collisionChecks = 0
        
        // Update spatial grid
        await updateSpatialGrid()
        
        // Broad phase: find potential collision pairs
        await broadPhaseDetection()
        
        // Narrow phase: detailed collision detection
        await narrowPhaseDetection()
        
        // Update collision states
        await updateCollisionStates()
        
        lastFrameCollisionChecks = collisionChecks
        
        if collisionChecks > 100 { // Log if doing too many checks
            logWarning("High collision check count: \(collisionChecks)", category: .general)
        }
    }
    
    private func updateSpatialGrid() async {
        for entity in physicsEntities.values {
            spatialGrid.updateEntity(entity)
        }
    }
    
    private func broadPhaseDetection() async {
        broadPhaseCollisions.removeAll()
        
        for entity in physicsEntities.values {
            guard entity.isActive && entity.isPhysicsEnabled else { continue }
            
            // Get potential collision candidates from spatial grid
            let candidates = spatialGrid.getPotentialCollisions(for: entity)
            
            for candidate in candidates {
                // Check if we should test this pair
                if shouldTestCollision(entity, candidate) {
                    broadPhaseCollisions.append((entity, candidate))
                }
            }
        }
    }
    
    private func narrowPhaseDetection() async {
        previousCollisions = currentCollisions
        currentCollisions.removeAll()
        
        // Entity-Entity collisions
        for (entityA, entityB) in broadPhaseCollisions {
            if let collision = await detectEntityCollision(entityA, entityB) {
                currentCollisions.insert(CollisionPair(entityA: entityA.id, entityB: entityB.id))
                await handleCollision(collision)
            }
            collisionChecks += 1
        }
        
        // Entity-Static collisions
        for entity in physicsEntities.values {
            guard entity.isActive && entity.isPhysicsEnabled else { continue }
            
            await detectStaticCollisions(entity)
        }
    }
    
    private func detectEntityCollision(_ entityA: PhysicsEntity, _ entityB: PhysicsEntity) async -> Collision? {
        // Simple sphere-sphere collision for now
        let radiusA = getBoundingRadius(entityA)
        let radiusB = getBoundingRadius(entityB)
        
        let distance = simd_distance(entityA.physicsBody.position, entityB.physicsBody.position)
        let combinedRadius = radiusA + radiusB + configuration.collisionMargin
        
        if distance < combinedRadius {
            let normal = simd_normalize(entityB.physicsBody.position - entityA.physicsBody.position)
            let penetration = combinedRadius - distance
            let contactPoint = entityA.physicsBody.position + normal * radiusA
            
            return Collision(
                entityA: entityA.id,
                entityB: entityB.id,
                contactPoint: contactPoint,
                normal: normal,
                penetration: penetration,
                type: .entityEntity
            )
        }
        
        return nil
    }
    
    private func detectStaticCollisions(_ entity: PhysicsEntity) async {
        let staticCandidates = spatialGrid.getStaticCollisions(for: entity)
        
        for collider in staticCandidates {
            if let collision = await detectStaticCollision(entity, collider) {
                await handleCollision(collision)
            }
            collisionChecks += 1
        }
    }
    
    private func detectStaticCollision(_ entity: PhysicsEntity, _ collider: StaticCollider) async -> Collision? {
        switch collider.geometry.type {
        case .plane:
            return await detectPlaneCollision(entity, collider)
        case .box:
            return await detectBoxCollision(entity, collider)
        case .mesh:
            return await detectMeshCollision(entity, collider)
        }
    }
    
    private func detectPlaneCollision(_ entity: PhysicsEntity, _ collider: StaticCollider) async -> Collision? {
        guard let planeGeometry = collider.geometry as? PlaneGeometry else { return nil }
        
        let planeNormal = planeGeometry.normal
        let planePoint = collider.getWorldPosition()
        
        let entityRadius = getBoundingRadius(entity)
        let entityPosition = entity.physicsBody.position
        
        // Distance from entity center to plane
        let distanceToPlane = simd_dot(entityPosition - planePoint, planeNormal)
        
        if distanceToPlane < entityRadius + configuration.collisionMargin {
            let penetration = entityRadius + configuration.collisionMargin - distanceToPlane
            let contactPoint = entityPosition - planeNormal * entityRadius
            
            return Collision(
                entityA: entity.id,
                entityB: collider.id,
                contactPoint: contactPoint,
                normal: planeNormal,
                penetration: penetration,
                type: .entityStatic
            )
        }
        
        return nil
    }
    
    private func detectBoxCollision(_ entity: PhysicsEntity, _ collider: StaticCollider) async -> Collision? {
        guard let boxGeometry = collider.geometry as? BoxGeometry else { return nil }
        
        // Simplified sphere-box collision
        let entityRadius = getBoundingRadius(entity)
        let entityPosition = entity.physicsBody.position
        let boxCenter = collider.getWorldPosition()
        let boxExtents = boxGeometry.size * 0.5
        
        // Find closest point on box to sphere center
        let localPoint = entityPosition - boxCenter
        let closestPoint = SIMD3<Float>(
            max(-boxExtents.x, min(boxExtents.x, localPoint.x)),
            max(-boxExtents.y, min(boxExtents.y, localPoint.y)),
            max(-boxExtents.z, min(boxExtents.z, localPoint.z))
        )
        
        let worldClosestPoint = boxCenter + closestPoint
        let distance = simd_distance(entityPosition, worldClosestPoint)
        
        if distance < entityRadius + configuration.collisionMargin {
            let normal = simd_normalize(entityPosition - worldClosestPoint)
            let penetration = entityRadius + configuration.collisionMargin - distance
            
            return Collision(
                entityA: entity.id,
                entityB: collider.id,
                contactPoint: worldClosestPoint,
                normal: normal,
                penetration: penetration,
                type: .entityStatic
            )
        }
        
        return nil
    }
    
    private func detectMeshCollision(_ entity: PhysicsEntity, _ collider: StaticCollider) async -> Collision? {
        // Simplified mesh collision using bounding box
        // In a full implementation, this would use GJK or SAT algorithms
        return await detectBoxCollision(entity, collider)
    }
    
    private func shouldTestCollision(_ entityA: PhysicsEntity, _ entityB: PhysicsEntity) -> Bool {
        // Check collision groups
        let groupA = entityA.properties.collisionGroup
        let groupB = entityB.properties.collisionGroup
        
        // Simple collision filtering
        if groupA == .none || groupB == .none {
            return false
        }
        
        // Check if collision groups should interact
        return (groupA.rawValue & groupB.rawValue) != 0
    }
    
    private func getBoundingRadius(_ entity: PhysicsEntity) -> Float {
        switch entity.physicsBody.geometry.type {
        case .sphere:
            if let sphereGeometry = entity.physicsBody.geometry as? SphereGeometry {
                return sphereGeometry.radius
            }
        case .box:
            if let boxGeometry = entity.physicsBody.geometry as? BoxGeometry {
                return simd_length(boxGeometry.size) * 0.5
            }
        case .mesh:
            // Use bounding sphere radius
            let bounds = entity.entity.visualBounds(relativeTo: nil)
            return simd_length(bounds.extents) * 0.5
        default:
            break
        }
        
        // Default radius
        return 0.5
    }
    
    private func updateCollisionStates() async {
        // Find new collisions
        let newCollisions = currentCollisions.subtracting(previousCollisions)
        
        // Find ended collisions
        let endedCollisions = previousCollisions.subtracting(currentCollisions)
        
        // Process collision events
        for collision in newCollisions {
            logDebug("New collision detected", category: .general, context: LogContext(customData: [
                "entity_a": collision.entityA.uuidString,
                "entity_b": collision.entityB.uuidString
            ]))
        }
        
        for collision in endedCollisions {
            logDebug("Collision ended", category: .general, context: LogContext(customData: [
                "entity_a": collision.entityA.uuidString,
                "entity_b": collision.entityB.uuidString
            ]))
        }
    }
    
    // MARK: - Collision Response
    
    private func handleCollision(_ collision: Collision) async {
        switch collision.type {
        case .entityEntity:
            await handleEntityEntityCollision(collision)
        case .entityStatic:
            await handleEntityStaticCollision(collision)
        }
    }
    
    private func handleEntityEntityCollision(_ collision: Collision) async {
        guard let entityA = physicsEntities[collision.entityA],
              let entityB = physicsEntities[collision.entityB] else { return }
        
        // Resolve penetration
        let totalMass = entityA.physicsBody.mass + entityB.physicsBody.mass
        let massRatioA = entityB.physicsBody.mass / totalMass
        let massRatioB = entityA.physicsBody.mass / totalMass
        
        let correction = collision.normal * collision.penetration * 0.8 // 80% correction
        
        entityA.physicsBody.position -= correction * massRatioA
        entityB.physicsBody.position += correction * massRatioB
        
        // Apply collision impulse
        let relativeVelocity = entityB.physicsBody.velocity - entityA.physicsBody.velocity
        let velocityAlongNormal = simd_dot(relativeVelocity, collision.normal)
        
        if velocityAlongNormal > 0 { return } // Objects separating
        
        let restitution = min(entityA.physicsBody.material.restitution, entityB.physicsBody.material.restitution)
        let impulseScalar = -(1 + restitution) * velocityAlongNormal / (1/entityA.physicsBody.mass + 1/entityB.physicsBody.mass)
        
        let impulse = collision.normal * impulseScalar
        
        entityA.physicsBody.velocity -= impulse / entityA.physicsBody.mass
        entityB.physicsBody.velocity += impulse / entityB.physicsBody.mass
    }
    
    private func handleEntityStaticCollision(_ collision: Collision) async {
        guard let entity = physicsEntities[collision.entityA] else { return }
        
        // Resolve penetration
        entity.physicsBody.position += collision.normal * collision.penetration
        
        // Apply collision impulse
        let velocityAlongNormal = simd_dot(entity.physicsBody.velocity, collision.normal)
        
        if velocityAlongNormal > 0 { return } // Object moving away from surface
        
        let restitution = entity.physicsBody.material.restitution
        let impulseScalar = -(1 + restitution) * velocityAlongNormal
        
        entity.physicsBody.velocity += collision.normal * impulseScalar
        
        // Apply friction
        let tangentVelocity = entity.physicsBody.velocity - collision.normal * velocityAlongNormal
        let frictionMagnitude = simd_length(tangentVelocity) * entity.physicsBody.material.friction
        
        if frictionMagnitude > 0 {
            let frictionDirection = simd_normalize(tangentVelocity)
            entity.physicsBody.velocity -= frictionDirection * min(frictionMagnitude, simd_length(tangentVelocity))
        }
    }
    
    // MARK: - Event Handlers
    
    public func handleCollisionBegan(_ event: CollisionEvents.Began) async {
        // Handle RealityKit collision events
        logDebug("RealityKit collision began", category: .general)
    }
    
    public func handleCollisionUpdated(_ event: CollisionEvents.Updated) async {
        // Handle ongoing collision
    }
    
    public func handleCollisionEnded(_ event: CollisionEvents.Ended) async {
        // Handle collision end
        logDebug("RealityKit collision ended", category: .general)
    }
    
    // MARK: - Configuration Updates
    
    public func updateConfiguration(_ newConfiguration: PhysicsSystem.PhysicsConfiguration) {
        // Update collision detector configuration
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> CollisionStatistics {
        return CollisionStatistics(
            collisionChecks: lastFrameCollisionChecks,
            activeCollisions: currentCollisions.count,
            staticColliders: staticColliders.count,
            spatialGridCells: spatialGrid.getActiveCellCount()
        )
    }
}

// MARK: - Supporting Types

public struct Collision {
    public let entityA: UUID
    public let entityB: UUID
    public let contactPoint: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let penetration: Float
    public let type: CollisionType
    
    public enum CollisionType {
        case entityEntity
        case entityStatic
    }
}

public struct CollisionPair: Hashable {
    public let entityA: UUID
    public let entityB: UUID
    
    public init(entityA: UUID, entityB: UUID) {
        // Ensure consistent ordering
        if entityA.uuidString < entityB.uuidString {
            self.entityA = entityA
            self.entityB = entityB
        } else {
            self.entityA = entityB
            self.entityB = entityA
        }
    }
}

public struct CollisionStatistics {
    public let collisionChecks: Int
    public let activeCollisions: Int
    public let staticColliders: Int
    public let spatialGridCells: Int
    
    public init(collisionChecks: Int, activeCollisions: Int, staticColliders: Int, spatialGridCells: Int) {
        self.collisionChecks = collisionChecks
        self.activeCollisions = activeCollisions
        self.staticColliders = staticColliders
        self.spatialGridCells = spatialGridCells
    }
}

// MARK: - Static Collider

public struct StaticCollider {
    public let id: UUID
    public let transform: simd_float4x4
    public let geometry: ColliderGeometry
    
    public init(id: UUID, transform: simd_float4x4, geometry: ColliderGeometry) {
        self.id = id
        self.transform = transform
        self.geometry = geometry
    }
    
    public func getWorldPosition() -> SIMD3<Float> {
        return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}