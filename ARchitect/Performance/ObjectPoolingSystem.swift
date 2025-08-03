import Foundation
import SceneKit
import RealityKit
import ARKit
import Combine

// MARK: - Object Pooling System for 3D Models

@MainActor
public class ObjectPoolingSystem: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var poolStats: PoolStatistics = PoolStatistics()
    @Published public var isOptimizing: Bool = false
    @Published public var memoryPressure: MemoryPressureLevel = .normal
    
    // MARK: - Pool Storage
    private var sceneKitPools: [String: SCNNodePool] = [:]
    private var realityKitPools: [String: EntityPool] = [:]
    private var meshPools: [String: MeshPool] = [:]
    private var materialPools: [String: MaterialPool] = [:]
    private var texturePools: [String: TexturePool] = [:]
    
    // MARK: - Configuration
    private let maxPoolSize = 50
    private let minPoolSize = 5
    private let cleanupInterval: TimeInterval = 30.0
    private let memoryThreshold: UInt64 = 500 * 1024 * 1024 // 500MB
    
    // MARK: - Private Properties
    private var cleanupTimer: Timer?
    private var memoryMonitor: MemoryMonitor
    private var performanceProfiler: InstrumentsProfiler
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Pool Management
    private let poolQueue = DispatchQueue(label: "com.architectar.objectpool", qos: .userInteractive)
    private var isCleanupInProgress = false
    
    public init(performanceProfiler: InstrumentsProfiler) {
        self.memoryMonitor = MemoryMonitor()
        self.performanceProfiler = performanceProfiler
        
        setupMemoryMonitoring()
        startPeriodicCleanup()
        
        logDebug("Object pooling system initialized", category: .performance)
    }
    
    // MARK: - Setup
    
    private func setupMemoryMonitoring() {
        // Monitor memory pressure
        memoryMonitor.$memoryPressure
            .sink { [weak self] pressure in
                self?.memoryPressure = pressure
                self?.handleMemoryPressureChange(pressure)
            }
            .store(in: &cancellables)
        
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleMemoryWarning()
                }
            }
            .store(in: &cancellables)
    }
    
    private func startPeriodicCleanup() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performPeriodicCleanup()
            }
        }
    }
    
    // MARK: - SceneKit Object Pooling
    
    public func getSceneKitNode(for modelIdentifier: String, modelLoader: @escaping () -> SCNNode?) -> SCNNode? {
        performanceProfiler.beginModelLoading(modelName: modelIdentifier, fileSize: 0)
        let startTime = Date()
        
        defer {
            let loadTime = Date().timeIntervalSince(startTime)
            performanceProfiler.endModelLoading(modelName: modelIdentifier, success: true, loadTime: loadTime)
        }
        
        // Get or create pool
        let pool = getOrCreateSCNPool(for: modelIdentifier)
        
        // Try to get from pool first
        if let pooledNode = pool.checkout() {
            poolStats.incrementCheckouts()
            logDebug("Retrieved SceneKit node from pool", category: .performance, context: LogContext(customData: [
                "model_identifier": modelIdentifier,
                "pool_size": pool.size
            ]))
            return pooledNode
        }
        
        // Create new node if pool is empty
        guard let newNode = modelLoader() else {
            logError("Failed to load SceneKit model", category: .performance, context: LogContext(customData: [
                "model_identifier": modelIdentifier
            ]))
            return nil
        }
        
        // Configure node for pooling
        configureNodeForPooling(newNode, identifier: modelIdentifier)
        
        poolStats.incrementCreations()
        logDebug("Created new SceneKit node", category: .performance, context: LogContext(customData: [
            "model_identifier": modelIdentifier
        ]))
        
        return newNode
    }
    
    public func returnSceneKitNode(_ node: SCNNode, modelIdentifier: String) {
        guard let pool = sceneKitPools[modelIdentifier] else {
            logWarning("No pool found for SceneKit model", category: .performance, context: LogContext(customData: [
                "model_identifier": modelIdentifier
            ]))
            return
        }
        
        // Reset node state
        resetSceneKitNodeState(node)
        
        // Return to pool
        if pool.checkin(node) {
            poolStats.incrementReturns()
            logDebug("Returned SceneKit node to pool", category: .performance, context: LogContext(customData: [
                "model_identifier": modelIdentifier,
                "pool_size": pool.size
            ]))
        }
    }
    
    // MARK: - RealityKit Entity Pooling
    
    public func getRealityKitEntity(for modelIdentifier: String, modelLoader: @escaping () throws -> Entity?) -> Entity? {
        performanceProfiler.beginModelLoading(modelName: modelIdentifier, fileSize: 0)
        let startTime = Date()
        
        defer {
            let loadTime = Date().timeIntervalSince(startTime)
            performanceProfiler.endModelLoading(modelName: modelIdentifier, success: true, loadTime: loadTime)
        }
        
        // Get or create pool
        let pool = getOrCreateEntityPool(for: modelIdentifier)
        
        // Try to get from pool first
        if let pooledEntity = pool.checkout() {
            poolStats.incrementCheckouts()
            logDebug("Retrieved RealityKit entity from pool", category: .performance, context: LogContext(customData: [
                "model_identifier": modelIdentifier,
                "pool_size": pool.size
            ]))
            return pooledEntity
        }
        
        // Create new entity if pool is empty
        do {
            guard let newEntity = try modelLoader() else {
                logError("Failed to load RealityKit entity", category: .performance, context: LogContext(customData: [
                    "model_identifier": modelIdentifier
                ]))
                return nil
            }
            
            // Configure entity for pooling
            configureEntityForPooling(newEntity, identifier: modelIdentifier)
            
            poolStats.incrementCreations()
            logDebug("Created new RealityKit entity", category: .performance, context: LogContext(customData: [
                "model_identifier": modelIdentifier
            ]))
            
            return newEntity
            
        } catch {
            logError("Error loading RealityKit entity", category: .performance, error: error, context: LogContext(customData: [
                "model_identifier": modelIdentifier
            ]))
            return nil
        }
    }
    
    public func returnRealityKitEntity(_ entity: Entity, modelIdentifier: String) {
        guard let pool = realityKitPools[modelIdentifier] else {
            logWarning("No pool found for RealityKit entity", category: .performance, context: LogContext(customData: [
                "model_identifier": modelIdentifier
            ]))
            return
        }
        
        // Reset entity state
        resetRealityKitEntityState(entity)
        
        // Return to pool
        if pool.checkin(entity) {
            poolStats.incrementReturns()
            logDebug("Returned RealityKit entity to pool", category: .performance, context: LogContext(customData: [
                "model_identifier": modelIdentifier,
                "pool_size": pool.size
            ]))
        }
    }
    
    // MARK: - Mesh Pooling
    
    public func getMesh(for identifier: String, meshLoader: @escaping () -> SCNGeometry?) -> SCNGeometry? {
        let pool = getOrCreateMeshPool(for: identifier)
        
        if let pooledMesh = pool.checkout() {
            poolStats.incrementCheckouts()
            return pooledMesh
        }
        
        guard let newMesh = meshLoader() else { return nil }
        
        poolStats.incrementCreations()
        return newMesh
    }
    
    public func returnMesh(_ mesh: SCNGeometry, identifier: String) {
        guard let pool = meshPools[identifier] else { return }
        
        if pool.checkin(mesh) {
            poolStats.incrementReturns()
        }
    }
    
    // MARK: - Material Pooling
    
    public func getMaterial(for identifier: String, materialLoader: @escaping () -> SCNMaterial?) -> SCNMaterial? {
        let pool = getOrCreateMaterialPool(for: identifier)
        
        if let pooledMaterial = pool.checkout() {
            poolStats.incrementCheckouts()
            return pooledMaterial
        }
        
        guard let newMaterial = materialLoader() else { return nil }
        
        poolStats.incrementCreations()
        return newMaterial
    }
    
    public func returnMaterial(_ material: SCNMaterial, identifier: String) {
        guard let pool = materialPools[identifier] else { return }
        
        // Reset material properties
        resetMaterialState(material)
        
        if pool.checkin(material) {
            poolStats.incrementReturns()
        }
    }
    
    // MARK: - Texture Pooling
    
    public func getTexture(for identifier: String, textureLoader: @escaping () -> Any?) -> Any? {
        let pool = getOrCreateTexturePool(for: identifier)
        
        if let pooledTexture = pool.checkout() {
            poolStats.incrementCheckouts()
            return pooledTexture
        }
        
        guard let newTexture = textureLoader() else { return nil }
        
        poolStats.incrementCreations()
        return newTexture
    }
    
    public func returnTexture(_ texture: Any, identifier: String) {
        guard let pool = texturePools[identifier] else { return }
        
        if pool.checkin(texture) {
            poolStats.incrementReturns()
        }
    }
    
    // MARK: - Pool Creation
    
    private func getOrCreateSCNPool(for identifier: String) -> SCNNodePool {
        if let existingPool = sceneKitPools[identifier] {
            return existingPool
        }
        
        let newPool = SCNNodePool(
            identifier: identifier,
            maxSize: maxPoolSize,
            minSize: minPoolSize
        )
        
        sceneKitPools[identifier] = newPool
        updatePoolStats()
        
        logInfo("Created SceneKit node pool", category: .performance, context: LogContext(customData: [
            "identifier": identifier,
            "max_size": maxPoolSize
        ]))
        
        return newPool
    }
    
    private func getOrCreateEntityPool(for identifier: String) -> EntityPool {
        if let existingPool = realityKitPools[identifier] {
            return existingPool
        }
        
        let newPool = EntityPool(
            identifier: identifier,
            maxSize: maxPoolSize,
            minSize: minPoolSize
        )
        
        realityKitPools[identifier] = newPool
        updatePoolStats()
        
        logInfo("Created RealityKit entity pool", category: .performance, context: LogContext(customData: [
            "identifier": identifier,
            "max_size": maxPoolSize
        ]))
        
        return newPool
    }
    
    private func getOrCreateMeshPool(for identifier: String) -> MeshPool {
        if let existingPool = meshPools[identifier] {
            return existingPool
        }
        
        let newPool = MeshPool(
            identifier: identifier,
            maxSize: maxPoolSize,
            minSize: minPoolSize
        )
        
        meshPools[identifier] = newPool
        updatePoolStats()
        
        return newPool
    }
    
    private func getOrCreateMaterialPool(for identifier: String) -> MaterialPool {
        if let existingPool = materialPools[identifier] {
            return existingPool
        }
        
        let newPool = MaterialPool(
            identifier: identifier,
            maxSize: maxPoolSize,
            minSize: minPoolSize
        )
        
        materialPools[identifier] = newPool
        updatePoolStats()
        
        return newPool
    }
    
    private func getOrCreateTexturePool(for identifier: String) -> TexturePool {
        if let existingPool = texturePools[identifier] {
            return existingPool
        }
        
        let newPool = TexturePool(
            identifier: identifier,
            maxSize: maxPoolSize,
            minSize: minPoolSize
        )
        
        texturePools[identifier] = newPool
        updatePoolStats()
        
        return newPool
    }
    
    // MARK: - Object Configuration
    
    private func configureNodeForPooling(_ node: SCNNode, identifier: String) {
        // Add pooling metadata
        node.setValue(identifier, forKey: "poolIdentifier")
        node.setValue(Date(), forKey: "poolCreationTime")
        
        // Optimize for pooling
        node.castsShadow = false // Will be set when needed
        node.categoryBitMask = 0 // Will be set when needed
    }
    
    private func configureEntityForPooling(_ entity: Entity, identifier: String) {
        // Add pooling metadata
        entity.name = "\(identifier)_pooled"
        
        // Optimize for pooling
        entity.isEnabled = false // Will be enabled when needed
    }
    
    // MARK: - Object State Reset
    
    private func resetSceneKitNodeState(_ node: SCNNode) {
        // Reset transform
        node.transform = SCNMatrix4Identity
        node.position = SCNVector3Zero
        node.rotation = SCNVector4Zero
        node.scale = SCNVector3(1, 1, 1)
        
        // Reset visibility and physics
        node.isHidden = false
        node.opacity = 1.0
        node.physicsBody = nil
        
        // Reset animation
        node.removeAllAnimations()
        node.removeAllAudioPlayers()
        
        // Remove from parent
        node.removeFromParentNode()
        
        // Reset category bit mask
        node.categoryBitMask = 0
    }
    
    private func resetRealityKitEntityState(_ entity: Entity) {
        // Reset transform
        entity.transform = Transform.identity
        entity.position = SIMD3<Float>(0, 0, 0)
        entity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        entity.scale = SIMD3<Float>(1, 1, 1)
        
        // Reset state
        entity.isEnabled = false
        entity.isAnchored = false
        
        // Remove from parent
        entity.removeFromParent()
        
        // Remove components that should be reset
        entity.components.removeAll { component in
            // Keep essential components, remove temporary ones
            return !(component is ModelComponent || component is MaterialComponent)
        }
    }
    
    private func resetMaterialState(_ material: SCNMaterial) {
        // Reset material properties to defaults
        material.transparency = 1.0
        material.isDoubleSided = false
        material.fillMode = .fill
        material.cullMode = .back
        material.transparencyMode = .default
        material.locksAmbientWithDiffuse = true
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
    }
    
    // MARK: - Memory Management
    
    private func handleMemoryPressureChange(_ pressure: MemoryPressureLevel) {
        Task {
            await performMemoryOptimization(for: pressure)
        }
    }
    
    private func handleMemoryWarning() async {
        isOptimizing = true
        
        logWarning("Memory warning received, performing aggressive cleanup", category: .performance)
        
        // Aggressive cleanup of all pools
        await performAggressiveCleanup()
        
        // Force garbage collection
        performGarbageCollection()
        
        isOptimizing = false
    }
    
    private func performMemoryOptimization(for pressure: MemoryPressureLevel) async {
        switch pressure {
        case .normal:
            return
            
        case .warning:
            logInfo("Memory pressure warning, performing moderate cleanup", category: .performance)
            await performModerateCleanup()
            
        case .critical:
            logWarning("Critical memory pressure, performing aggressive cleanup", category: .performance)
            await performAggressiveCleanup()
        }
    }
    
    private func performModerateCleanup() async {
        await poolQueue.run {
            // Reduce pool sizes by 25%
            let targetReduction = 0.25
            
            for pool in self.sceneKitPools.values {
                pool.reduceSize(by: targetReduction)
            }
            
            for pool in self.realityKitPools.values {
                pool.reduceSize(by: targetReduction)
            }
            
            for pool in self.meshPools.values {
                pool.reduceSize(by: targetReduction)
            }
            
            for pool in self.materialPools.values {
                pool.reduceSize(by: targetReduction)
            }
            
            for pool in self.texturePools.values {
                pool.reduceSize(by: targetReduction)
            }
        }
        
        updatePoolStats()
        logInfo("Moderate cleanup completed", category: .performance)
    }
    
    private func performAggressiveCleanup() async {
        await poolQueue.run {
            // Clear all pools except minimum size
            for pool in self.sceneKitPools.values {
                pool.clearToMinimum()
            }
            
            for pool in self.realityKitPools.values {
                pool.clearToMinimum()
            }
            
            for pool in self.meshPools.values {
                pool.clearToMinimum()
            }
            
            for pool in self.materialPools.values {
                pool.clearToMinimum()
            }
            
            for pool in self.texturePools.values {
                pool.clearToMinimum()
            }
        }
        
        updatePoolStats()
        logInfo("Aggressive cleanup completed", category: .performance)
    }
    
    private func performPeriodicCleanup() async {
        guard !isCleanupInProgress else { return }
        isCleanupInProgress = true
        
        await poolQueue.run {
            let cutoffTime = Date().addingTimeInterval(-300) // 5 minutes ago
            
            // Clean up unused objects in all pools
            for pool in self.sceneKitPools.values {
                pool.cleanupOldObjects(olderThan: cutoffTime)
            }
            
            for pool in self.realityKitPools.values {
                pool.cleanupOldObjects(olderThan: cutoffTime)
            }
            
            // Remove empty pools
            self.sceneKitPools = self.sceneKitPools.filter { !$1.isEmpty }
            self.realityKitPools = self.realityKitPools.filter { !$1.isEmpty }
            self.meshPools = self.meshPools.filter { !$1.isEmpty }
            self.materialPools = self.materialPools.filter { !$1.isEmpty }
            self.texturePools = self.texturePools.filter { !$1.isEmpty }
        }
        
        updatePoolStats()
        isCleanupInProgress = false
        
        logDebug("Periodic cleanup completed", category: .performance)
    }
    
    private func performGarbageCollection() {
        // Force autoreleasepool drain
        autoreleasepool {
            // Perform operations that might create temporary objects
        }
        
        // Suggest garbage collection (not guaranteed)
        DispatchQueue.global(qos: .utility).async {
            // Perform heavy operations on background queue to trigger cleanup
        }
    }
    
    // MARK: - Statistics
    
    private func updatePoolStats() {
        let totalPools = sceneKitPools.count + realityKitPools.count + meshPools.count + materialPools.count + texturePools.count
        let totalObjects = sceneKitPools.values.map { $0.size }.reduce(0, +) +
                          realityKitPools.values.map { $0.size }.reduce(0, +) +
                          meshPools.values.map { $0.size }.reduce(0, +) +
                          materialPools.values.map { $0.size }.reduce(0, +) +
                          texturePools.values.map { $0.size }.reduce(0, +)
        
        poolStats.updateStats(
            totalPools: totalPools,
            totalObjects: totalObjects,
            memoryUsage: estimateMemoryUsage()
        )
    }
    
    private func estimateMemoryUsage() -> UInt64 {
        // Rough estimation of memory usage
        var totalMemory: UInt64 = 0
        
        // Estimate SceneKit nodes (rough estimate: 10KB per node)
        let scnNodeCount = sceneKitPools.values.map { $0.size }.reduce(0, +)
        totalMemory += UInt64(scnNodeCount * 10 * 1024)
        
        // Estimate RealityKit entities (rough estimate: 15KB per entity)
        let entityCount = realityKitPools.values.map { $0.size }.reduce(0, +)
        totalMemory += UInt64(entityCount * 15 * 1024)
        
        // Add estimates for meshes, materials, and textures
        totalMemory += UInt64(meshPools.values.map { $0.size }.reduce(0, +) * 50 * 1024)
        totalMemory += UInt64(materialPools.values.map { $0.size }.reduce(0, +) * 5 * 1024)
        totalMemory += UInt64(texturePools.values.map { $0.size }.reduce(0, +) * 100 * 1024)
        
        return totalMemory
    }
    
    // MARK: - Public Interface
    
    public func getPoolingStatistics() -> [String: Any] {
        return [
            "scenekit_pools": sceneKitPools.count,
            "realitykit_pools": realityKitPools.count,
            "mesh_pools": meshPools.count,
            "material_pools": materialPools.count,
            "texture_pools": texturePools.count,
            "total_objects": poolStats.totalObjects,
            "memory_usage_mb": Double(poolStats.memoryUsage) / (1024 * 1024),
            "checkouts": poolStats.checkouts,
            "returns": poolStats.returns,
            "creations": poolStats.creations
        ]
    }
    
    public func clearAllPools() {
        sceneKitPools.removeAll()
        realityKitPools.removeAll()
        meshPools.removeAll()
        materialPools.removeAll()
        texturePools.removeAll()
        
        updatePoolStats()
        
        logInfo("All object pools cleared", category: .performance)
    }
    
    public func preloadObjects(identifiers: [String], loader: (String) -> Any?) {
        Task {
            for identifier in identifiers {
                if let object = loader(identifier) {
                    // Preload object into appropriate pool
                    // Implementation would depend on object type
                }
            }
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        clearAllPools()
    }
}

