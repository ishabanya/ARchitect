import Foundation
import RealityKit
import UIKit
import MetalKit
import SceneKit
import ModelIO

// MARK: - Model Thumbnail Generator

public class ModelThumbnailGenerator {
    
    // MARK: - Private Properties
    private let renderQueue = DispatchQueue(label: "thumbnail.render", qos: .utility)
    private let thumbnailSize = CGSize(width: 256, height: 256)
    private let previewSize = CGSize(width: 512, height: 512)
    private let maxRenderTime: TimeInterval = 5.0
    
    // Rendering configuration
    private let cameraDistance: Float = 2.0
    private let lightIntensity: Float = 1000.0
    private let backgroundColor = UIColor.systemBackground
    
    public init() {
        logInfo("Model thumbnail generator initialized", category: .general, context: LogContext(customData: [
            "thumbnail_size": "\(Int(thumbnailSize.width))x\(Int(thumbnailSize.height))",
            "preview_size": "\(Int(previewSize.width))x\(Int(previewSize.height))"
        ]))
    }
    
    // MARK: - Public Methods
    
    /// Generate thumbnail for a model
    public func generateThumbnail(for model: Model3D, size: ThumbnailSize = .standard) async throws -> Data {
        let targetSize = size == .large ? previewSize : thumbnailSize
        
        logDebug("Generating thumbnail", category: .general, context: LogContext(customData: [
            "model_id": model.id.uuidString,
            "model_name": model.name,
            "size": "\(Int(targetSize.width))x\(Int(targetSize.height))"
        ]))
        
        switch model.format {
        case .usdz, .reality:
            return try await generateRealityKitThumbnail(model: model, size: targetSize)
        case .obj:
            return try await generateOBJThumbnail(model: model, size: targetSize)
        case .dae:
            return try await generateDAEThumbnail(model: model, size: targetSize)
        case .fbx, .gltf:
            return try await generateGenericThumbnail(model: model, size: targetSize)
        }
    }
    
