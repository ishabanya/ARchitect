import Foundation
import RealityKit
import ARKit
import simd
import SwiftUI

// MARK: - Physics Integration

@MainActor
public class PhysicsIntegration: ObservableObject {
    
    // MARK: - Properties
    private let physicsSystem: PhysicsSystem
    private let furnitureCatalog: FurnitureCatalog
    private let modelManager: ModelManager
    
    // Integration state
    @Published public var isPhysicsEnabled = true
    @Published public var physicsQuality: PhysicsQuality = .high
    @Published public var debugVisualization = false
    
    // Physics entities mapping
    private var furniturePhysicsMapping: [UUID: UUID] = [:] // Furniture ID -> Physics Entity ID
    
    public init(furnitureCatalog: FurnitureCatalog, modelManager: ModelManager) {
        self.physicsSystem = PhysicsSystem()
        self.furnitureCatalog = furnitureCatalog
        self.modelManager = modelManager
        
        setupIntegration()
        
        logInfo("Physics integration initialized", category: .general)
    }
    
    // MARK: - Integration Setup
    
    private func setupIntegration() {
        // Configure physics system based on quality setting
        updatePhysicsQuality()
        
        // Setup observers for furniture catalog changes
        setupFurnitureCatalogObservers()
        
        // Setup observers for model manager changes
        setupModelManagerObservers()
    }
    
    private func setupFurnitureCatalogObservers() {
        // Observe when furniture items are placed in AR
        // This would typically be handled through notifications or delegates
    }
    
    private func setupModelManagerObservers() {
        // Observe when 3D models are loaded/unloaded
        // This would typically be handled through notifications or delegates
    }
    
    // MARK: - AR Integration
    
    public func initializeWithARView(_ arView: ARView) async {
        // Initialize physics system with AR view
        await physicsSystem.initialize(with: arView)
        
        // Setup AR anchors as static colliders
        await setupARAnchorsAsColliders(arView)
        
        // Initialize shadow rendering
        await setupShadowRendering(arView)
        
        // Initialize occlusion
        await setupOcclusion(arView)
        
        logInfo("Physics integration initialized with AR view", category: .general)
    }
    
    private func setupARAnchorsAsColliders(_ arView: ARView) async {
        // Subscribe to anchor updates
        arView.scene.subscribe(to: SceneEvents.AnchoredStateChanged.self) { [weak self] event in
            Task { @MainActor in
                await self?.handleAnchorStateChanged(event)
            }
        }
    }
    
    private func setupShadowRendering(_ arView: ARView) async {
        // Configure shadow rendering based on quality settings
        let shadowQuality: ShadowQuality = {
            switch physicsQuality {
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            case .ultra: return .ultra
            }
        }()
        
        // This would be integrated with the shadow renderer
    }
    