// MARK: - Pool Statistics

public class PoolStatistics: ObservableObject {
    @Published public var totalPools: Int = 0
    @Published public var totalObjects: Int = 0
    @Published public var memoryUsage: UInt64 = 0
    @Published public var checkouts: Int = 0
    @Published public var returns: Int = 0
    @Published public var creations: Int = 0
    
    public func updateStats(totalPools: Int, totalObjects: Int, memoryUsage: UInt64) {
        self.totalPools = totalPools
        self.totalObjects = totalObjects
        self.memoryUsage = memoryUsage
    }
    
    public func incrementCheckouts() {
        checkouts += 1
    }
    
    public func incrementReturns() {
        returns += 1
    }
    
    public func incrementCreations() {
        creations += 1
    }
}

// MARK: - Memory Monitoring

public enum MemoryPressureLevel {
    case normal
    case warning
    case critical
}

@MainActor
public class MemoryMonitor: ObservableObject {
    @Published public var memoryPressure: MemoryPressureLevel = .normal
    @Published public var currentMemoryUsage: UInt64 = 0
    
    private var monitoringTimer: Timer?
    
    public init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkMemoryPressure()
        }
    }
    
    private func checkMemoryPressure() {
        let memoryInfo = getMemoryInfo()
        currentMemoryUsage = memoryInfo.used
        
        // Determine pressure level based on memory usage
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usagePercentage = Double(memoryInfo.used) / Double(totalMemory)
        
        let newPressure: MemoryPressureLevel
        if usagePercentage > 0.9 {
            newPressure = .critical
        } else if usagePercentage > 0.7 {
            newPressure = .warning
        } else {
            newPressure = .normal
        }
        
        if newPressure != memoryPressure {
            memoryPressure = newPressure
        }
    }
    
    private func getMemoryInfo() -> (used: UInt64, available: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let used = UInt64(info.resident_size)
            let total = ProcessInfo.processInfo.physicalMemory
            return (used, total - used)
        }
        
        return (0, 0)
    }
    
    deinit {
        monitoringTimer?.invalidate()
    }
}

