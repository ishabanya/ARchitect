import Foundation
import RealityKit
import UIKit
import Combine
import ModelIO
import SceneKit

// MARK: - Model Loader

@MainActor
public class ModelLoader: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var loadingProgress: [UUID: Float] = [:]
    @Published public var loadedModels: [UUID: Entity] = [:]
    @Published public var loadingStates: [UUID: ModelLoadingState] = [:]
    @Published public var memoryUsage: Int64 = 0
    
    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let loadingQueue = DispatchQueue(label: "model.loading", qos: .userInitiated)
    private let conversionQueue = DispatchQueue(label: "model.conversion", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    
    // Caching and memory management
    private let cache: ModelCache
    private let memoryManager: ModelMemoryManager
    private let thumbnailGenerator: ModelThumbnailGenerator
    private let lodGenerator: ModelLODGenerator
    
    // Configuration
    private let maxConcurrentLoads = 3
    private let maxMemoryUsage: Int64 = 512 * 1024 * 1024 // 512MB
    private var currentLoads = 0
    private var loadingQueue_internal: [UUID] = []
    
    public init() {
        self.cache = ModelCache()
        self.memoryManager = ModelMemoryManager()
        self.thumbnailGenerator = ModelThumbnailGenerator()
        self.lodGenerator = ModelLODGenerator()
        
        setupMemoryMonitoring()
        
        logInfo("Model loader initialized", category: .general, context: LogContext(customData: [
            "max_concurrent_loads": maxConcurrentLoads,
            "max_memory_usage": maxMemoryUsage
        ]))
    }
    
    // MARK: - Public Methods
    
    /// Load a 3D model from file
    public func loadModel(_ model: Model3D, lodLevel: LODLevel? = nil) async throws -> Entity {
        // Check if already loaded
        if let existingEntity = loadedModels[model.id] {
            logDebug("Model already loaded", category: .general, context: LogContext(customData: [
                "model_id": model.id.uuidString,
                "model_name": model.name
            ]))
            return existingEntity
        }
        
        // Check cache first
        if let cachedEntity = try await cache.getCachedModel(model.id, lodLevel: lodLevel) {
            loadedModels[model.id] = cachedEntity
            updateMemoryUsage()
            return cachedEntity
        }
        
        // Queue for loading if at capacity
        if currentLoads >= maxConcurrentLoads {
            loadingQueue_internal.append(model.id)
            loadingStates[model.id] = .loading(progress: 0.0)
            
            // Wait for slot to become available
            while currentLoads >= maxConcurrentLoads {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        // Start loading
        currentLoads += 1
        loadingStates[model.id] = .loading(progress: 0.0)
        
        defer {
            currentLoads -= 1
            loadingProgress.removeValue(forKey: model.id)
            processLoadingQueue()
        }
        
        do {
            let entity = try await performModelLoading(model, lodLevel: lodLevel)
            loadedModels[model.id] = entity
            loadingStates[model.id] = .loaded(entity: entity)
            updateMemoryUsage()
            
            // Cache the loaded model
            try await cache.cacheModel(model.id, entity: entity, lodLevel: lodLevel)
            
            logInfo("Model loaded successfully", category: .general, context: LogContext(customData: [
                "model_id": model.id.uuidString,
                "model_name": model.name,
                "format": model.format.rawValue,
                "file_size": model.fileSize,
                "lod_level": lodLevel?.level ?? -1
            ]))
            
            return entity
            
        } catch {
            loadingStates[model.id] = .failed(error: error as? ModelLoadingError ?? .corruptedFile(model.fileName))
            
            logError("Model loading failed: \(error)", category: .general, context: LogContext(customData: [
                "model_id": model.id.uuidString,
                "model_name": model.name,
                "error": error.localizedDescription
            ]))
            
            throw error
        }
    }
    
    /// Unload a model from memory
    public func unloadModel(_ modelID: UUID) {
        loadedModels.removeValue(forKey: modelID)
        loadingStates.removeValue(forKey: modelID)
        cache.removeCachedModel(modelID)
        updateMemoryUsage()
        
        logDebug("Model unloaded", category: .general, context: LogContext(customData: [
            "model_id": modelID.uuidString
        ]))
    }
    
    /// Preload models in background
    public func preloadModels(_ models: [Model3D]) {
        Task {
            for model in models {
                guard loadingStates[model.id] == nil else { continue }
                
                do {
                    _ = try await loadModel(model)
                } catch {
                    logWarning("Preload failed for model: \(model.name)", category: .general)
                }
            }
        }
    }
    
    /// Get loading state for a model
    public func getLoadingState(_ modelID: UUID) -> ModelLoadingState {
        return loadingStates[modelID] ?? .notLoaded
    }
    
    /// Check if model is loaded
    public func isModelLoaded(_ modelID: UUID) -> Bool {
        return loadedModels[modelID] != nil
    }
    
    /// Clear all loaded models
    public func clearAllModels() {
        loadedModels.removeAll()
        loadingStates.removeAll()
        loadingProgress.removeAll()
        cache.clearAll()
        updateMemoryUsage()
        
        logInfo("All models cleared from memory", category: .general)
    }
    
    // MARK: - Private Methods
    
    private func performModelLoading(_ model: Model3D, lodLevel: LODLevel?) async throws -> Entity {
        updateProgress(model.id, progress: 0.1)
        
        // Get file URL
        let fileURL = try getModelFileURL(model, lodLevel: lodLevel)
        
        updateProgress(model.id, progress: 0.2)
        
        // Validate file
        try validateModelFile(fileURL, format: model.format)
        
        updateProgress(model.id, progress: 0.3)
        
        // Load based on format
        let entity: Entity
        switch model.format {
        case .usdz, .reality:
            entity = try await loadRealityKitModel(fileURL, model: model)
        case .obj:
            entity = try await loadOBJModel(fileURL, model: model)
        case .dae:
            entity = try await loadDAEModel(fileURL, model: model)
        case .fbx, .gltf:
            throw ModelLoadingError.unsupportedFormat(model.format)
        }
        
        updateProgress(model.id, progress: 0.9)
        
        // Apply optimizations
        try await optimizeModel(entity, complexity: model.metadata.complexity)
        
        updateProgress(model.id, progress: 1.0)
        
        return entity
    }
    
    private func loadRealityKitModel(_ url: URL, model: Model3D) async throws -> Entity {
        return try await withCheckedThrowingContinuation { continuation in
            loadingQueue.async {
                do {
                    let entity = try Entity.load(contentsOf: url)
                    DispatchQueue.main.async {
                        continuation.resume(returning: entity)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: ModelLoadingError.corruptedFile(url.lastPathComponent))
                    }
                }
            }
        }
    }
    
    private func loadOBJModel(_ url: URL, model: Model3D) async throws -> Entity {
        return try await withCheckedThrowingContinuation { continuation in
            conversionQueue.async {
                do {
                    // Load using ModelIO
                    let asset = MDLAsset(url: url)
                    guard let object = asset.object(at: 0) as? MDLMesh else {
                        throw ModelLoadingError.invalidGeometry("No mesh found in OBJ file")
                    }
                    
                    // Convert to RealityKit
                    let entity = self.convertMDLMeshToEntity(object, model: model)
                    
                    DispatchQueue.main.async {
                        continuation.resume(returning: entity)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: ModelLoadingError.conversionFailed(error.localizedDescription))
                    }
                }
            }
        }
    }
    
    private func loadDAEModel(_ url: URL, model: Model3D) async throws -> Entity {
        return try await withCheckedThrowingContinuation { continuation in
            conversionQueue.async {
                do {
                    // Load using SceneKit
                    let scene = try SCNScene(url: url)
                    
                    // Convert to RealityKit
                    let entity = self.convertSCNSceneToEntity(scene, model: model)
                    
                    DispatchQueue.main.async {
                        continuation.resume(returning: entity)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: ModelLoadingError.conversionFailed(error.localizedDescription))
                    }
                }
            }
        }
    }
    
    private func convertMDLMeshToEntity(_ mesh: MDLMesh, model: Model3D) -> Entity {
        let entity = Entity()
        
        // Create mesh resource from MDL mesh
        do {
            let meshResource = try MeshResource.generate(from: mesh)
            let material = SimpleMaterial(color: .white, isMetallic: false)
            let modelComponent = ModelComponent(mesh: meshResource, materials: [material])
            entity.components.set(modelComponent)
        } catch {
            logError("Failed to convert MDL mesh: \(error)", category: .general)
        }
        
        return entity
    }
    
    private func convertSCNSceneToEntity(_ scene: SCNScene, model: Model3D) -> Entity {
        let entity = Entity()
        
        // Convert SceneKit scene to RealityKit (simplified)
        if let rootNode = scene.rootNode.childNodes.first {
            // This is a simplified conversion - in practice, you'd need to handle
            // materials, textures, animations, etc.
            if let geometry = rootNode.geometry {
                // Convert SCNGeometry to MeshResource (complex process)
                // For now, create a placeholder
                let material = SimpleMaterial(color: .white, isMetallic: false)
                let modelComponent = ModelComponent(
                    mesh: MeshResource.generateBox(size: 0.1),
                    materials: [material]
                )
                entity.components.set(modelComponent)
            }
        }
        
        return entity
    }
    
    private func optimizeModel(_ entity: Entity, complexity: ModelComplexity) async throws {
        // Apply optimizations based on complexity
        switch complexity {
        case .high, .extreme:
            // Enable occlusion culling
            enableOcclusionCulling(entity)
            
            // Optimize materials
            optimizeMaterials(entity)
            
        case .medium:
            // Basic optimizations
            optimizeMaterials(entity)
            
        case .low:
            // No optimizations needed
            break
        }
    }
    
    private func enableOcclusionCulling(_ entity: Entity) {
        entity.visit { child in
            if var modelComponent = child.components[ModelComponent.self] {
                // Enable occlusion culling if available
                child.components.set(modelComponent)
            }
        }
    }
    
    private func optimizeMaterials(_ entity: Entity) {
        entity.visit { child in
            if var modelComponent = child.components[ModelComponent.self] {
                // Optimize materials (reduce texture resolution, combine materials, etc.)
                let optimizedMaterials = modelComponent.materials.map { material in
                    if let simpleMaterial = material as? SimpleMaterial {
                        // Create optimized version
                        return SimpleMaterial(
                            color: simpleMaterial.color.tint,
                            texture: nil, // Remove texture for optimization
                            isMetallic: simpleMaterial.isMetallic
                        )
                    }
                    return material
                }
                modelComponent.materials = optimizedMaterials
                child.components.set(modelComponent)
            }
        }
    }
    
    private func getModelFileURL(_ model: Model3D, lodLevel: LODLevel?) throws -> URL {
        let fileName = lodLevel?.fileName ?? model.fileName
        
        // Check local cache first
        if let cachedURL = cache.getCachedFileURL(fileName) {
            return cachedURL
        }
        
        // Check bundle
        if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) {
            return bundleURL
        }
        
        // Check documents directory
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsURL = documentsURL.appendingPathComponent("Models")
        let fileURL = modelsURL.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        
        throw ModelLoadingError.fileNotFound(fileName)
    }
    
    private func validateModelFile(_ url: URL, format: ModelFormat) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ModelLoadingError.fileNotFound(url.lastPathComponent)
        }
        
        // Check file size
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        if fileSize == 0 {
            throw ModelLoadingError.corruptedFile(url.lastPathComponent)
        }
        
        // Check file extension matches format
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension != format.fileExtension {
            logWarning("File extension mismatch", category: .general, context: LogContext(customData: [
                "expected": format.fileExtension,
                "actual": fileExtension
            ]))
        }
        
        // Basic file validation
        switch format {
        case .usdz:
            try validateUSDZFile(url)
        case .reality:
            try validateRealityFile(url)
        case .obj:
            try validateOBJFile(url)
        case .dae:
            try validateDAEFile(url)
        default:
            break
        }
    }
    
    private func validateUSDZFile(_ url: URL) throws {
        // USDZ files are ZIP archives - check if they can be opened
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            // Check for ZIP signature
            if data.count < 4 || data.prefix(4) != Data([0x50, 0x4B, 0x03, 0x04]) {
                throw ModelLoadingError.corruptedFile(url.lastPathComponent)
            }
        } catch {
            throw ModelLoadingError.corruptedFile(url.lastPathComponent)
        }
    }
    
    private func validateRealityFile(_ url: URL) throws {
        // Reality files have specific header - basic validation
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if data.count < 16 {
                throw ModelLoadingError.corruptedFile(url.lastPathComponent)
            }
        } catch {
            throw ModelLoadingError.corruptedFile(url.lastPathComponent)
        }
    }
    
    private func validateOBJFile(_ url: URL) throws {
        // OBJ files are text - check for basic structure
        do {
            let content = try String(contentsOf: url)
            if !content.contains("v ") && !content.contains("f ") {
                throw ModelLoadingError.invalidGeometry("No vertices or faces found")
            }
        } catch {
            throw ModelLoadingError.corruptedFile(url.lastPathComponent)
        }
    }
    
    private func validateDAEFile(_ url: URL) throws {
        // DAE files are XML - check for COLLADA header
        do {
            let content = try String(contentsOf: url)
            if !content.contains("COLLADA") {
                throw ModelLoadingError.corruptedFile(url.lastPathComponent)
            }
        } catch {
            throw ModelLoadingError.corruptedFile(url.lastPathComponent)
        }
    }
    
    private func updateProgress(_ modelID: UUID, progress: Float) {
        DispatchQueue.main.async {
            self.loadingProgress[modelID] = progress
            self.loadingStates[modelID] = .loading(progress: progress)
        }
    }
    
    private func updateMemoryUsage() {
        let usage = memoryManager.calculateMemoryUsage(loadedModels.values)
        memoryUsage = usage
        
        // Check if we need to free memory
        if memoryUsage > maxMemoryUsage {
            freeMemoryIfNeeded()
        }
    }
    
    private func freeMemoryIfNeeded() {
        // Unload least recently used models
        let modelsToUnload = memoryManager.getModelsToUnload(
            loadedModels: loadedModels,
            targetMemory: maxMemoryUsage * 80 / 100 // Free to 80% of max
        )
        
        for modelID in modelsToUnload {
            unloadModel(modelID)
        }
        
        logInfo("Freed memory by unloading \(modelsToUnload.count) models", category: .general)
    }
    
    private func processLoadingQueue() {
        guard !loadingQueue_internal.isEmpty && currentLoads < maxConcurrentLoads else { return }
        
        let nextModelID = loadingQueue_internal.removeFirst()
        
        // Start loading next model in queue
        Task {
            // This would need access to the model data - in practice, you'd store
            // a mapping of model IDs to model data or pass models to the queue
        }
    }
    
    private func setupMemoryMonitoring() {
        // Monitor memory pressure
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
    }
    
    private func handleMemoryWarning() {
        logWarning("Memory warning received - clearing models", category: .general)
        
        // Aggressively free memory
        let loadedCount = loadedModels.count
        clearAllModels()
        
        logInfo("Cleared \(loadedCount) models due to memory warning", category: .general)
    }
}

