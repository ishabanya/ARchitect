import Foundation
import RealityKit
import simd

// MARK: - Physics World

public class PhysicsWorld {
    
    // MARK: - Properties
    public var gravity: SIMD3<Float>
    public var damping: Float
    public var sleepThreshold: Float
    
    private var entities: [UUID: PhysicsEntity] = [:]
    private var activeEntities: Set<UUID> = []
    private var sleepingEntities: Set<UUID> = []
    
    private let configuration: PhysicsSystem.PhysicsConfiguration
    private let integrator: PhysicsIntegrator
    
    // Performance tracking
    private var lastStepTime: TimeInterval = 0
    private var stepCount: Int = 0
    
    public init(configuration: PhysicsSystem.PhysicsConfiguration) {
        self.configuration = configuration
        self.gravity = configuration.gravity
        self.damping = configuration.damping
        self.sleepThreshold = configuration.sleepThreshold
        self.integrator = PhysicsIntegrator(configuration: configuration)
        
        logDebug("Physics world initialized", category: .general)
    }
    
    // MARK: - Entity Management
    
    public func addEntity(_ entity: PhysicsEntity) {
        entities[entity.id] = entity
        activeEntities.insert(entity.id)
        sleepingEntities.remove(entity.id)
        
        logDebug("Added entity to physics world", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString,
            "mass": entity.physicsBody.mass
        ]))
    }
    
    public func removeEntity(_ entity: PhysicsEntity) {
        entities.removeValue(forKey: entity.id)
        activeEntities.remove(entity.id)
        sleepingEntities.remove(entity.id)
        
        logDebug("Removed entity from physics world", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    public func getEntity(_ id: UUID) -> PhysicsEntity? {
        return entities[id]
    }
    
    public func getAllEntities() -> [PhysicsEntity] {
        return Array(entities.values)
    }
    
    // MARK: - Physics Simulation
    
    public func step(deltaTime: Float) async {
        let startTime = CACurrentMediaTime()
        
        // Apply gravity to all active entities
        await applyGravity(deltaTime: deltaTime)
        
        // Integrate forces and update positions
        await integrateMotion(deltaTime: deltaTime)
        
        // Apply damping
        await applyDamping()
        
        // Check for sleep state
        await updateSleepStates()
        
        // Update entity transforms
        await updateEntityTransforms()
        
        stepCount += 1
        lastStepTime = CACurrentMediaTime() - startTime
        
        if stepCount % 300 == 0 { // Log every 5 seconds at 60fps
            logDebug("Physics world step completed", category: .general, context: LogContext(customData: [
                "step_time": lastStepTime * 1000,
                "active_entities": activeEntities.count,
                "sleeping_entities": sleepingEntities.count
            ]))
        }
    }
    
    private func applyGravity(deltaTime: Float) async {
        for entityID in activeEntities {
            guard let entity = entities[entityID],
                  !entity.properties.isKinematic,
                  entity.physicsBody.mass > 0 else { continue }
            
            let gravityForce = gravity * entity.physicsBody.mass
            entity.physicsBody.addForce(gravityForce)
        }
    }
    
    private func integrateMotion(deltaTime: Float) async {
        for entityID in activeEntities {
            guard let entity = entities[entityID] else { continue }
            
            await integrator.integrate(entity: entity, deltaTime: deltaTime)
        }
    }
    
    private func applyDamping() async {
        for entityID in activeEntities {
            guard let entity = entities[entityID] else { continue }
            
            // Apply linear damping
            entity.physicsBody.velocity *= damping
            
            // Apply angular damping
            entity.physicsBody.angularVelocity *= damping
        }
    }
    
    private func updateSleepStates() async {
        for entityID in activeEntities {
            guard let entity = entities[entityID] else { continue }
            
            let speed = simd_length(entity.physicsBody.velocity)
            let angularSpeed = simd_length(entity.physicsBody.angularVelocity)
            
            if speed < sleepThreshold && angularSpeed < sleepThreshold {
                // Entity should sleep
                if !entity.isSleeping {
                    entity.sleepTimer += 1.0/60.0 // Assuming 60fps
                    
                    if entity.sleepTimer > 1.0 { // Sleep after 1 second of low activity
                        putEntityToSleep(entityID)
                    }
                }
            } else {
                // Entity should wake up
                if entity.isSleeping {
                    wakeUpEntity(entityID)
                }
                entity.sleepTimer = 0
            }
        }
    }
    
    private func putEntityToSleep(_ entityID: UUID) {
        guard let entity = entities[entityID] else { return }
        
        entity.isSleeping = true
        entity.physicsBody.velocity = SIMD3<Float>(0, 0, 0)
        entity.physicsBody.angularVelocity = SIMD3<Float>(0, 0, 0)
        
        activeEntities.remove(entityID)
        sleepingEntities.insert(entityID)
        
        logDebug("Entity put to sleep", category: .general, context: LogContext(customData: [
            "entity_id": entityID.uuidString
        ]))
    }
    
    private func wakeUpEntity(_ entityID: UUID) {
        guard let entity = entities[entityID] else { return }
        
        entity.isSleeping = false
        entity.sleepTimer = 0
        
        sleepingEntities.remove(entityID)
        activeEntities.insert(entityID)
        
        logDebug("Entity woken up", category: .general, context: LogContext(customData: [
            "entity_id": entityID.uuidString
        ]))
    }
    
    private func updateEntityTransforms() async {
        for entityID in activeEntities {
            guard let entity = entities[entityID] else { continue }
            
            // Update RealityKit entity transform
            let transform = Transform(
                translation: entity.physicsBody.position,
                rotation: entity.physicsBody.orientation
            )
            
            entity.entity.transform = transform
        }
    }
    
    // MARK: - Force Application
    
    public func applyForce(_ force: SIMD3<Float>, to entity: PhysicsEntity, at point: SIMD3<Float>? = nil) {
        // Wake up entity if sleeping
        if entity.isSleeping {
            wakeUpEntity(entity.id)
        }
        
        entity.physicsBody.addForce(force)
        
        // Apply torque if point is specified
        if let point = point {
            let centerOfMass = entity.physicsBody.position
            let arm = point - centerOfMass
            let torque = simd_cross(arm, force)
            entity.physicsBody.addTorque(torque)
        }
    }
    
    public func applyImpulse(_ impulse: SIMD3<Float>, to entity: PhysicsEntity, at point: SIMD3<Float>? = nil) {
        // Wake up entity if sleeping
        if entity.isSleeping {
            wakeUpEntity(entity.id)
        }
        
        entity.physicsBody.addImpulse(impulse)
        
        // Apply angular impulse if point is specified
        if let point = point {
            let centerOfMass = entity.physicsBody.position
            let arm = point - centerOfMass
            let angularImpulse = simd_cross(arm, impulse)
            entity.physicsBody.addAngularImpulse(angularImpulse)
        }
    }
    
    // MARK: - Configuration Updates
    
    public func updateConfiguration(_ newConfiguration: PhysicsSystem.PhysicsConfiguration) {
        gravity = newConfiguration.gravity
        damping = newConfiguration.damping
        sleepThreshold = newConfiguration.sleepThreshold
        
        integrator.updateConfiguration(newConfiguration)
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> PhysicsWorldStatistics {
        return PhysicsWorldStatistics(
            totalEntities: entities.count,
            activeEntities: activeEntities.count,
            sleepingEntities: sleepingEntities.count,
            lastStepTime: lastStepTime,
            stepCount: stepCount
        )
    }
}

// MARK: - Physics Integrator

public class PhysicsIntegrator {
    
    private let configuration: PhysicsSystem.PhysicsConfiguration
    
    public init(configuration: PhysicsSystem.PhysicsConfiguration) {
        self.configuration = configuration
    }
    
    public func integrate(entity: PhysicsEntity, deltaTime: Float) async {
        guard !entity.properties.isKinematic else { return }
        
        let body = entity.physicsBody
        
        // Velocity Verlet integration for linear motion
        let acceleration = body.force / body.mass
        
        // Update position
        body.position += body.velocity * deltaTime + 0.5 * acceleration * deltaTime * deltaTime
        
        // Update velocity
        body.velocity += acceleration * deltaTime
        
        // Clamp velocity to max
        let speed = simd_length(body.velocity)
        if speed > configuration.maxVelocity {
            body.velocity = simd_normalize(body.velocity) * configuration.maxVelocity
        }
        
        // Angular integration
        let angularAcceleration = body.torque / body.momentOfInertia
        
        // Update orientation (simplified)
        let angularDisplacement = body.angularVelocity * deltaTime + 0.5 * angularAcceleration * deltaTime * deltaTime
        let angularMagnitude = simd_length(angularDisplacement)
        
        if angularMagnitude > 0 {
            let axis = simd_normalize(angularDisplacement)
            let rotation = simd_quatf(angle: angularMagnitude, axis: axis)
            body.orientation = simd_normalize(body.orientation * rotation)
        }
        
        // Update angular velocity
        body.angularVelocity += angularAcceleration * deltaTime
        
        // Clear forces and torques for next frame
        body.clearForces()
    }
    
    public func updateConfiguration(_ newConfiguration: PhysicsSystem.PhysicsConfiguration) {
        // Update integrator configuration if needed
    }
}

// MARK: - Physics Entity

public class PhysicsEntity {
    public let id: UUID
    public let entity: Entity
    public let physicsBody: PhysicsBody
    public let properties: PhysicsProperties
    
    public var isActive: Bool = true
    public var isPhysicsEnabled: Bool = true
    public var isSleeping: Bool = false
    public var sleepTimer: Float = 0
    
    public init(id: UUID, entity: Entity, physicsBody: PhysicsBody, properties: PhysicsProperties) {
        self.id = id
        self.entity = entity
        self.physicsBody = physicsBody
        self.properties = properties
        
        // Initialize physics body position from entity
        let transform = entity.transform
        physicsBody.position = transform.translation
        physicsBody.orientation = transform.rotation
    }
}

// MARK: - Physics Body

public class PhysicsBody {
    public let mass: Float
    public let geometry: ColliderGeometry
    public let material: PhysicsMaterial
    
    // Motion state
    public var position: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    public var orientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    public var velocity: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    public var angularVelocity: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    // Forces and torques
    public var force: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    public var torque: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    // Computed properties
    public var momentOfInertia: Float {
        // Simplified moment of inertia calculation
        return mass * 0.4 // Rough approximation for a solid sphere
    }
    
    public init(mass: Float, geometry: ColliderGeometry, material: PhysicsMaterial) {
        self.mass = mass
        self.geometry = geometry
        self.material = material
    }
    
    public func addForce(_ force: SIMD3<Float>) {
        self.force += force
    }
    
    public func addTorque(_ torque: SIMD3<Float>) {
        self.torque += torque
    }
    
    public func addImpulse(_ impulse: SIMD3<Float>) {
        velocity += impulse / mass
    }
    
    public func addAngularImpulse(_ angularImpulse: SIMD3<Float>) {
        angularVelocity += angularImpulse / momentOfInertia
    }
    
    public func clearForces() {
        force = SIMD3<Float>(0, 0, 0)
        torque = SIMD3<Float>(0, 0, 0)
    }
}

// MARK: - Physics Material

public struct PhysicsMaterial {
    public let friction: Float
    public let restitution: Float
    public let density: Float
    
    public init(friction: Float = 0.7, restitution: Float = 0.3, density: Float = 1.0) {
        self.friction = friction
        self.restitution = restitution
        self.density = density
    }
}

// MARK: - Physics World Statistics

public struct PhysicsWorldStatistics {
    public let totalEntities: Int
    public let activeEntities: Int
    public let sleepingEntities: Int
    public let lastStepTime: TimeInterval
    public let stepCount: Int
    
    public init(totalEntities: Int, activeEntities: Int, sleepingEntities: Int, lastStepTime: TimeInterval, stepCount: Int) {
        self.totalEntities = totalEntities
        self.activeEntities = activeEntities
        self.sleepingEntities = sleepingEntities
        self.lastStepTime = lastStepTime
        self.stepCount = stepCount
    }
}