// MARK: - Generic Pool Classes

class SCNNodePool {
    private var objects: [SCNNode] = []
    private var creationTimes: [Date] = []
    private let identifier: String
    private let maxSize: Int
    private let minSize: Int
    private let poolQueue = DispatchQueue(label: "scn.pool", qos: .userInteractive)
    
    var size: Int { objects.count }
    var isEmpty: Bool { objects.isEmpty }
    
    init(identifier: String, maxSize: Int, minSize: Int) {
        self.identifier = identifier
        self.maxSize = maxSize
        self.minSize = minSize
    }
    
    func checkout() -> SCNNode? {
        return poolQueue.sync {
            if !objects.isEmpty {
                creationTimes.removeFirst()
                return objects.removeFirst()
            }
            return nil
        }
    }
    
    func checkin(_ object: SCNNode) -> Bool {
        return poolQueue.sync {
            guard objects.count < maxSize else { return false }
            
            objects.append(object)
            creationTimes.append(Date())
            return true
        }
    }
    
    func reduceSize(by percentage: Double) {
        poolQueue.sync {
            let targetCount = max(minSize, Int(Double(objects.count) * (1 - percentage)))
            let removeCount = objects.count - targetCount
            
            if removeCount > 0 {
                objects.removeFirst(removeCount)
                creationTimes.removeFirst(removeCount)
            }
        }
    }
    