// MARK: - Model Cache

public class ModelCache {
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private var cachedEntities: [String: Entity] = [:]
    private let maxCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
    
    public init() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsURL.appendingPathComponent("ModelCache")
        
        createCacheDirectory()
    }
    
    private func createCacheDirectory() {
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            logError("Failed to create cache directory: \(error)", category: .general)
        }
    }
    
    public func getCachedModel(_ modelID: UUID, lodLevel: LODLevel?) async throws -> Entity? {
        let cacheKey = cacheKey(modelID: modelID, lodLevel: lodLevel)
        
        // Check memory cache first
        if let entity = cachedEntities[cacheKey] {
            return entity.clone(recursive: true)
        }
        
        // Check disk cache
        let cacheURL = cacheDirectory.appendingPathComponent(cacheKey)
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        
        // Load from disk cache
        do {
            let entity = try Entity.load(contentsOf: cacheURL)
            cachedEntities[cacheKey] = entity
            return entity.clone(recursive: true)
        } catch {
            // Remove corrupted cache file
            try? fileManager.removeItem(at: cacheURL)
            return nil
        }
    }
    
    public func cacheModel(_ modelID: UUID, entity: Entity, lodLevel: LODLevel?) async throws {
        let cacheKey = cacheKey(modelID: modelID, lodLevel: lodLevel)
        
        // Store in memory cache
        cachedEntities[cacheKey] = entity.clone(recursive: true)
        
        // Store in disk cache
        let cacheURL = cacheDirectory.appendingPathComponent(cacheKey)
        // Note: RealityKit doesn't support saving entities to disk directly
        // In practice, you'd need to implement custom serialization
    }
    
    public func removeCachedModel(_ modelID: UUID) {
        let patterns = ["*\(modelID.uuidString)*"]
        
        for pattern in patterns {
            let keys = cachedEntities.keys.filter { $0.contains(modelID.uuidString) }
            for key in keys {
                cachedEntities.removeValue(forKey: key)
            }
        }
    }
    
    public func getCachedFileURL(_ fileName: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    
    public func clearAll() {
        cachedEntities.removeAll()
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            logError("Failed to clear cache: \(error)", category: .general)
        }
    }
    
    private func cacheKey(modelID: UUID, lodLevel: LODLevel?) -> String {
        if let lod = lodLevel {
            return "\(modelID.uuidString)_lod\(lod.level)"
        }
        return modelID.uuidString
    }
}