    private func setupOcclusion(_ arView: ARView) async {
        // Enable occlusion based on device capabilities
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            await physicsSystem.occlusionManager.initialize(with: arView)
        }
    }
    
    // MARK: - Furniture Physics Integration
    
    public func addFurnitureToPhysics(_ furnitureItem: FurnitureItem) async throws {
        // Load the 3D model
        let entity = try await modelManager.loadModel(furnitureItem.model3D)
        
        // Create physics properties based on furniture metadata
        let physicsProperties = createPhysicsProperties(from: furnitureItem)
        
        // Add to physics system
        try await physicsSystem.addEntity(entity, physicsProperties: physicsProperties)
        
        // Store mapping
        furniturePhysicsMapping[furnitureItem.id] = entity.id
        
        logInfo("Added furniture to physics", category: .general, context: LogContext(customData: [
            "furniture_id": furnitureItem.id.uuidString,
            "furniture_name": furnitureItem.name,
            "mass": physicsProperties.mass
        ]))
    }
    
    public func removeFurnitureFromPhysics(_ furnitureID: UUID) async {
        guard let entityID = furniturePhysicsMapping[furnitureID] else { return }
        
        await physicsSystem.removeEntity(entityID)
        furniturePhysicsMapping.removeValue(forKey: furnitureID)
        
        logInfo("Removed furniture from physics", category: .general, context: LogContext(customData: [
            "furniture_id": furnitureID.uuidString
        ]))
    }
    
    private func createPhysicsProperties(from furnitureItem: FurnitureItem) -> PhysicsProperties {
        // Calculate mass based on furniture dimensions and material
        let volume = furnitureItem.metadata.dimensions.volume
        let baseDensity: Float = 500 // kg/m³ for typical furniture
        
        // Adjust density based on materials
        let materialDensityMultiplier = calculateMaterialDensity(furnitureItem.metadata.materials)
        let mass = volume * baseDensity * materialDensityMultiplier
        
        // Determine collision group
        let collisionGroup: CollisionGroup = {
            switch furnitureItem.category {
            case .seating, .tables, .storage, .bedroom: return .furniture
            case .decor: return .decoration
            default: return .furniture
            }
        }()
        
        return PhysicsProperties(
            mass: mass,
            friction: calculateFriction(furnitureItem.metadata.materials),
            restitution: calculateRestitution(furnitureItem.metadata.materials),
            canSnap: true,
            castsShadows: true,
            receivesOcclusion: true,
            isKinematic: false,
            collisionGroup: collisionGroup
        )
    }
    
    private func calculateMaterialDensity(_ materials: [FurnitureMaterial]) -> Float {
        var densityMultiplier: Float = 1.0
        
        for material in materials {
            switch material {
            case .wood: densityMultiplier *= 0.6
            case .metal: densityMultiplier *= 2.0
            case .marble, .stone: densityMultiplier *= 2.5
            case .fabric, .leather: densityMultiplier *= 0.3
            case .plastic: densityMultiplier *= 0.4
            case .glass, .ceramic: densityMultiplier *= 1.5
            default: break
            }
        }
        
        return densityMultiplier / Float(materials.count)
    }
    
    private func calculateFriction(_ materials: [FurnitureMaterial]) -> Float {
        var totalFriction: Float = 0.0
        
        for material in materials {
            switch material {
            case .wood: totalFriction += 0.6
            case .metal: totalFriction += 0.3
            case .fabric, .leather: totalFriction += 0.8
            case .plastic: totalFriction += 0.4
            case .glass: totalFriction += 0.2
            case .rubber: totalFriction += 0.9
            default: totalFriction += 0.5
            }
        }
        
        return totalFriction / Float(materials.count)
    }
    
    private func calculateRestitution(_ materials: [FurnitureMaterial]) -> Float {
        var totalRestitution: Float = 0.0
        
        for material in materials {
            switch material {
            case .wood: totalRestitution += 0.3
            case .metal: totalRestitution += 0.7
            case .fabric, .leather: totalRestitution += 0.1
            case .plastic: totalRestitution += 0.5
            case .glass: totalRestitution += 0.8
            case .rubber: totalRestitution += 0.9
            default: totalRestitution += 0.3
            }
        }
        
        return totalRestitution / Float(materials.count)
    }
    
    // MARK: - Physics Controls
    
    public func snapFurnitureToFloor(_ furnitureID: UUID) async -> Bool {
        guard let entityID = furniturePhysicsMapping[furnitureID] else { return false }
        return await physicsSystem.snapToSurface(entityID, snapType: .floor)
    }
    
    public func snapFurnitureToWall(_ furnitureID: UUID) async -> Bool {
        guard let entityID = furniturePhysicsMapping[furnitureID] else { return false }
        return await physicsSystem.snapToSurface(entityID, snapType: .wall)
    }
    
    public func applyForceToFurniture(_ furnitureID: UUID, force: SIMD3<Float>) async {
        guard let entityID = furniturePhysicsMapping[furnitureID] else { return }
        await physicsSystem.applyForce(force, to: entityID)
    }
    
    public func setFurniturePhysicsEnabled(_ furnitureID: UUID, enabled: Bool) async {
        guard let entityID = furniturePhysicsMapping[furnitureID] else { return }
        await physicsSystem.setPhysicsEnabled(enabled, for: entityID)
    }
    
    // MARK: - Configuration
    
    public func setPhysicsEnabled(_ enabled: Bool) {
        isPhysicsEnabled = enabled
        physicsSystem.isEnabled = enabled
        
        logInfo("Physics \(enabled ? "enabled" : "disabled")", category: .general)
    }
    
    public func setPhysicsQuality(_ quality: PhysicsQuality) {
        physicsQuality = quality
        updatePhysicsQuality()
        
        logInfo("Physics quality set to \(quality.rawValue)", category: .general)
    }
    
    private func updatePhysicsQuality() {
        var config = physicsSystem.configuration
        
        switch physicsQuality {
        case .low:
            config.performanceBudget = 0.020 // 20ms
            physicsSystem.collisionDetectionEnabled = true
            physicsSystem.shadowsEnabled = false
            physicsSystem.occlusionEnabled = false
            
        case .medium:
            config.performanceBudget = 0.012 // 12ms
            physicsSystem.collisionDetectionEnabled = true
            physicsSystem.shadowsEnabled = true
            physicsSystem.occlusionEnabled = false
            
        case .high:
            config.performanceBudget = 0.008 // 8ms
            physicsSystem.collisionDetectionEnabled = true
            physicsSystem.shadowsEnabled = true
            physicsSystem.occlusionEnabled = true
            
        case .ultra:
            config.performanceBudget = 0.005 // 5ms
            physicsSystem.collisionDetectionEnabled = true
            physicsSystem.shadowsEnabled = true
            physicsSystem.occlusionEnabled = true
        }
        
        Task {
            await physicsSystem.updateConfiguration(config)
        }
    }
    
    public func setDebugVisualization(_ enabled: Bool) {
        debugVisualization = enabled
        // This would enable/disable debug visualization overlays
    }
    
    // MARK: - Event Handlers
    
    private func handleAnchorStateChanged(_ event: SceneEvents.AnchoredStateChanged) async {
        let entity = event.entity
        
        if event.isAnchored {
            // Add anchor as static collider
            if let anchor = entity.anchor {
                let geometry = createGeometryFromAnchor(anchor)
                await physicsSystem.addStaticCollider(anchor, geometry: geometry)
            }
        } else {
            // Remove anchor from physics
            if let anchor = entity.anchor {
                await physicsSystem.removeStaticCollider(anchor.id)
            }
        }
    }
    
    private func createGeometryFromAnchor(_ anchor: ARAnchor) -> ColliderGeometry {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            // Create plane geometry
            let center = planeAnchor.center
            let extent = planeAnchor.extent
            
            return GeometryFactory.createPlane(
                normal: SIMD3<Float>(0, 1, 0), // Assume horizontal plane
                point: SIMD3<Float>(center.x, center.y, center.z),
                size: SIMD2<Float>(extent.x, extent.z)
            )
        } else if let meshAnchor = anchor as? ARMeshAnchor {
            // Create mesh geometry from mesh anchor
            let geometry = meshAnchor.geometry
            var vertices: [SIMD3<Float>] = []
            var indices: [UInt32] = []
            
            // Extract vertices
            let vertexCount = geometry.vertices.count
            let vertexBuffer = geometry.vertices.buffer.contents()
            
            for i in 0..<vertexCount {
                let vertex = vertexBuffer.advanced(by: i * MemoryLayout<SIMD3<Float>>.size)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee
                vertices.append(vertex)
            }
            
            // Extract indices
            let indexCount = geometry.faces.count * 3
            let indexBuffer = geometry.faces.buffer.contents()
            
            for i in 0..<indexCount {
                let index = indexBuffer.advanced(by: i * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee
                indices.append(index)
            }
            
            return GeometryFactory.createMeshFromVertices(vertices, indices: indices)
        } else {
            // Default to box geometry
            return GeometryFactory.createBox(width: 0.1, height: 0.1, depth: 0.1)
        }
    }
    
    // MARK: - Statistics and Debug
    
    public func getPhysicsStatistics() -> PhysicsStatistics {
        return physicsSystem.getPhysicsStatistics()
    }
    
    public func getPerformanceInfo() -> PhysicsPerformanceInfo {
        let stats = physicsSystem.getPhysicsStatistics()
        
        return PhysicsPerformanceInfo(
            frameTime: stats.frameTime,
            memoryUsage: stats.memoryUsage,
            activeEntities: stats.activeEntities,
            collisionChecks: stats.collisionChecks,
            shadowUpdates: stats.shadowUpdates,
            isPerformanceOptimized: physicsSystem.performanceOptimized
        )
    }
}