    func clearToMinimum() {
        poolQueue.sync {
            let removeCount = max(0, objects.count - minSize)
            if removeCount > 0 {
                objects.removeFirst(removeCount)
                creationTimes.removeFirst(removeCount)
            }
        }
    }
    
    func cleanupOldObjects(olderThan cutoffTime: Date) {
        poolQueue.sync {
            var indicesToRemove: [Int] = []
            
            for (index, creationTime) in creationTimes.enumerated() {
                if creationTime < cutoffTime && objects.count > minSize {
                    indicesToRemove.append(index)
                }
            }
            
            // Remove in reverse order to maintain indices
            for index in indicesToRemove.reversed() {
                objects.remove(at: index)
                creationTimes.remove(at: index)
            }
        }
    }
}

class EntityPool {
    private var objects: [Entity] = []
    private var creationTimes: [Date] = []
    private let identifier: String
    private let maxSize: Int
    private let minSize: Int
    private let poolQueue = DispatchQueue(label: "entity.pool", qos: .userInteractive)
    
    var size: Int { objects.count }
    var isEmpty: Bool { objects.isEmpty }
    
    init(identifier: String, maxSize: Int, minSize: Int) {
        self.identifier = identifier
        self.maxSize = maxSize
        self.minSize = minSize
    }
    