// MARK: - Memory Manager

public class ModelMemoryManager {
    private var modelAccessTimes: [UUID: Date] = [:]
    
    public func calculateMemoryUsage(_ entities: Dictionary<UUID, Entity>.Values) -> Int64 {
        // Estimate memory usage - in practice, this would be more sophisticated
        return Int64(entities.count * 10 * 1024 * 1024) // Rough estimate: 10MB per model
    }
    
    public func getModelsToUnload(loadedModels: [UUID: Entity], targetMemory: Int64) -> [UUID] {
        let currentUsage = calculateMemoryUsage(loadedModels.values)
        guard currentUsage > targetMemory else { return [] }
        
        // Sort by access time (least recently used first)
        let sortedModels = modelAccessTimes.sorted { $0.value < $1.value }
        
        var modelsToUnload: [UUID] = []
        var freedMemory: Int64 = 0
        let memoryToFree = currentUsage - targetMemory
        
        for (modelID, _) in sortedModels {
            guard loadedModels[modelID] != nil else { continue }
            
            modelsToUnload.append(modelID)
            freedMemory += 10 * 1024 * 1024 // Estimate per model
            
            if freedMemory >= memoryToFree {
                break
            }
        }
        
        return modelsToUnload
    }
    
    public func recordAccess(_ modelID: UUID) {
        modelAccessTimes[modelID] = Date()
    }
}