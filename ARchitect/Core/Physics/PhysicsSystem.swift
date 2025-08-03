import Foundation
import RealityKit
import ARKit
import simd
import Combine

// MARK: - Physics System

@MainActor
public class PhysicsSystem: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isEnabled = true
    @Published public var gravityEnabled = true
    @Published public var collisionDetectionEnabled = true
    @Published public var snapToFloorEnabled = true
    @Published public var snapToWallEnabled = true
    @Published public var shadowsEnabled = true
    @Published public var occlusionEnabled = true
    @Published public var performanceOptimized = true
    
    // MARK: - Physics Configuration
    public struct PhysicsConfiguration {
        public var gravity: SIMD3<Float> = SIMD3<Float>(0, -9.81, 0)
        public var collisionMargin: Float = 0.01 // 1cm
        public var snapDistance: Float = 0.05 // 5cm
        public var snapAngleTolerance: Float = 15.0 // degrees
        public var damping: Float = 0.98
        public var restitution: Float = 0.3
        public var friction: Float = 0.7
        public var maxVelocity: Float = 10.0
        public var sleepThreshold: Float = 0.01
        public var performanceBudget: TimeInterval = 0.008 // 8ms per frame
        
        public init() {}
    }
    
    // MARK: - Private Properties
    private var physicsWorld: PhysicsWorld
    private var collisionDetector: CollisionDetector
    private var snapSystem: SnapSystem
    private var shadowRenderer: ShadowRenderer
    private var occlusionManager: OcclusionManager
    private var performanceManager: PhysicsPerformanceManager
    
    private var anchorUpdates = Set<AnyCancellable>()
    private var entityUpdates = Set<AnyCancellable>()
    
    public var configuration = PhysicsConfiguration()
    
    // Tracked objects
    private var physicsEntities: [UUID: PhysicsEntity] = [:]
    private var staticColliders: [UUID: StaticCollider] = [:]
    private var snapTargets: [UUID: SnapTarget] = [:]
    
    // Performance tracking
    private var lastUpdateTime: TimeInterval = 0
    private var frameTime: TimeInterval = 0
    
    public init() {
        self.physicsWorld = PhysicsWorld(configuration: configuration)
        self.collisionDetector = CollisionDetector(configuration: configuration)
        self.snapSystem = SnapSystem(configuration: configuration)
        self.shadowRenderer = ShadowRenderer()
        self.occlusionManager = OcclusionManager()
        self.performanceManager = PhysicsPerformanceManager(configuration: configuration)
        
        setupPhysicsWorld()
        
        logInfo("Physics system initialized", category: .general)
    }
    
    deinit {
        anchorUpdates.removeAll()
        entityUpdates.removeAll()
        logInfo("Physics system deinitialized", category: .general)
    }
    
    // MARK: - Public Methods
    
    /// Initialize the physics system with AR session
    public func initialize(with arView: ARView) async {
        // Setup physics world in RealityKit
        await setupRealityKitPhysics(arView)
        
        // Initialize shadow rendering
        await shadowRenderer.initialize(with: arView)
        
        // Initialize occlusion
        await occlusionManager.initialize(with: arView)
        
        // Start physics simulation
        startSimulation(arView)
        
        logInfo("Physics system initialized with AR view", category: .general)
    }
    
    /// Add an entity to the physics simulation
    public func addEntity(_ entity: Entity, physicsProperties: PhysicsProperties) async throws {
        let physicsEntity = try await createPhysicsEntity(entity, properties: physicsProperties)
        
        physicsEntities[entity.id] = physicsEntity
        physicsWorld.addEntity(physicsEntity)
        
        // Add collision detection
        if collisionDetectionEnabled {
            collisionDetector.addEntity(physicsEntity)
        }
        
        // Add to snap system
        if physicsProperties.canSnap {
            snapSystem.addEntity(physicsEntity)
        }
        
        // Setup shadow casting
        if shadowsEnabled && physicsProperties.castsShadows {
            await shadowRenderer.addShadowCaster(physicsEntity)
        }
        
        logDebug("Added entity to physics simulation", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString,
            "mass": physicsProperties.mass,
            "can_snap": physicsProperties.canSnap
        ]))
    }
    
    /// Remove an entity from the physics simulation
    public func removeEntity(_ entityID: UUID) async {
        guard let physicsEntity = physicsEntities[entityID] else { return }
        
        // Remove from all systems
        physicsWorld.removeEntity(physicsEntity)
        collisionDetector.removeEntity(physicsEntity)
        snapSystem.removeEntity(physicsEntity)
        await shadowRenderer.removeShadowCaster(physicsEntity)
        
        physicsEntities.removeValue(forKey: entityID)
        
        logDebug("Removed entity from physics simulation", category: .general, context: LogContext(customData: [
            "entity_id": entityID.uuidString
        ]))
    }
    
    /// Add a static collider (walls, floor, furniture)
    public func addStaticCollider(_ anchor: ARAnchor, geometry: ColliderGeometry) async {
        let collider = StaticCollider(
            id: anchor.identifier,
            transform: anchor.transform,
            geometry: geometry
        )
        
        staticColliders[anchor.identifier] = collider
        collisionDetector.addStaticCollider(collider)
        
        // Add as snap target if applicable
        if let snapTarget = createSnapTarget(from: collider) {
            snapTargets[anchor.identifier] = snapTarget
            snapSystem.addSnapTarget(snapTarget)
        }
        
        logDebug("Added static collider", category: .general, context: LogContext(customData: [
            "anchor_id": anchor.identifier.uuidString,
            "geometry_type": geometry.type.rawValue
        ]))
    }
    
    /// Update static collider
    public func updateStaticCollider(_ anchor: ARAnchor) async {
        guard let collider = staticColliders[anchor.identifier] else { return }
        
        let updatedCollider = StaticCollider(
            id: anchor.identifier,
            transform: anchor.transform,
            geometry: collider.geometry
        )
        
        staticColliders[anchor.identifier] = updatedCollider
        collisionDetector.updateStaticCollider(updatedCollider)
        
        // Update snap target
        if let snapTarget = snapTargets[anchor.identifier] {
            let updatedSnapTarget = SnapTarget(
                id: snapTarget.id,
                transform: anchor.transform,
                type: snapTarget.type,
                normal: snapTarget.normal,
                bounds: snapTarget.bounds
            )
            snapTargets[anchor.identifier] = updatedSnapTarget
            snapSystem.updateSnapTarget(updatedSnapTarget)
        }
    }
    
    /// Remove static collider
    public func removeStaticCollider(_ anchorID: UUID) async {
        if let collider = staticColliders[anchorID] {
            collisionDetector.removeStaticCollider(collider)
            staticColliders.removeValue(forKey: anchorID)
        }
        
        if let snapTarget = snapTargets[anchorID] {
            snapSystem.removeSnapTarget(snapTarget)
            snapTargets.removeValue(forKey: anchorID)
        }
    }
    
    /// Apply force to an entity
    public func applyForce(_ force: SIMD3<Float>, to entityID: UUID, at point: SIMD3<Float>? = nil) async {
        guard let physicsEntity = physicsEntities[entityID] else { return }
        
        physicsWorld.applyForce(force, to: physicsEntity, at: point)
        
        logDebug("Applied force to entity", category: .general, context: LogContext(customData: [
            "entity_id": entityID.uuidString,
            "force": [force.x, force.y, force.z]
        ]))
    }
    
    /// Apply impulse to an entity
    public func applyImpulse(_ impulse: SIMD3<Float>, to entityID: UUID, at point: SIMD3<Float>? = nil) async {
        guard let physicsEntity = physicsEntities[entityID] else { return }
        
        physicsWorld.applyImpulse(impulse, to: physicsEntity, at: point)
        
        logDebug("Applied impulse to entity", category: .general, context: LogContext(customData: [
            "entity_id": entityID.uuidString,
            "impulse": [impulse.x, impulse.y, impulse.z]
        ]))
    }
    
    /// Snap entity to nearest surface
    public func snapToSurface(_ entityID: UUID, snapType: SnapType = .automatic) async -> Bool {
        guard let physicsEntity = physicsEntities[entityID] else { return false }
        
        let result = await snapSystem.snapToSurface(physicsEntity, type: snapType)
        
        if result.snapped {
            logDebug("Entity snapped to surface", category: .general, context: LogContext(customData: [
                "entity_id": entityID.uuidString,
                "snap_type": snapType.rawValue,
                "target_type": result.targetType?.rawValue ?? "none"
            ]))
        }
        
        return result.snapped
    }
    
    /// Enable/disable physics for specific entity
    public func setPhysicsEnabled(_ enabled: Bool, for entityID: UUID) async {
        guard let physicsEntity = physicsEntities[entityID] else { return }
        
        physicsEntity.isPhysicsEnabled = enabled
        
        if enabled {
            physicsWorld.addEntity(physicsEntity)
        } else {
            physicsWorld.removeEntity(physicsEntity)
        }
    }
    
    /// Update physics configuration
    public func updateConfiguration(_ newConfiguration: PhysicsConfiguration) async {
        configuration = newConfiguration
        
        physicsWorld.updateConfiguration(newConfiguration)
        collisionDetector.updateConfiguration(newConfiguration)
        snapSystem.updateConfiguration(newConfiguration)
        performanceManager.updateConfiguration(newConfiguration)
        
        logInfo("Physics configuration updated", category: .general)
    }
    
    /// Get physics statistics
    public func getPhysicsStatistics() -> PhysicsStatistics {
        return PhysicsStatistics(
            totalEntities: physicsEntities.count,
            activeEntities: physicsEntities.values.filter { $0.isActive }.count,
            staticColliders: staticColliders.count,
            snapTargets: snapTargets.count,
            frameTime: frameTime,
            collisionChecks: collisionDetector.getStatistics().collisionChecks,
            snapOperations: snapSystem.getStatistics().snapOperations,
            shadowUpdates: shadowRenderer.getStatistics().shadowUpdates,
            memoryUsage: performanceManager.getMemoryUsage()
        )
    }
    
    // MARK: - Private Methods
    
    private func setupPhysicsWorld() {
        // Configure physics world
        physicsWorld.gravity = configuration.gravity
        physicsWorld.damping = configuration.damping
        physicsWorld.sleepThreshold = configuration.sleepThreshold
    }
    
    private func setupRealityKitPhysics(_ arView: ARView) async {
        // Enable physics simulation in RealityKit
        if let scene = arView.scene as? Scene {
            // Configure scene physics
            scene.physicsWorld.gravity = configuration.gravity
        }
        
        // Setup collision callbacks
        arView.scene.subscribe(to: CollisionEvents.Began.self) { [weak self] event in
            Task { @MainActor in
                await self?.handleCollisionBegan(event)
            }
        }.store(in: &anchorUpdates)
        
        arView.scene.subscribe(to: CollisionEvents.Updated.self) { [weak self] event in
            Task { @MainActor in
                await self?.handleCollisionUpdated(event)
            }
        }.store(in: &anchorUpdates)
        
        arView.scene.subscribe(to: CollisionEvents.Ended.self) { [weak self] event in
            Task { @MainActor in
                await self?.handleCollisionEnded(event)
            }
        }.store(in: &anchorUpdates)
    }
    
    private func startSimulation(_ arView: ARView) {
        // Start physics update loop
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePhysics()
            }
        }
    }
    
    private func updatePhysics() async {
        let startTime = CACurrentMediaTime()
        
        guard isEnabled else { return }
        
        // Update physics world
        if gravityEnabled {
            await physicsWorld.step(deltaTime: 1.0/60.0)
        }
        
        // Update collision detection
        if collisionDetectionEnabled {
            await collisionDetector.detectCollisions()
        }
        
        // Update snap system
        if snapToFloorEnabled || snapToWallEnabled {
            await snapSystem.updateSnapping()
        }
        
        // Update shadows
        if shadowsEnabled {
            await shadowRenderer.updateShadows()
        }
        
        // Update occlusion
        if occlusionEnabled {
            await occlusionManager.updateOcclusion()
        }
        
        // Performance management
        if performanceOptimized {
            await performanceManager.optimizePerformance()
        }
        
        frameTime = CACurrentMediaTime() - startTime
        lastUpdateTime = startTime
        
        // Check performance budget
        if frameTime > configuration.performanceBudget {
            logWarning("Physics frame time exceeded budget: \(frameTime * 1000)ms", category: .general)
            await performanceManager.handlePerformanceIssue()
        }
    }
    
    private func createPhysicsEntity(_ entity: Entity, properties: PhysicsProperties) async throws -> PhysicsEntity {
        // Extract geometry from entity
        let geometry = try await extractGeometry(from: entity)
        
        // Create physics body
        let physicsBody = PhysicsBody(
            mass: properties.mass,
            geometry: geometry,
            material: PhysicsMaterial(
                friction: properties.friction ?? configuration.friction,
                restitution: properties.restitution ?? configuration.restitution
            )
        )
        
        return PhysicsEntity(
            id: entity.id,
            entity: entity,
            physicsBody: physicsBody,
            properties: properties
        )
    }
    
    private func extractGeometry(from entity: Entity) async throws -> ColliderGeometry {
        // Try to get mesh from ModelEntity
        if let modelEntity = entity as? ModelEntity,
           let mesh = modelEntity.model?.mesh {
            return .mesh(MeshGeometry(mesh: mesh))
        }
        
        // Fallback to bounding box
        let bounds = entity.visualBounds(relativeTo: nil)
        return .box(BoxGeometry(size: bounds.extents))
    }
    
    private func createSnapTarget(from collider: StaticCollider) -> SnapTarget? {
        switch collider.geometry.type {
        case .plane:
            if let planeGeometry = collider.geometry as? PlaneGeometry {
                let normal = planeGeometry.normal
                let type: SnapTargetType = abs(normal.y) > 0.8 ? .floor : .wall
                
                return SnapTarget(
                    id: collider.id,
                    transform: collider.transform,
                    type: type,
                    normal: normal,
                    bounds: planeGeometry.bounds
                )
            }
        default:
            break
        }
        
        return nil
    }
    
    // MARK: - Collision Event Handlers
    
    private func handleCollisionBegan(_ event: CollisionEvents.Began) async {
        logDebug("Collision began", category: .general, context: LogContext(customData: [
            "entity_a": event.entityA.id.uuidString,
            "entity_b": event.entityB.id.uuidString
        ]))
        
        // Handle collision response
        await collisionDetector.handleCollisionBegan(event)
    }
    
    private func handleCollisionUpdated(_ event: CollisionEvents.Updated) async {
        // Handle ongoing collision
        await collisionDetector.handleCollisionUpdated(event)
    }
    
    private func handleCollisionEnded(_ event: CollisionEvents.Ended) async {
        logDebug("Collision ended", category: .general, context: LogContext(customData: [
            "entity_a": event.entityA.id.uuidString,
            "entity_b": event.entityB.id.uuidString
        ]))
        
        // Handle collision end
        await collisionDetector.handleCollisionEnded(event)
    }
}