    func checkout() -> Entity? {
        return poolQueue.sync {
            if !objects.isEmpty {
                creationTimes.removeFirst()
                return objects.removeFirst()
            }
            return nil
        }
    }
    
    func checkin(_ object: Entity) -> Bool {
        return poolQueue.sync {
            guard objects.count < maxSize else { return false }
            
            objects.append(object)
            creationTimes.append(Date())
            return true
        }
    }
    
    func reduceSize(by percentage: Double) {
        poolQueue.sync {
            let targetCount = max(minSize, Int(Double(objects.count) * (1 - percentage)))
            let removeCount = objects.count - targetCount
            
            if removeCount > 0 {
                objects.removeFirst(removeCount)
                creationTimes.removeFirst(removeCount)
            }
        }
    }
    
    func clearToMinimum() {
        poolQueue.sync {
            let removeCount = max(0, objects.count - minSize)
            if removeCount > 0 {
                objects.removeFirst(removeCount)
                creationTimes.removeFirst(removeCount)
            }
        }
    }
    
    func cleanupOldObjects(olderThan cutoffTime: Date) {
        poolQueue.sync {
            var indicesToRemove: [Int] = []
            
            for (index, creationTime) in creationTimes.enumerated() {
                if creationTime < cutoffTime && objects.count > minSize {
                    indicesToRemove.append(index)
                }
            }
            
            for index in indicesToRemove.reversed() {
                objects.remove(at: index)
                creationTimes.remove(at: index)
            }
        }
    }
}

