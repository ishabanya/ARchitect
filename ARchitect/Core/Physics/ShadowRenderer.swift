import Foundation
import RealityKit
import Metal
import MetalKit
import simd
import ARKit

// MARK: - Shadow Renderer

@MainActor
public class ShadowRenderer: ObservableObject {
    
    // MARK: - Properties
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var shadowMapTexture: MTLTexture?
    private var shadowRenderPipeline: MTLRenderPipelineState?
    private var shadowComputePipeline: MTLComputePipelineState?
    
    // Shadow configuration
    private var shadowMapSize: Int = 2048
    private var shadowDistance: Float = 10.0
    private var shadowSoftness: Float = 0.002
    private var shadowBias: Float = 0.005
    
    // Shadow casters and receivers
    private var shadowCasters: [UUID: ShadowCaster] = [:]
    private var shadowReceivers: [UUID: ShadowReceiver] = [:]
    private var lightSources: [LightSource] = []
    
    // Performance tracking
    private var shadowUpdates: Int = 0
    private var frameTime: TimeInterval = 0
    private var isEnabled: Bool = true
    
    // RealityKit integration
    private var arView: ARView?
    private var shadowEntity: Entity?
    
    public init() {
        setupMetal()
        createDefaultLightSource()
        
        logDebug("Shadow renderer initialized", category: .general)
    }
    
    // MARK: - Initialization
    
    public func initialize(with arView: ARView) async {
        self.arView = arView
        
        // Setup shadow plane entity
        await setupShadowPlane()
        
        // Create shadow materials
        await createShadowMaterials()
        
        logInfo("Shadow renderer initialized with AR view", category: .general)
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logError("Failed to create Metal device", category: .general)
            return
        }
        
        metalDevice = device
        commandQueue = device.makeCommandQueue()
        
        // Create shadow map texture
        createShadowMapTexture()
        
        // Create render pipelines
        createRenderPipelines()
        