    /// Generate thumbnail from loaded entity
    public func generateThumbnail(from entity: Entity, size: ThumbnailSize = .standard) async throws -> Data {
        let targetSize = size == .large ? previewSize : thumbnailSize
        
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                do {
                    let imageData = try self.renderEntityToImage(entity, size: targetSize)
                    continuation.resume(returning: imageData)
                } catch {
                    continuation.resume(throwing: ModelLoadingError.thumbnailGenerationFailed)
                }
            }
        }
    }
    
    /// Generate multiple thumbnails with different angles
    public func generateThumbnailSet(for model: Model3D) async throws -> ThumbnailSet {
        let angles: [ThumbnailAngle] = [.front, .side, .top, .perspective]
        var thumbnails: [ThumbnailAngle: Data] = [:]
        
        for angle in angles {
            do {
                let thumbnailData = try await generateThumbnailWithAngle(model: model, angle: angle)
                thumbnails[angle] = thumbnailData
            } catch {
                logWarning("Failed to generate \(angle.rawValue) thumbnail: \(error)", category: .general)
                // Continue with other angles
            }
        }
        
        return ThumbnailSet(
            modelID: model.id,
            thumbnails: thumbnails,
            generatedAt: Date()
        )
    }
    
    /// Generate animated GIF preview
    public func generateAnimatedPreview(for model: Model3D, duration: TimeInterval = 3.0) async throws -> Data {
        guard model.metadata.hasAnimations else {
            // Generate rotating preview instead
            return try await generateRotatingPreview(model: model, duration: duration)
        }
        
        return try await generateAnimationPreview(model: model, duration: duration)
    }
    
    /// Check if thumbnail exists in cache
    public func hasCachedThumbnail(for model: Model3D, size: ThumbnailSize = .standard) -> Bool {
        let cacheKey = thumbnailCacheKey(model: model, size: size)
        return ThumbnailCache.shared.hasImage(for: cacheKey)
    }
    
    /// Get cached thumbnail
    public func getCachedThumbnail(for model: Model3D, size: ThumbnailSize = .standard) -> Data? {
        let cacheKey = thumbnailCacheKey(model: model, size: size)
        return ThumbnailCache.shared.getImage(for: cacheKey)
    }
    
    // MARK: - Private Methods
    
    private func generateRealityKitThumbnail(model: Model3D, size: CGSize) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                do {
                    // Create a temporary ARView for rendering
                    let arView = ARView(frame: CGRect(origin: .zero, size: size))
                    arView.environment.background = .color(self.backgroundColor)
                    
                    // Load the model
                    let modelURL = try self.getModelURL(model)
                    let entity = try Entity.load(contentsOf: modelURL)
                    
                    // Setup scene
                    self.setupThumbnailScene(arView: arView, entity: entity, angle: .perspective)
                    
                    // Render
                    let imageData = try self.captureARViewImage(arView)
                    
                    // Cache the result
                    let cacheKey = self.thumbnailCacheKey(model: model, size: .standard)
                    ThumbnailCache.shared.setImage(imageData, for: cacheKey)
                    
                    continuation.resume(returning: imageData)
                    
                } catch {
                    continuation.resume(throwing: ModelLoadingError.thumbnailGenerationFailed)
                }
            }
        }
    }
    
    private func generateOBJThumbnail(model: Model3D, size: CGSize) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                do {
                    // Load OBJ using ModelIO
                    let modelURL = try self.getModelURL(model)
                    let asset = MDLAsset(url: modelURL)
                    
                    guard let object = asset.object(at: 0) as? MDLMesh else {
                        throw ModelLoadingError.invalidGeometry("No mesh found in OBJ")
                    }
                    
                    // Convert to SceneKit for rendering
                    let scene = SCNScene()
                    let node = SCNNode(mdlObject: object)
                    scene.rootNode.addChildNode(node)
                    
                    // Render using SceneKit
                    let imageData = try self.renderSceneKitScene(scene, size: size)
                    
                    continuation.resume(returning: imageData)
                    
                } catch {
                    continuation.resume(throwing: ModelLoadingError.thumbnailGenerationFailed)
                }
            }
        }
    }
    
    private func generateDAEThumbnail(model: Model3D, size: CGSize) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                do {
                    // Load DAE using SceneKit
                    let modelURL = try self.getModelURL(model)
                    let scene = try SCNScene(url: modelURL)
                    
                    // Render using SceneKit
                    let imageData = try self.renderSceneKitScene(scene, size: size)
                    
                    continuation.resume(returning: imageData)
                    
                } catch {
                    continuation.resume(throwing: ModelLoadingError.thumbnailGenerationFailed)
                }
            }
        }
    }
    
    private func generateGenericThumbnail(model: Model3D, size: CGSize) async throws -> Data {
        // Generate a placeholder thumbnail for unsupported formats
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                let imageData = self.generatePlaceholderThumbnail(
                    format: model.format,
                    category: model.category,
                    size: size
                )
                continuation.resume(returning: imageData)
            }
        }
    }
    
    private func generateThumbnailWithAngle(model: Model3D, angle: ThumbnailAngle) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                do {
                    let modelURL = try self.getModelURL(model)
                    
                    switch model.format {
                    case .usdz, .reality:
                        let arView = ARView(frame: CGRect(origin: .zero, size: self.thumbnailSize))
                        let entity = try Entity.load(contentsOf: modelURL)
                        self.setupThumbnailScene(arView: arView, entity: entity, angle: angle)
                        let imageData = try self.captureARViewImage(arView)
                        continuation.resume(returning: imageData)
                        
                    case .obj, .dae:
                        let scene = try SCNScene(url: modelURL)
                        let imageData = try self.renderSceneKitScene(scene, size: self.thumbnailSize, angle: angle)
                        continuation.resume(returning: imageData)
                        
                    default:
                        let imageData = self.generatePlaceholderThumbnail(
                            format: model.format,
                            category: model.category,
                            size: self.thumbnailSize
                        )
                        continuation.resume(returning: imageData)
                    }
                    
                } catch {
                    continuation.resume(throwing: ModelLoadingError.thumbnailGenerationFailed)
                }
            }
        }
    }
    
    private func generateRotatingPreview(model: Model3D, duration: TimeInterval) async throws -> Data {
        // Generate multiple frames and create GIF
        let frameCount = 24
        let frameDuration = duration / Double(frameCount)
        var frames: [UIImage] = []
        
        for i in 0..<frameCount {
            let rotation = Float(i) / Float(frameCount) * 2 * Float.pi
            let frame = try await generateFrameWithRotation(model: model, rotation: rotation)
            frames.append(frame)
        }
        
        return try createAnimatedGIF(from: frames, duration: frameDuration)
    }
    
    private func generateAnimationPreview(model: Model3D, duration: TimeInterval) async throws -> Data {
        // This would capture frames from the model's animations
        // For now, fall back to rotating preview
        return try await generateRotatingPreview(model: model, duration: duration)
    }
    
    private func generateFrameWithRotation(model: Model3D, rotation: Float) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                do {
                    let modelURL = try self.getModelURL(model)
                    let arView = ARView(frame: CGRect(origin: .zero, size: self.thumbnailSize))
                    let entity = try Entity.load(contentsOf: modelURL)
                    
                    // Apply rotation
                    entity.transform.rotation = simd_quatf(angle: rotation, axis: [0, 1, 0])
                    
                    self.setupThumbnailScene(arView: arView, entity: entity, angle: .perspective)
                    let imageData = try self.captureARViewImage(arView)
                    
                    guard let image = UIImage(data: imageData) else {
                        throw ModelLoadingError.thumbnailGenerationFailed
                    }
                    
                    continuation.resume(returning: image)
                    
                } catch {
                    continuation.resume(throwing: ModelLoadingError.thumbnailGenerationFailed)
                }
            }
        }
    }
    
    private func setupThumbnailScene(arView: ARView, entity: Entity, angle: ThumbnailAngle) {
        // Calculate bounding box
        let boundingBox = entity.visualBounds(relativeTo: nil)
        let size = boundingBox.max - boundingBox.min
        let maxDimension = max(size.x, max(size.y, size.z))
        
        // Position entity at origin
        entity.position = -boundingBox.center
        
        // Create anchor and add entity
        let anchor = AnchorEntity(world: [0, 0, 0])
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        
        // Setup camera based on angle
        let cameraDistance = maxDimension * self.cameraDistance
        let cameraPosition = getCameraPosition(for: angle, distance: cameraDistance)
        
        // Create camera entity
        let cameraAnchor = AnchorEntity(world: cameraPosition)
        let camera = PerspectiveCamera()
        camera.look(at: [0, 0, 0], from: cameraPosition, relativeTo: nil)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)
        
        // Setup lighting
        setupLighting(in: arView)
    }
    
    private func getCameraPosition(for angle: ThumbnailAngle, distance: Float) -> SIMD3<Float> {
        switch angle {
        case .front:
            return [0, 0, distance]
        case .side:
            return [distance, 0, 0]
        case .top:
            return [0, distance, 0]
        case .perspective:
            return [distance * 0.7, distance * 0.7, distance * 0.7]
        }
    }
    
    private func setupLighting(in arView: ARView) {
        // Add key light
        let keyLight = DirectionalLight()
        keyLight.light.intensity = lightIntensity
        keyLight.position = [2, 2, 2]
        keyLight.look(at: [0, 0, 0], from: keyLight.position, relativeTo: nil)
        
        let keyAnchor = AnchorEntity(world: keyLight.position)
        keyAnchor.addChild(keyLight)
        arView.scene.addAnchor(keyAnchor)
        
        // Add fill light
        let fillLight = DirectionalLight()
        fillLight.light.intensity = lightIntensity * 0.3
        fillLight.position = [-1, 1, 1]
        fillLight.look(at: [0, 0, 0], from: fillLight.position, relativeTo: nil)
        
        let fillAnchor = AnchorEntity(world: fillLight.position)
        fillAnchor.addChild(fillLight)
        arView.scene.addAnchor(fillAnchor)
    }
    
    private func captureARViewImage(_ arView: ARView) throws -> Data {
        // This would capture the ARView content
        // In practice, this requires complex Metal rendering
        // For now, create a placeholder
        return try generatePlaceholderImage(size: arView.frame.size)
    }
    
    private func renderSceneKitScene(_ scene: SCNScene, size: CGSize, angle: ThumbnailAngle = .perspective) throws -> Data {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice())
        renderer.scene = scene
        
        // Setup camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        
        // Position camera based on angle
        let distance: Float = 5.0
        switch angle {
        case .front:
            cameraNode.position = SCNVector3(0, 0, distance)
        case .side:
            cameraNode.position = SCNVector3(distance, 0, 0)
        case .top:
            cameraNode.position = SCNVector3(0, distance, 0)
        case .perspective:
            cameraNode.position = SCNVector3(distance * 0.7, distance * 0.7, distance * 0.7)
        }
        
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)
        
        // Setup lighting
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .directional
        lightNode.position = SCNVector3(2, 2, 2)
        scene.rootNode.addChildNode(lightNode)
        
        // Render
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        
        guard let imageData = image.pngData() else {
            throw ModelLoadingError.thumbnailGenerationFailed
        }
        
        return imageData
    }
    
    private func renderEntityToImage(_ entity: Entity, size: CGSize) throws -> Data {
        // This would render the RealityKit entity to an image
        // Complex implementation involving Metal rendering
        return try generatePlaceholderImage(size: size)
    }
    
    private func generatePlaceholderThumbnail(format: ModelFormat, category: ModelCategory, size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Background
            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Draw format icon
            let iconSize: CGFloat = size.width * 0.4
            let iconRect = CGRect(
                x: (size.width - iconSize) / 2,
                y: (size.height - iconSize) / 2 - 20,
                width: iconSize,
                height: iconSize
            )
            
            // Draw category icon
            UIColor.systemBlue.setFill()
            let iconPath = UIBezierPath(roundedRect: iconRect, cornerRadius: 8)
            iconPath.fill()
            
            // Draw format text
            let text = format.displayName
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.label
            ]
            
            let textSize = text.size(withAttributes: textAttributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: iconRect.maxY + 10,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: textAttributes)
        }
        
        return image.pngData() ?? Data()
    }
    
    private func generatePlaceholderImage(size: CGSize) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            backgroundColor.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        }
        
        guard let data = image.pngData() else {
            throw ModelLoadingError.thumbnailGenerationFailed
        }
        
        return data
    }
    
    private func createAnimatedGIF(from frames: [UIImage], duration: TimeInterval) throws -> Data {
        // This would create an animated GIF from the frames
        // Complex implementation using ImageIO
        
        // For now, return the first frame as PNG
        guard let firstFrame = frames.first,
              let data = firstFrame.pngData() else {
            throw ModelLoadingError.thumbnailGenerationFailed
        }
        
        return data
    }
    
    private func getModelURL(_ model: Model3D) throws -> URL {
        // Get the model file URL
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsURL = documentsURL.appendingPathComponent("Models")
        let fileURL = modelsURL.appendingPathComponent(model.fileName)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        
        // Check bundle
        if let bundleURL = Bundle.main.url(forResource: model.fileName, withExtension: nil) {
            return bundleURL
        }
        
        throw ModelLoadingError.fileNotFound(model.fileName)
    }
    
    private func thumbnailCacheKey(model: Model3D, size: ThumbnailSize) -> String {
        return "\(model.id.uuidString)_\(size.rawValue)"
    }
}