// Similar pool classes for other types
class MeshPool {
    private var objects: [SCNGeometry] = []
    private let identifier: String
    private let maxSize: Int
    private let minSize: Int
    
    var size: Int { objects.count }
    var isEmpty: Bool { objects.isEmpty }
    
    init(identifier: String, maxSize: Int, minSize: Int) {
        self.identifier = identifier
        self.maxSize = maxSize
        self.minSize = minSize
    }
    
    func checkout() -> SCNGeometry? {
        return objects.isEmpty ? nil : objects.removeFirst()
    }
    
    func checkin(_ object: SCNGeometry) -> Bool {
        guard objects.count < maxSize else { return false }
        objects.append(object)
        return true
    }
    
    func reduceSize(by percentage: Double) {
        let targetCount = max(minSize, Int(Double(objects.count) * (1 - percentage)))
        let removeCount = objects.count - targetCount
        if removeCount > 0 {
            objects.removeFirst(removeCount)
        }
    }
    
    func clearToMinimum() {
        let removeCount = max(0, objects.count - minSize)
        if removeCount > 0 {
            objects.removeFirst(removeCount)
        }
    }
}

class MaterialPool {
    private var objects: [SCNMaterial] = []
    private let identifier: String
    private let maxSize: Int
    private let minSize: Int
    
