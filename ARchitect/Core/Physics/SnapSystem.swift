import Foundation
import simd
import RealityKit

// MARK: - Snap System

public class SnapSystem {
    
    // MARK: - Properties
    private let configuration: PhysicsSystem.PhysicsConfiguration
    private var snapTargets: [UUID: SnapTarget] = [:]
    private var snappableEntities: [UUID: PhysicsEntity] = [:]
    
    // Snap state tracking
    private var entitySnapStates: [UUID: SnapState] = [:]
    private var activeSnapOperations: [UUID: SnapOperation] = [:]
    
    // Performance tracking
    private var snapOperations: Int = 0
    private var successfulSnaps: Int = 0
    
    public init(configuration: PhysicsSystem.PhysicsConfiguration) {
        self.configuration = configuration
        
        logDebug("Snap system initialized", category: .general)
    }
    
    // MARK: - Entity Management
    
    public func addEntity(_ entity: PhysicsEntity) {
        snappableEntities[entity.id] = entity
        entitySnapStates[entity.id] = SnapState()
        
        logDebug("Added entity to snap system", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    public func removeEntity(_ entity: PhysicsEntity) {
        snappableEntities.removeValue(forKey: entity.id)
        entitySnapStates.removeValue(forKey: entity.id)
        activeSnapOperations.removeValue(forKey: entity.id)
        
        logDebug("Removed entity from snap system", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    public func addSnapTarget(_ target: SnapTarget) {
        snapTargets[target.id] = target
        
        logDebug("Added snap target", category: .general, context: LogContext(customData: [
            "target_id": target.id.uuidString,
            "target_type": target.type.rawValue
        ]))
    }
    
    public func updateSnapTarget(_ target: SnapTarget) {
        snapTargets[target.id] = target
    }
    
    public func removeSnapTarget(_ target: SnapTarget) {
        snapTargets.removeValue(forKey: target.id)
        
        // Remove any active snap operations using this target
        for (entityID, operation) in activeSnapOperations {
            if operation.targetID == target.id {
                activeSnapOperations.removeValue(forKey: entityID)
            }
        }
    }
    
    // MARK: - Snap Operations
    
    public func snapToSurface(_ entity: PhysicsEntity, type: SnapType) async -> SnapResult {
        snapOperations += 1
        
        guard let snapState = entitySnapStates[entity.id] else {
            return SnapResult(snapped: false, targetType: nil, snapPoint: nil)
        }
        
        // Find best snap target
        let candidates = findSnapCandidates(for: entity, type: type)
        
        guard let bestTarget = selectBestSnapTarget(for: entity, candidates: candidates) else {
            return SnapResult(snapped: false, targetType: nil, snapPoint: nil)
        }
        
        // Perform the snap
        let snapPoint = calculateSnapPoint(entity: entity, target: bestTarget)
        let snapSuccess = await performSnap(entity: entity, target: bestTarget, snapPoint: snapPoint)
        
        if snapSuccess {
            successfulSnaps += 1
            snapState.isSnapped = true
            snapState.snapTarget = bestTarget.id
            snapState.snapPoint = snapPoint
            snapState.snapTime = CACurrentMediaTime()
            
            logDebug("Entity snapped successfully", category: .general, context: LogContext(customData: [
                "entity_id": entity.id.uuidString,
                "target_id": bestTarget.id.uuidString,
                "target_type": bestTarget.type.rawValue,
                "snap_point": [snapPoint.x, snapPoint.y, snapPoint.z]
            ]))
        }
        
        return SnapResult(
            snapped: snapSuccess,
            targetType: bestTarget.type,
            snapPoint: snapSuccess ? snapPoint : nil
        )
    }
    
    public func updateSnapping() async {
        // Update automatic snapping for entities near snap targets
        for entity in snappableEntities.values {
            await updateEntitySnapping(entity)
        }
        
        // Update active snap operations
        await updateActiveSnapOperations()
    }
    
    private func updateEntitySnapping(_ entity: PhysicsEntity) async {
        guard let snapState = entitySnapStates[entity.id] else { return }
        
        // Check if entity should maintain snap
        if snapState.isSnapped {
            await maintainSnap(entity: entity, snapState: snapState)
        } else {
            // Check for automatic snapping
            await checkAutomaticSnap(entity: entity)
        }
    }
    
    private func maintainSnap(entity: PhysicsEntity, snapState: SnapState) async {
        guard let targetID = snapState.snapTarget,
              let target = snapTargets[targetID],
              let snapPoint = snapState.snapPoint else {
            // Lost snap target, unsnap
            snapState.isSnapped = false
            snapState.snapTarget = nil
            snapState.snapPoint = nil
            return
        }
        
        // Check if entity has moved too far from snap point
        let currentPosition = entity.physicsBody.position
        let distanceFromSnap = simd_distance(currentPosition, snapPoint)
        
        if distanceFromSnap > configuration.snapDistance * 2.0 {
            // Entity moved too far, break snap
            await breakSnap(entity: entity, snapState: snapState)
        } else {
            // Maintain snap position
            let snapForce = calculateSnapMaintainForce(
                currentPosition: currentPosition,
                snapPoint: snapPoint,
                target: target
            )
            
            if simd_length(snapForce) > 0.001 {
                entity.physicsBody.addForce(snapForce)
            }
        }
    }
    
    private func checkAutomaticSnap(entity: PhysicsEntity) async {
        // Only automatically snap if entity is moving slowly
        let speed = simd_length(entity.physicsBody.velocity)
        if speed > 1.0 { return } // Moving too fast for auto-snap
        
        let candidates = findSnapCandidates(for: entity, type: .automatic)
        
        for candidate in candidates {
            let distance = distanceToSnapTarget(entity: entity, target: candidate)
            
            if distance < configuration.snapDistance {
                // Entity is close enough for automatic snap
                let _ = await snapToSurface(entity, type: .automatic)
                break
            }
        }
    }
    
    private func breakSnap(entity: PhysicsEntity, snapState: SnapState) async {
        snapState.isSnapped = false
        snapState.snapTarget = nil
        snapState.snapPoint = nil
        
        logDebug("Snap broken", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    private func updateActiveSnapOperations() async {
        var completedOperations: [UUID] = []
        
        for (entityID, operation) in activeSnapOperations {
            if await updateSnapOperation(operation) {
                completedOperations.append(entityID)
            }
        }
        
        // Remove completed operations
        for entityID in completedOperations {
            activeSnapOperations.removeValue(forKey: entityID)
        }
    }
    
    private func updateSnapOperation(_ operation: SnapOperation) async -> Bool {
        // Check if snap operation is complete
        let elapsed = CACurrentMediaTime() - operation.startTime
        
        if elapsed > operation.duration {
            return true // Operation complete
        }
        
        // Update snap interpolation
        let progress = Float(elapsed / operation.duration)
        let smoothProgress = smoothStep(progress)
        
        guard let entity = snappableEntities[operation.entityID],
              let target = snapTargets[operation.targetID] else {
            return true // Entity or target no longer exists
        }
        
        let currentPosition = simd_mix(operation.startPosition, operation.targetPosition, smoothProgress)
        entity.physicsBody.position = currentPosition
        
        // Reduce velocity during snap
        entity.physicsBody.velocity *= (1.0 - smoothProgress * 0.5)
        
        return false // Operation ongoing
    }
    
    // MARK: - Snap Target Finding
    
    private func findSnapCandidates(for entity: PhysicsEntity, type: SnapType) -> [SnapTarget] {
        var candidates: [SnapTarget] = []
        
        for target in snapTargets.values {
            if shouldConsiderSnapTarget(entity: entity, target: target, snapType: type) {
                candidates.append(target)
            }
        }
        
        return candidates
    }
    
    private func shouldConsiderSnapTarget(entity: PhysicsEntity, target: SnapTarget, snapType: SnapType) -> Bool {
        // Check snap type compatibility
        switch snapType {
        case .floor:
            return target.type == .floor
        case .wall:
            return target.type == .wall
        case .surface:
            return target.type == .floor || target.type == .wall
        case .automatic:
            return true // Consider all targets for automatic snapping
        }
    }
    
    private func selectBestSnapTarget(for entity: PhysicsEntity, candidates: [SnapTarget]) -> SnapTarget? {
        guard !candidates.isEmpty else { return nil }
        
        var bestTarget: SnapTarget?
        var bestScore: Float = Float.greatestFiniteMagnitude
        
        for candidate in candidates {
            let score = calculateSnapScore(entity: entity, target: candidate)
            
            if score < bestScore {
                bestScore = score
                bestTarget = candidate
            }
        }
        
        return bestTarget
    }
    
    private func calculateSnapScore(entity: PhysicsEntity, target: SnapTarget) -> Float {
        let distance = distanceToSnapTarget(entity: entity, target: target)
        let alignment = calculateAlignment(entity: entity, target: target)
        
        // Lower score is better
        return distance * 2.0 + (1.0 - alignment) * 1.0
    }
    
    private func distanceToSnapTarget(entity: PhysicsEntity, target: SnapTarget) -> Float {
        let entityPosition = entity.physicsBody.position
        let targetPosition = getTargetPosition(target)
        
        switch target.type {
        case .floor:
            // Distance to floor plane
            return abs(entityPosition.y - targetPosition.y)
        case .wall:
            // Distance to wall plane
            let toWall = entityPosition - targetPosition
            return abs(simd_dot(toWall, target.normal))
        case .corner:
            // Direct distance to corner point
            return simd_distance(entityPosition, targetPosition)
        case .edge:
            // Distance to edge line
            return distanceToLine(point: entityPosition, lineStart: targetPosition, lineEnd: targetPosition + target.normal)
        }
    }
    
    private func calculateAlignment(entity: PhysicsEntity, target: SnapTarget) -> Float {
        // Calculate how well the entity aligns with the target
        // Returns 0.0 to 1.0, where 1.0 is perfect alignment
        
        let entityForward = getEntityForward(entity)
        
        switch target.type {
        case .floor:
            // Check if entity is upright
            let dot = simd_dot(entityForward, SIMD3<Float>(0, 1, 0))
            return abs(dot)
        case .wall:
            // Check alignment with wall normal
            let dot = simd_dot(entityForward, target.normal)
            return 1.0 - abs(dot) // Perpendicular is best
        case .corner, .edge:
            return 0.5 // Neutral alignment for corners and edges
        }
    }
    
    private func getEntityForward(_ entity: PhysicsEntity) -> SIMD3<Float> {
        let rotation = entity.physicsBody.orientation
        return simd_act(rotation, SIMD3<Float>(0, 0, -1)) // Assuming -Z is forward
    }
    
    private func getTargetPosition(_ target: SnapTarget) -> SIMD3<Float> {
        return SIMD3<Float>(
            target.transform.columns.3.x,
            target.transform.columns.3.y,
            target.transform.columns.3.z
        )
    }
    
    private func distanceToLine(point: SIMD3<Float>, lineStart: SIMD3<Float>, lineEnd: SIMD3<Float>) -> Float {
        let lineVector = lineEnd - lineStart
        let pointVector = point - lineStart
        
        let lineLength = simd_length(lineVector)
        if lineLength < 0.001 { return simd_distance(point, lineStart) }
        
        let normalizedLine = lineVector / lineLength
        let projection = simd_dot(pointVector, normalizedLine)
        let clampedProjection = max(0, min(lineLength, projection))
        
        let closestPoint = lineStart + normalizedLine * clampedProjection
        return simd_distance(point, closestPoint)
    }
    
    // MARK: - Snap Execution
    
    private func calculateSnapPoint(entity: PhysicsEntity, target: SnapTarget) -> SIMD3<Float> {
        let entityPosition = entity.physicsBody.position
        let targetPosition = getTargetPosition(target)
        
        switch target.type {
        case .floor:
            // Snap to floor surface
            let entityRadius = getBoundingRadius(entity)
            return SIMD3<Float>(entityPosition.x, targetPosition.y + entityRadius, entityPosition.z)
            
        case .wall:
            // Snap to wall surface
            let entityRadius = getBoundingRadius(entity)
            let offsetFromWall = target.normal * entityRadius
            return targetPosition + offsetFromWall
            
        case .corner:
            // Snap to corner point
            return targetPosition
            
        case .edge:
            // Snap to nearest point on edge
            let edgeEnd = targetPosition + target.normal // Simplified edge representation
            let closestPoint = closestPointOnLine(
                point: entityPosition,
                lineStart: targetPosition,
                lineEnd: edgeEnd
            )
            return closestPoint
        }
    }
    
    private func closestPointOnLine(point: SIMD3<Float>, lineStart: SIMD3<Float>, lineEnd: SIMD3<Float>) -> SIMD3<Float> {
        let lineVector = lineEnd - lineStart
        let pointVector = point - lineStart
        
        let lineLength = simd_length(lineVector)
        if lineLength < 0.001 { return lineStart }
        
        let normalizedLine = lineVector / lineLength
        let projection = simd_dot(pointVector, normalizedLine)
        let clampedProjection = max(0, min(lineLength, projection))
        
        return lineStart + normalizedLine * clampedProjection
    }
    
    private func performSnap(entity: PhysicsEntity, target: SnapTarget, snapPoint: SIMD3<Float>) async -> Bool {
        // Create smooth snap operation
        let snapOperation = SnapOperation(
            entityID: entity.id,
            targetID: target.id,
            startPosition: entity.physicsBody.position,
            targetPosition: snapPoint,
            startTime: CACurrentMediaTime(),
            duration: 0.3 // 300ms snap duration
        )
        
        activeSnapOperations[entity.id] = snapOperation
        
        // Apply snap orientation if needed
        if let snapOrientation = calculateSnapOrientation(entity: entity, target: target) {
            entity.physicsBody.orientation = snapOrientation
        }
        
        return true
    }
    
    private func calculateSnapOrientation(entity: PhysicsEntity, target: SnapTarget) -> simd_quatf? {
        switch target.type {
        case .wall:
            // Orient entity to face away from wall
            let wallNormal = target.normal
            let forward = -wallNormal // Face away from wall
            let up = SIMD3<Float>(0, 1, 0)
            
            // Create rotation matrix
            let right = simd_normalize(simd_cross(up, forward))
            let correctedUp = simd_cross(forward, right)
            
            let rotationMatrix = simd_float3x3(right, correctedUp, forward)
            return simd_quatf(rotationMatrix)
            
        case .floor:
            // Keep entity upright on floor
            return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // Identity rotation
            
        default:
            return nil // No orientation change
        }
    }
    
    private func calculateSnapMaintainForce(currentPosition: SIMD3<Float>, snapPoint: SIMD3<Float>, target: SnapTarget) -> SIMD3<Float> {
        let displacement = snapPoint - currentPosition
        let distance = simd_length(displacement)
        
        if distance < 0.001 { return SIMD3<Float>(0, 0, 0) }
        
        let direction = displacement / distance
        let springForce = direction * distance * 100.0 // Spring constant
        
        return springForce
    }
    
    private func getBoundingRadius(_ entity: PhysicsEntity) -> Float {
        // Simplified bounding radius calculation
        let bounds = entity.entity.visualBounds(relativeTo: nil)
        return simd_length(bounds.extents) * 0.5
    }
    
    private func smoothStep(_ t: Float) -> Float {
        return t * t * (3.0 - 2.0 * t)
    }
    
    // MARK: - Configuration Updates
    
    public func updateConfiguration(_ newConfiguration: PhysicsSystem.PhysicsConfiguration) {
        // Update snap system configuration
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> SnapStatistics {
        return SnapStatistics(
            snapOperations: snapOperations,
            successfulSnaps: successfulSnaps,
            activeSnaps: entitySnapStates.values.filter { $0.isSnapped }.count,
            snapTargets: snapTargets.count,
            activeOperations: activeSnapOperations.count
        )
    }
}

// MARK: - Supporting Types

public enum SnapType: String, CaseIterable {
    case floor = "floor"
    case wall = "wall"
    case surface = "surface"
    case automatic = "automatic"
}

public enum SnapTargetType: String, CaseIterable {
    case floor = "floor"
    case wall = "wall"
    case corner = "corner"
    case edge = "edge"
}

public struct SnapTarget {
    public let id: UUID
    public let transform: simd_float4x4
    public let type: SnapTargetType
    public let normal: SIMD3<Float>
    public let bounds: BoundingBox
    
    public init(id: UUID, transform: simd_float4x4, type: SnapTargetType, normal: SIMD3<Float>, bounds: BoundingBox) {
        self.id = id
        self.transform = transform
        self.type = type
        self.normal = normal
        self.bounds = bounds
    }
}

public struct SnapResult {
    public let snapped: Bool
    public let targetType: SnapTargetType?
    public let snapPoint: SIMD3<Float>?
    
    public init(snapped: Bool, targetType: SnapTargetType?, snapPoint: SIMD3<Float>?) {
        self.snapped = snapped
        self.targetType = targetType
        self.snapPoint = snapPoint
    }
}

public class SnapState {
    public var isSnapped: Bool = false
    public var snapTarget: UUID?
    public var snapPoint: SIMD3<Float>?
    public var snapTime: TimeInterval = 0
    
    public init() {}
}

public struct SnapOperation {
    public let entityID: UUID
    public let targetID: UUID
    public let startPosition: SIMD3<Float>
    public let targetPosition: SIMD3<Float>
    public let startTime: TimeInterval
    public let duration: TimeInterval
    
    public init(entityID: UUID, targetID: UUID, startPosition: SIMD3<Float>, targetPosition: SIMD3<Float>, startTime: TimeInterval, duration: TimeInterval) {
        self.entityID = entityID
        self.targetID = targetID
        self.startPosition = startPosition
        self.targetPosition = targetPosition
        self.startTime = startTime
        self.duration = duration
    }
}

public struct SnapStatistics {
    public let snapOperations: Int
    public let successfulSnaps: Int
    public let activeSnaps: Int
    public let snapTargets: Int
    public let activeOperations: Int
    
    public init(snapOperations: Int, successfulSnaps: Int, activeSnaps: Int, snapTargets: Int, activeOperations: Int) {
        self.snapOperations = snapOperations
        self.successfulSnaps = successfulSnaps
        self.activeSnaps = activeSnaps
        self.snapTargets = snapTargets
        self.activeOperations = activeOperations
    }
}