// MARK: - Physics Quality

public enum PhysicsQuality: String, CaseIterable {
    case low = "low"
    case medium = "medium"  
    case high = "high"
    case ultra = "ultra"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var description: String {
        switch self {
        case .low: return "Basic physics with limited features"
        case .medium: return "Standard physics with shadows"
        case .high: return "Full physics with shadows and occlusion"
        case .ultra: return "Maximum quality with all features"
        }
    }
}

// MARK: - Physics Performance Info

public struct PhysicsPerformanceInfo {
    public let frameTime: TimeInterval
    public let memoryUsage: Int64
    public let activeEntities: Int
    public let collisionChecks: Int
    public let shadowUpdates: Int
    public let isPerformanceOptimized: Bool
    
    public init(frameTime: TimeInterval, memoryUsage: Int64, activeEntities: Int, collisionChecks: Int, shadowUpdates: Int, isPerformanceOptimized: Bool) {
        self.frameTime = frameTime
        self.memoryUsage = memoryUsage
        self.activeEntities = activeEntities
        self.collisionChecks = collisionChecks
        self.shadowUpdates = shadowUpdates
        self.isPerformanceOptimized = isPerformanceOptimized
    }
    
    public var formattedFrameTime: String {
        return String(format: "%.2f ms", frameTime * 1000)
    }
    