    var size: Int { objects.count }
    var isEmpty: Bool { objects.isEmpty }
    
    init(identifier: String, maxSize: Int, minSize: Int) {
        self.identifier = identifier
        self.maxSize = maxSize
        self.minSize = minSize
    }
    
    func checkout() -> SCNMaterial? {
        return objects.isEmpty ? nil : objects.removeFirst()
    }
    
    func checkin(_ object: SCNMaterial) -> Bool {
        guard objects.count < maxSize else { return false }
        objects.append(object)
        return true
    }
    
    func reduceSize(by percentage: Double) {
        let targetCount = max(minSize, Int(Double(objects.count) * (1 - percentage)))
        let removeCount = objects.count - targetCount
        if removeCount > 0 {
            objects.removeFirst(removeCount)
        }
    }
    
    func clearToMinimum() {
        let removeCount = max(0, objects.count - minSize)
        if removeCount > 0 {
            objects.removeFirst(removeCount)
        }
    }
}

class TexturePool {
    private var objects: [Any] = []
    private let identifier: String
    private let maxSize: Int
    private let minSize: Int
    
    var size: Int { objects.count }
    var isEmpty: Bool { objects.isEmpty }
    
    init(identifier: String, maxSize: Int, minSize: Int) {
        self.identifier = identifier
        self.maxSize = maxSize
        self.minSize = minSize
    }
    
    func checkout() -> Any? {
        return objects.isEmpty ? nil : objects.removeFirst()
    }
    
    func checkin(_ object: Any) -> Bool {
        guard objects.count < maxSize else { return false }
        objects.append(object)
        return true
    }
    
    func reduceSize(by percentage: Double) {
        let targetCount = max(minSize, Int(Double(objects.count) * (1 - percentage)))
        let removeCount = objects.count - targetCount
        if removeCount > 0 {
            objects.removeFirst(removeCount)
        }
    }
    
    func clearToMinimum() {
        let removeCount = max(0, objects.count - minSize)
        if removeCount > 0 {
            objects.removeFirst(removeCount)
        }
    }
}

// Extensions for dispatch queue async operations
extension DispatchQueue {
    func run<T>(_ block: @escaping () throws -> T) async rethrows -> T {
        return try await withCheckedThrowingContinuation { continuation in
            self.async {
                do {
                    let result = try block()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}