        logDebug("Metal setup completed for shadow rendering", category: .general)
    }
    
    private func createShadowMapTexture() {
        guard let device = metalDevice else { return }
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .depth32Float
        descriptor.width = shadowMapSize
        descriptor.height = shadowMapSize
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        
        shadowMapTexture = device.makeTexture(descriptor: descriptor)
        shadowMapTexture?.label = "Shadow Map"
        
        logDebug("Created shadow map texture", category: .general, context: LogContext(customData: [
            "size": shadowMapSize
        ]))
    }
    
    private func createRenderPipelines() {
        guard let device = metalDevice else { return }
        
        do {
            // Create shader library
            let library = try device.makeDefaultLibrary(bundle: Bundle.main)
            
            // Shadow map generation pipeline
            let shadowVertexFunction = library?.makeFunction(name: "shadowMapVertex")
            let shadowFragmentFunction = library?.makeFunction(name: "shadowMapFragment")
            
            let shadowPipelineDescriptor = MTLRenderPipelineDescriptor()
            shadowPipelineDescriptor.vertexFunction = shadowVertexFunction
            shadowPipelineDescriptor.fragmentFunction = shadowFragmentFunction
            shadowPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            
            shadowRenderPipeline = try device.makeRenderPipelineState(descriptor: shadowPipelineDescriptor)
            
            // Shadow compute pipeline for soft shadows
            if let computeFunction = library?.makeFunction(name: "softShadowCompute") {
                shadowComputePipeline = try device.makeComputePipelineState(function: computeFunction)
            }
            
            logDebug("Created shadow render pipelines", category: .general)
            
        } catch {
            logError("Failed to create shadow render pipelines: \(error)", category: .general)
        }
    }
    
    private func setupShadowPlane() async {
        guard let arView = arView else { return }
        
        // Create a large plane to receive shadows
        let shadowPlane = ModelEntity(
            mesh: .generatePlane(width: 20, depth: 20),
            materials: [await createShadowMaterial()]
        )
        
        shadowPlane.name = "ShadowPlane"
        shadowPlane.position = SIMD3<Float>(0, -0.01, 0) // Slightly below ground
        
        // Add to scene
        let shadowAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        shadowAnchor.addChild(shadowPlane)
        arView.scene.addAnchor(shadowAnchor)
        
        shadowEntity = shadowPlane
        
        logDebug("Created shadow plane", category: .general)
    }
    
    private func createShadowMaterials() async {
        // Create materials for shadow casting and receiving
        for caster in shadowCasters.values {
            await updateCasterMaterial(caster)
        }
        
        for receiver in shadowReceivers.values {
            await updateReceiverMaterial(receiver)
        }
    }
    
    private func createDefaultLightSource() {
        // Create a default directional light (sun)
        let sunLight = LightSource(
            id: UUID(),
            type: .directional,
            position: SIMD3<Float>(0, 10, 0),
            direction: simd_normalize(SIMD3<Float>(0.3, -1, 0.5)),
            intensity: 1.0,
            color: SIMD3<Float>(1, 0.95, 0.8), // Warm sunlight
            shadowDistance: shadowDistance
        )
        
        lightSources.append(sunLight)
        
        logDebug("Created default light source", category: .general)
    }
    
    // MARK: - Shadow Caster Management
    
    public func addShadowCaster(_ entity: PhysicsEntity) async {
        let caster = ShadowCaster(
            id: entity.id,
            entity: entity.entity,
            bounds: entity.entity.visualBounds(relativeTo: nil),
            castsSoftShadows: true
        )
        
        shadowCasters[entity.id] = caster
        await updateCasterMaterial(caster)
        
        logDebug("Added shadow caster", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    public func removeShadowCaster(_ entity: PhysicsEntity) async {
        shadowCasters.removeValue(forKey: entity.id)
        
        logDebug("Removed shadow caster", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    public func addShadowReceiver(_ entity: Entity) async {
        let receiver = ShadowReceiver(
            id: entity.id,
            entity: entity,
            bounds: entity.visualBounds(relativeTo: nil),
            receivesSoftShadows: true
        )
        
        shadowReceivers[entity.id] = receiver
        await updateReceiverMaterial(receiver)
        
        logDebug("Added shadow receiver", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString
        ]))
    }
    
    public func removeShadowReceiver(_ entityID: UUID) async {
        shadowReceivers.removeValue(forKey: entityID)
        
        logDebug("Removed shadow receiver", category: .general, context: LogContext(customData: [
            "entity_id": entityID.uuidString
        ]))
    }
    
    // MARK: - Shadow Updates
    
    public func updateShadows() async {
        guard isEnabled else { return }
        
        let startTime = CACurrentMediaTime()
        
        // Update light positions (e.g., based on AR lighting estimation)
        await updateLightSources()
        
        // Generate shadow maps
        await generateShadowMaps()
        
        // Update shadow materials
        await updateShadowMaterials()
        
        shadowUpdates += 1
        frameTime = CACurrentMediaTime() - startTime
        
        if shadowUpdates % 60 == 0 { // Log every 60 updates
            logDebug("Shadow update completed", category: .general, context: LogContext(customData: [
                "frame_time": frameTime * 1000,
                "shadow_casters": shadowCasters.count,
                "shadow_receivers": shadowReceivers.count
            ]))
        }
    }
    
    private func updateLightSources() async {
        guard let arView = arView else { return }
        
        // Update sun direction based on AR lighting estimation
        if let lightEstimate = arView.session.currentFrame?.lightEstimate as? ARDirectionalLightEstimate {
            if let sunLight = lightSources.first(where: { $0.type == .directional }) {
                let newDirection = lightEstimate.primaryLightDirection
                lightSources[0].direction = newDirection
                lightSources[0].intensity = lightEstimate.primaryLightIntensity
            }
        }
    }
    
    private func generateShadowMaps() async {
        guard let device = metalDevice,
              let commandQueue = commandQueue,
              let renderPipeline = shadowRenderPipeline,
              let shadowMapTexture = shadowMapTexture else { return }
        
        for light in lightSources {
            guard light.castsShadows else { continue }
            
            // Create command buffer
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { continue }
            commandBuffer.label = "Shadow Map Generation"
            
            // Create render pass
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.depthAttachment.texture = shadowMapTexture
            renderPassDescriptor.depthAttachment.loadAction = .clear
            renderPassDescriptor.depthAttachment.storeAction = .store
            renderPassDescriptor.depthAttachment.clearDepth = 1.0
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { continue }
            renderEncoder.label = "Shadow Map Render"
            
            // Set render pipeline
            renderEncoder.setRenderPipelineState(renderPipeline)
            
            // Calculate light view-projection matrix
            let lightViewMatrix = calculateLightViewMatrix(light: light)
            let lightProjectionMatrix = calculateLightProjectionMatrix(light: light)
            let lightViewProjectionMatrix = lightProjectionMatrix * lightViewMatrix
            
            // Render shadow casters
            for caster in shadowCasters.values {
                renderShadowCaster(caster, encoder: renderEncoder, lightViewProjection: lightViewProjectionMatrix)
            }
            
            renderEncoder.endEncoding()
            
            // Apply soft shadow filter if enabled
            if light.softShadows {
                await applySoftShadowFilter(commandBuffer: commandBuffer)
            }
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }
    
    private func renderShadowCaster(_ caster: ShadowCaster, encoder: MTLRenderCommandEncoder, lightViewProjection: simd_float4x4) {
        // Get model matrix from entity transform
        let modelMatrix = caster.entity.transform.matrix
        let mvpMatrix = lightViewProjection * modelMatrix
        
        // Set uniforms
        var uniforms = ShadowUniforms(
            modelViewProjectionMatrix: mvpMatrix,
            modelMatrix: modelMatrix
        )
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShadowUniforms>.size, index: 0)
        
        // Render geometry (simplified - would need actual mesh data)
        // This would typically render the entity's mesh with the shadow pipeline
    }
    
    private func applySoftShadowFilter(commandBuffer: MTLCommandBuffer) async {
        guard let computePipeline = shadowComputePipeline,
              let shadowMapTexture = shadowMapTexture else { return }
        
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        computeEncoder.label = "Soft Shadow Filter"
        
        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setTexture(shadowMapTexture, index: 0)
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (shadowMapSize + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (shadowMapSize + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
    }
    
    private func updateShadowMaterials() async {
        // Update materials for shadow receivers with new shadow maps
        for receiver in shadowReceivers.values {
            await updateReceiverMaterial(receiver)
        }
    }
    
    // MARK: - Material Creation
    
    private func createShadowMaterial() async -> Material {
        // Create a custom material for shadow receiving
        var material = UnlitMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.3))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.3))
        
        return material
    }
    
    private func updateCasterMaterial(_ caster: ShadowCaster) async {
        // Update material to enable shadow casting
        if let modelEntity = caster.entity as? ModelEntity {
            // Enable shadow casting in RealityKit
            modelEntity.components.set(GroundingShadowComponent(castsShadow: true))
        }
    }
    
    private func updateReceiverMaterial(_ receiver: ShadowReceiver) async {
        // Update material to receive shadows
        if let modelEntity = receiver.entity as? ModelEntity {
            // Enable shadow receiving in RealityKit
            modelEntity.components.set(GroundingShadowComponent(castsShadow: false))
        }
    }
    
    // MARK: - Light Calculations
    
    private func calculateLightViewMatrix(light: LightSource) -> simd_float4x4 {
        switch light.type {
        case .directional:
            // For directional lights, position the camera far away in the opposite direction
            let lightPosition = -light.direction * light.shadowDistance
            return simd_lookAt(eye: lightPosition, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
            
        case .point:
            return simd_lookAt(eye: light.position, target: light.position + light.direction, up: SIMD3<Float>(0, 1, 0))
            
        case .spot:
            return simd_lookAt(eye: light.position, target: light.position + light.direction, up: SIMD3<Float>(0, 1, 0))
        }
    }
    
    private func calculateLightProjectionMatrix(light: LightSource) -> simd_float4x4 {
        switch light.type {
        case .directional:
            // Orthographic projection for directional lights
            let size = light.shadowDistance * 0.5
            return simd_ortho(left: -size, right: size, bottom: -size, top: size, near: 0.1, far: light.shadowDistance * 2.0)
            
        case .point:
            // Perspective projection for point lights
            return simd_perspective(fovy: .pi / 2, aspect: 1.0, near: 0.1, far: light.shadowDistance)
            
        case .spot:
            // Perspective projection for spot lights
            let fovy = light.spotAngle ?? (.pi / 4)
            return simd_perspective(fovy: fovy, aspect: 1.0, near: 0.1, far: light.shadowDistance)
        }
    }
    
    // MARK: - Utility Functions
    
    private func simd_lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, up))
        let correctedUp = simd_cross(right, forward)
        
        return simd_float4x4(
            SIMD4<Float>(right.x, correctedUp.x, -forward.x, 0),
            SIMD4<Float>(right.y, correctedUp.y, -forward.y, 0),
            SIMD4<Float>(right.z, correctedUp.z, -forward.z, 0),
            SIMD4<Float>(-simd_dot(right, eye), -simd_dot(correctedUp, eye), simd_dot(forward, eye), 1)
        )
    }
    
    private func simd_ortho(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        let width = right - left
        let height = top - bottom
        let depth = far - near
        
        return simd_float4x4(
            SIMD4<Float>(2 / width, 0, 0, 0),
            SIMD4<Float>(0, 2 / height, 0, 0),
            SIMD4<Float>(0, 0, -2 / depth, 0),
            SIMD4<Float>(-(right + left) / width, -(top + bottom) / height, -(far + near) / depth, 1)
        )
    }
    
    private func simd_perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fovy * 0.5)
        let xScale = yScale / aspect
        let zScale = far / (near - far)
        
        return simd_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, near * zScale, 0)
        )
    }
    
    // MARK: - Configuration
    
    public func setShadowQuality(_ quality: ShadowQuality) {
        switch quality {
        case .low:
            shadowMapSize = 1024
            shadowSoftness = 0.005
        case .medium:
            shadowMapSize = 2048
            shadowSoftness = 0.002
        case .high:
            shadowMapSize = 4096
            shadowSoftness = 0.001
        case .ultra:
            shadowMapSize = 8192
            shadowSoftness = 0.0005
        }
        
        // Recreate shadow map texture with new size
        createShadowMapTexture()
        
        logInfo("Shadow quality updated", category: .general, context: LogContext(customData: [
            "quality": quality.rawValue,
            "map_size": shadowMapSize
        ]))
    }
    
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        
        if !enabled {
            // Hide all shadows
            shadowEntity?.isEnabled = false
        } else {
            shadowEntity?.isEnabled = true
        }
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> ShadowStatistics {
        return ShadowStatistics(
            shadowUpdates: shadowUpdates,
            frameTime: frameTime,
            shadowCasters: shadowCasters.count,
            shadowReceivers: shadowReceivers.count,
            lightSources: lightSources.count,
            shadowMapSize: shadowMapSize
        )
    }
}