    public var formattedMemoryUsage: String {
        let mb = Double(memoryUsage) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Physics Debug View

public struct PhysicsDebugView: View {
    @ObservedObject private var physicsIntegration: PhysicsIntegration
    @State private var performanceInfo: PhysicsPerformanceInfo
    
    public init(physicsIntegration: PhysicsIntegration) {
        self.physicsIntegration = physicsIntegration
        self._performanceInfo = State(initialValue: physicsIntegration.getPerformanceInfo())
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Physics Debug")
                .font(.headline)
                .fontWeight(.bold)
            
            Group {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(physicsIntegration.isPhysicsEnabled ? "Enabled" : "Disabled")
                        .foregroundColor(physicsIntegration.isPhysicsEnabled ? .green : .red)
                }
                
                HStack {
                    Text("Quality:")
                    Spacer()
                    Text(physicsIntegration.physicsQuality.displayName)
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Frame Time:")
                    Spacer()
                    Text(performanceInfo.formattedFrameTime)
                        .foregroundColor(performanceInfo.frameTime > 0.016 ? .red : .green)
                }
                
                HStack {
                    Text("Memory Usage:")
                    Spacer()
                    Text(performanceInfo.formattedMemoryUsage)
                }
                
                HStack {
                    Text("Active Entities:")
                    Spacer()
                    Text("\(performanceInfo.activeEntities)")
                }
                
                HStack {
                    Text("Collision Checks:")
                    Spacer()
                    Text("\(performanceInfo.collisionChecks)")
                }
                
                HStack {
                    Text("Shadow Updates:")
                    Spacer()
                    Text("\(performanceInfo.shadowUpdates)")
                }
                
                HStack {
                    Text("Performance Optimized:")
                    Spacer()
                    Text(performanceInfo.isPerformanceOptimized ? "Yes" : "No")
                        .foregroundColor(performanceInfo.isPerformanceOptimized ? .green : .orange)
                }
            }
            .font(.caption)
            
            HStack {
                Button("Toggle Physics") {
                    physicsIntegration.setPhysicsEnabled(!physicsIntegration.isPhysicsEnabled)
                }
                .buttonStyle(.bordered)
                
                Button("Toggle Debug") {
                    physicsIntegration.setDebugVisualization(!physicsIntegration.debugVisualization)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            performanceInfo = physicsIntegration.getPerformanceInfo()
        }
    }
}

#Preview {
    PhysicsDebugView(physicsIntegration: PhysicsIntegration(
        furnitureCatalog: FurnitureCatalog(),
        modelManager: ModelManager()
    ))
}