// MARK: - Physics Properties

public struct PhysicsProperties {
    public let mass: Float
    public let friction: Float?
    public let restitution: Float?
    public let canSnap: Bool
    public let castsShadows: Bool
    public let receivesOcclusion: Bool
    public let isKinematic: Bool
    public let collisionGroup: CollisionGroup
    
    public init(
        mass: Float = 1.0,
        friction: Float? = nil,
        restitution: Float? = nil,
        canSnap: Bool = true,
        castsShadows: Bool = true,
        receivesOcclusion: Bool = true,
        isKinematic: Bool = false,
        collisionGroup: CollisionGroup = .furniture
    ) {
        self.mass = mass
        self.friction = friction
        self.restitution = restitution
        self.canSnap = canSnap
        self.castsShadows = castsShadows
        self.receivesOcclusion = receivesOcclusion
        self.isKinematic = isKinematic
        self.collisionGroup = collisionGroup
    }
}

// MARK: - Physics Statistics

public struct PhysicsStatistics {
    public let totalEntities: Int
    public let activeEntities: Int
    public let staticColliders: Int
    public let snapTargets: Int
    public let frameTime: TimeInterval
    public let collisionChecks: Int
    public let snapOperations: Int
    public let shadowUpdates: Int
    public let memoryUsage: Int64
    
    public init(
        totalEntities: Int,
        activeEntities: Int,
        staticColliders: Int,
        snapTargets: Int,
        frameTime: TimeInterval,
        collisionChecks: Int,
        snapOperations: Int,
        shadowUpdates: Int,
        memoryUsage: Int64
    ) {
        self.totalEntities = totalEntities
        self.activeEntities = activeEntities
        self.staticColliders = staticColliders
        self.snapTargets = snapTargets
        self.frameTime = frameTime
        self.collisionChecks = collisionChecks
        self.snapOperations = snapOperations
        self.shadowUpdates = shadowUpdates
        self.memoryUsage = memoryUsage
    }
}

// MARK: - Collision Groups

public enum CollisionGroup: UInt32, CaseIterable {
    case none = 0
    case furniture = 1
    case walls = 2
    case floor = 4
    case ceiling = 8
    case decoration = 16
    case all = 0xFFFFFFFF
    
    public var filter: CollisionFilter {
        return CollisionFilter(group: CollisionGroup(rawValue: rawValue) ?? .none, mask: .all)
    }
}

#Preview {
    Text("Physics System")
}