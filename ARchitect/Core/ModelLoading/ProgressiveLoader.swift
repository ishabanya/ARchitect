import Foundation
import RealityKit
import UIKit
import Combine

// MARK: - Progressive Model Loader

@MainActor
public class ProgressiveModelLoader: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var loadingProgress: [UUID: ProgressiveLoadingState] = [:]
    @Published public var loadedLevels: [UUID: [Int: Entity]] = [:]
    
    // MARK: - Private Properties
    private let baseLoader: ModelLoader
    private let lodGenerator: ModelLODGenerator
    private let loadingQueue = DispatchQueue(label: "progressive.loading", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    // Progressive loading configuration
    private let initialLODLevel = 3 // Start with lowest quality
    private let streamingBatchSize = 3
    private let loadingTimeouts: [Int: TimeInterval] = [
        0: 10.0,  // High quality - 10 seconds
        1: 7.0,   // Medium-high - 7 seconds
        2: 5.0,   // Medium - 5 seconds
        3: 3.0    // Low quality - 3 seconds
    ]
    
    public init(baseLoader: ModelLoader) {
        self.baseLoader = baseLoader
        self.lodGenerator = ModelLODGenerator()
        
        logInfo("Progressive model loader initialized", category: .general)
    }
    
    // MARK: - Public Methods
    
    /// Start progressive loading of a model
    public func startProgressiveLoading(_ model: Model3D, targetDistance: Float = 5.0) async throws -> Entity {
        logDebug("Starting progressive loading", category: .general, context: LogContext(customData: [
            "model_id": model.id.uuidString,
            "model_name": model.name,
            "target_distance": targetDistance
        ]))
        
        // Initialize loading state
        let loadingState = ProgressiveLoadingState(
            modelID: model.id,
            currentLevel: -1,
            targetLevel: 0,
            isLoading: true,
            loadedLevels: [],
            error: nil
        )
        loadingProgress[model.id] = loadingState
        
        // Determine optimal initial LOD level
        let initialLevel = determineInitialLODLevel(model: model, distance: targetDistance)
        
        // Load initial LOD level
        let initialEntity = try await loadLODLevel(model, level: initialLevel)
        
        // Update state
        var updatedState = loadingState
        updatedState.currentLevel = initialLevel
        updatedState.loadedLevels.append(initialLevel)
        loadingProgress[model.id] = updatedState
        
        // Store loaded entity
        if loadedLevels[model.id] == nil {
            loadedLevels[model.id] = [:]
        }
        loadedLevels[model.id]?[initialLevel] = initialEntity
        
        // Start background loading of other levels
        Task {
            await loadRemainingLevels(model, currentLevel: initialLevel, targetDistance: targetDistance)
        }
        
        return initialEntity
    }
    
    /// Update LOD level based on distance
    public func updateLODForDistance(_ modelID: UUID, distance: Float) async -> Entity? {
        guard let model = getModelForID(modelID),
              let currentState = loadingProgress[modelID] else {
            return nil
        }
        
        let optimalLevel = determineOptimalLODLevel(model: model, distance: distance)
        
        // If we need a different level
        if optimalLevel != currentState.currentLevel {
            // Check if we have it loaded
            if let entity = loadedLevels[modelID]?[optimalLevel] {
                // Update current level
                var updatedState = currentState
                updatedState.currentLevel = optimalLevel
                loadingProgress[modelID] = updatedState
                
                logDebug("Switched to LOD level \(optimalLevel)", category: .general, context: LogContext(customData: [
                    "model_id": modelID.uuidString,
                    "distance": distance,
                    "lod_level": optimalLevel
                ]))
                
                return entity
            } else if !currentState.loadedLevels.contains(optimalLevel) {
                // Start loading the needed level
                Task {
                    do {
                        if let model = getModelForID(modelID) {
                            _ = try await loadLODLevel(model, level: optimalLevel)
                            
                            // Update available levels
                            var updatedState = currentState
                            updatedState.loadedLevels.append(optimalLevel)
                            updatedState.currentLevel = optimalLevel
                            loadingProgress[modelID] = updatedState
                        }
                    } catch {
                        logError("Failed to load LOD level \(optimalLevel): \(error)", category: .general)
                    }
                }
            }
        }
        
        // Return current best available level
        return getCurrentBestEntity(modelID, targetLevel: optimalLevel)
    }
    
    /// Get current entity for model
    public func getCurrentEntity(_ modelID: UUID) -> Entity? {
        guard let currentState = loadingProgress[modelID],
              currentState.currentLevel >= 0 else {
            return nil
        }
        
        return loadedLevels[modelID]?[currentState.currentLevel]
    }
    
    /// Cancel progressive loading
    public func cancelProgressiveLoading(_ modelID: UUID) {
        loadingProgress.removeValue(forKey: modelID)
        loadedLevels.removeValue(forKey: modelID)
        
        logDebug("Cancelled progressive loading", category: .general, context: LogContext(customData: [
            "model_id": modelID.uuidString
        ]))
    }
    
    /// Get loading statistics
    public func getLoadingStats(_ modelID: UUID) -> ProgressiveLoadingStats? {
        guard let state = loadingProgress[modelID] else { return nil }
        
        let totalLevels = getModelForID(modelID)?.lodLevels.count ?? 0
        let loadedLevels = state.loadedLevels.count
        let completionPercentage = totalLevels > 0 ? Float(loadedLevels) / Float(totalLevels) : 0.0
        
        return ProgressiveLoadingStats(
            modelID: modelID,
            totalLevels: totalLevels,
            loadedLevels: loadedLevels,
            currentLevel: state.currentLevel,
            completionPercentage: completionPercentage,
            isLoading: state.isLoading,
            hasError: state.error != nil
        )
    }
    
    // MARK: - Private Methods
    
    private func loadRemainingLevels(_ model: Model3D, currentLevel: Int, targetDistance: Float) async {
        let allLevels = Array(0..<model.lodLevels.count)
        let remainingLevels = allLevels.filter { $0 != currentLevel }
        
        // Sort by priority (closer to optimal level first)
        let optimalLevel = determineOptimalLODLevel(model: model, distance: targetDistance)
        let sortedLevels = remainingLevels.sorted { abs($0 - optimalLevel) < abs($1 - optimalLevel) }
        
        // Load in batches
        for batch in sortedLevels.chunked(into: streamingBatchSize) {
            await loadLevelBatch(model, levels: batch)
        }
        
        // Mark as fully loaded
        if var state = loadingProgress[model.id] {
            state.isLoading = false
            loadingProgress[model.id] = state
        }
        
        logInfo("Completed progressive loading", category: .general, context: LogContext(customData: [
            "model_id": model.id.uuidString,
            "total_levels": sortedLevels.count + 1
        ]))
    }
    
    private func loadLevelBatch(_ model: Model3D, levels: [Int]) async {
        await withTaskGroup(of: Void.self) { group in
            for level in levels {
                group.addTask {
                    do {
                        _ = try await self.loadLODLevel(model, level: level)
                    } catch {
                        logWarning("Failed to load LOD level \(level): \(error)", category: .general)
                    }
                }
            }
        }
    }
    
    private func loadLODLevel(_ model: Model3D, level: Int) async throws -> Entity {
        guard level < model.lodLevels.count else {
            throw ModelLoadingError.invalidGeometry("Invalid LOD level: \(level)")
        }
        
        let lodLevel = model.lodLevels[level]
        let timeout = loadingTimeouts[level] ?? 10.0
        
        // Load with timeout
        let entity = try await withTimeout(timeout) {
            try await baseLoader.loadModel(model, lodLevel: lodLevel)
        }
        
        // Apply LOD-specific optimizations
        await applyLODOptimizations(entity, level: level, quality: lodLevel.qualityLevel)
        
        // Store in loaded levels
        if loadedLevels[model.id] == nil {
            loadedLevels[model.id] = [:]
        }
        loadedLevels[model.id]?[level] = entity
        
        // Update loading state
        if var state = loadingProgress[model.id] {
            if !state.loadedLevels.contains(level) {
                state.loadedLevels.append(level)
                loadingProgress[model.id] = state
            }
        }
        
        logDebug("Loaded LOD level \(level)", category: .general, context: LogContext(customData: [
            "model_id": model.id.uuidString,
            "level": level,
            "quality": lodLevel.qualityLevel.rawValue,
            "triangle_count": lodLevel.triangleCount
        ]))
        
        return entity
    }
    
    private func applyLODOptimizations(_ entity: Entity, level: Int, quality: LODQuality) async {
        await Task.detached {
            // Apply level-specific optimizations
            switch quality {
            case .minimal, .low:
                // Aggressive optimizations for distant viewing
                self.applyAggressiveOptimizations(entity)
                
            case .medium:
                // Balanced optimizations
                self.applyMediumOptimizations(entity)
                
            case .high, .original:
                // Minimal optimizations to preserve quality
                self.applyMinimalOptimizations(entity)
            }
        }.value
    }
    
    private func applyAggressiveOptimizations(_ entity: Entity) {
        entity.visit { child in
            if var modelComponent = child.components[ModelComponent.self] {
                // Simplify materials
                let simplifiedMaterials = modelComponent.materials.map { _ in
                    SimpleMaterial(color: .white, isMetallic: false)
                }
                modelComponent.materials = simplifiedMaterials
                child.components.set(modelComponent)
            }
        }
    }
    
    private func applyMediumOptimizations(_ entity: Entity) {
        entity.visit { child in
            if var modelComponent = child.components[ModelComponent.self] {
                // Optimize materials while preserving some detail
                let optimizedMaterials = modelComponent.materials.map { material in
                    if let simpleMaterial = material as? SimpleMaterial {
                        return SimpleMaterial(
                            color: simpleMaterial.color.tint,
                            texture: nil, // Remove textures for medium LOD
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
    
    private func applyMinimalOptimizations(_ entity: Entity) {
        // Preserve most detail - only basic optimizations
        entity.visit { child in
            // Enable shadows and proper lighting
            if child.components[ModelComponent.self] != nil {
                child.components.set(GroundingShadowComponent(castsShadow: true))
            }
        }
    }
    
    private func determineInitialLODLevel(model: Model3D, distance: Float) -> Int {
        // Start with a level that loads quickly but provides reasonable quality
        let lodLevels = model.lodLevels.sorted { $0.level < $1.level }
        
        // For very close objects, start with medium quality
        if distance < 2.0 {
            return min(1, lodLevels.count - 1)
        }
        // For medium distance, start with low quality
        else if distance < 5.0 {
            return min(2, lodLevels.count - 1)
        }
        // For far objects, start with minimal quality
        else {
            return min(3, lodLevels.count - 1)
        }
    }
    
    private func determineOptimalLODLevel(model: Model3D, distance: Float) -> Int {
        let lodLevels = model.lodLevels.sorted { $0.maxDistance < $1.maxDistance }
        
        for (index, lod) in lodLevels.enumerated() {
            if distance <= lod.maxDistance {
                return index
            }
        }
        
        // Default to highest quality if very close
        return 0
    }
    
    private func getCurrentBestEntity(_ modelID: UUID, targetLevel: Int) -> Entity? {
        guard let availableLevels = loadedLevels[modelID] else { return nil }
        
        // Try to get exact level
        if let entity = availableLevels[targetLevel] {
            return entity
        }
        
        // Get closest available level
        let sortedLevels = availableLevels.keys.sorted()
        
        // Find closest level (prefer higher quality)
        var bestLevel = sortedLevels.first ?? 0
        var bestDistance = abs(bestLevel - targetLevel)
        
        for level in sortedLevels {
            let distance = abs(level - targetLevel)
            if distance < bestDistance || (distance == bestDistance && level < bestLevel) {
                bestLevel = level
                bestDistance = distance
            }
        }
        
        return availableLevels[bestLevel]
    }
    
    private func getModelForID(_ modelID: UUID) -> Model3D? {
        // In practice, this would lookup the model from a registry
        // For now, return nil - this would be injected from the model manager
        return nil
    }
    
    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ModelLoadingError.networkError("Loading timeout after \(timeout) seconds")
            }
            
            guard let result = try await group.next() else {
                throw ModelLoadingError.networkError("Task group failed")
            }
            
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Progressive Loading State

public struct ProgressiveLoadingState {
    public var modelID: UUID
    public var currentLevel: Int
    public var targetLevel: Int
    public var isLoading: Bool
    public var loadedLevels: [Int]
    public var error: ModelLoadingError?
    
    public var completionPercentage: Float {
        // This would be calculated based on total expected levels
        return loadedLevels.isEmpty ? 0.0 : 1.0
    }
}

// MARK: - Progressive Loading Statistics

public struct ProgressiveLoadingStats {
    public let modelID: UUID
    public let totalLevels: Int
    public let loadedLevels: Int
    public let currentLevel: Int
    public let completionPercentage: Float
    public let isLoading: Bool
    public let hasError: Bool
    
    public var remainingLevels: Int {
        return max(0, totalLevels - loadedLevels)
    }
    
    public var isComplete: Bool {
        return loadedLevels >= totalLevels && !isLoading
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}