// MARK: - Supporting Types

public enum ThumbnailSize: String, CaseIterable {
    case standard = "standard"
    case large = "large"
    
    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .large: return "Large"
        }
    }
}

public enum ThumbnailAngle: String, CaseIterable {
    case front = "front"
    case side = "side"
    case top = "top"
    case perspective = "perspective"
    
    public var displayName: String {
        return rawValue.capitalized
    }
}

public struct ThumbnailSet {
    public let modelID: UUID
    public let thumbnails: [ThumbnailAngle: Data]
    public let generatedAt: Date
    
    public func thumbnail(for angle: ThumbnailAngle) -> Data? {
        return thumbnails[angle]
    }
    
    public var availableAngles: [ThumbnailAngle] {
        return Array(thumbnails.keys)
    }
}

// MARK: - Thumbnail Cache

public class ThumbnailCache {
    public static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsURL.appendingPathComponent("ThumbnailCache")
        
        // Configure cache
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        
        createCacheDirectory()
    }
    
    private func createCacheDirectory() {
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            logError("Failed to create thumbnail cache directory: \(error)", category: .general)
        }
    }
    
    public func setImage(_ data: Data, for key: String) {
        // Store in memory cache
        cache.setObject(data as NSData, forKey: key as NSString)
        
        // Store in disk cache
        let fileURL = cacheDirectory.appendingPathComponent("\(key).png")
        do {
            try data.write(to: fileURL)
        } catch {
            logError("Failed to cache thumbnail to disk: \(error)", category: .general)
        }
    }
    
    public func getImage(for key: String) -> Data? {
        // Check memory cache first
        if let data = cache.object(forKey: key as NSString) {
            return data as Data
        }
        
        // Check disk cache
        let fileURL = cacheDirectory.appendingPathComponent("\(key).png")
        if let data = try? Data(contentsOf: fileURL) {
            // Store back in memory cache
            cache.setObject(data as NSData, forKey: key as NSString)
            return data
        }
        
        return nil
    }
    
    public func hasImage(for key: String) -> Bool {
        if cache.object(forKey: key as NSString) != nil {
            return true
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(key).png")
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    public func removeImage(for key: String) {
        cache.removeObject(forKey: key as NSString)
        
        let fileURL = cacheDirectory.appendingPathComponent("\(key).png")
        try? fileManager.removeItem(at: fileURL)
    }
    
    public func clearAll() {
        cache.removeAllObjects()
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            logError("Failed to clear thumbnail cache: \(error)", category: .general)
        }
    }
}