// MARK: - Supporting Types

public struct ShadowCaster {
    public let id: UUID
    public let entity: Entity
    public let bounds: BoundingBox
    public let castsSoftShadows: Bool
    
    public init(id: UUID, entity: Entity, bounds: BoundingBox, castsSoftShadows: Bool) {
        self.id = id
        self.entity = entity
        self.bounds = bounds
        self.castsSoftShadows = castsSoftShadows
    }
}

public struct ShadowReceiver {
    public let id: UUID
    public let entity: Entity
    public let bounds: BoundingBox
    public let receivesSoftShadows: Bool
    
    public init(id: UUID, entity: Entity, bounds: BoundingBox, receivesSoftShadows: Bool) {
        self.id = id
        self.entity = entity
        self.bounds = bounds
        self.receivesSoftShadows = receivesSoftShadows
    }
}

public class LightSource {
    public let id: UUID
    public let type: LightType
    public var position: SIMD3<Float>
    public var direction: SIMD3<Float>
    public var intensity: Float
    public var color: SIMD3<Float>
    public let shadowDistance: Float
    public let castsShadows: Bool
    public let softShadows: Bool
    public let spotAngle: Float?
    
    public init(
        id: UUID,
        type: LightType,
        position: SIMD3<Float>,
        direction: SIMD3<Float>,
        intensity: Float,
        color: SIMD3<Float>,
        shadowDistance: Float,
        castsShadows: Bool = true,
        softShadows: Bool = true,
        spotAngle: Float? = nil
    ) {
        self.id = id
        self.type = type
        self.position = position
        self.direction = direction
        self.intensity = intensity
        self.color = color
        self.shadowDistance = shadowDistance
        self.castsShadows = castsShadows
        self.softShadows = softShadows
        self.spotAngle = spotAngle
    }
}

public enum LightType {
    case directional
    case point
    case spot
}

public enum ShadowQuality: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case ultra = "ultra"
}

public struct ShadowUniforms {
    let modelViewProjectionMatrix: simd_float4x4
    let modelMatrix: simd_float4x4
    
    public init(modelViewProjectionMatrix: simd_float4x4, modelMatrix: simd_float4x4) {
        self.modelViewProjectionMatrix = modelViewProjectionMatrix
        self.modelMatrix = modelMatrix
    }
}

public struct ShadowStatistics {
    public let shadowUpdates: Int
    public let frameTime: TimeInterval
    public let shadowCasters: Int
    public let shadowReceivers: Int
    public let lightSources: Int
    public let shadowMapSize: Int
    
    public init(shadowUpdates: Int, frameTime: TimeInterval, shadowCasters: Int, shadowReceivers: Int, lightSources: Int, shadowMapSize: Int) {
        self.shadowUpdates = shadowUpdates
        self.frameTime = frameTime
        self.shadowCasters = shadowCasters
        self.shadowReceivers = shadowReceivers
        self.lightSources = lightSources
        self.shadowMapSize = shadowMapSize
    }
}