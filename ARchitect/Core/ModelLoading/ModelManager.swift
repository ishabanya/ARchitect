import Foundation
import RealityKit
import UIKit
import Combine

// MARK: - Model Manager

@MainActor
public class ModelManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var modelLibrary = ModelLibrary()
    @Published public var isLoading = false
    @Published public var loadingProgress: [UUID: Float] = [:]
    @Published public var errorMessages: [String] = []
    @Published public var memoryUsage: Int64 = 0
    @Published public var cacheSize: Int64 = 0
    
    // MARK: - Private Properties
    private let modelLoader: ModelLoader
    private let progressiveLoader: ProgressiveModelLoader
    private let thumbnailGenerator: ModelThumbnailGenerator
    private let lodGenerator: ModelLODGenerator
    private let persistenceManager: ModelPersistenceManager
    private let errorHandler: ModelErrorHandler
    
    private var cancellables = Set<AnyCancellable>()
    private let initializationQueue = DispatchQueue(label: "model.manager.init", qos: .userInitiated)
    
    // Configuration
    private let maxErrorMessages = 10
    private let backgroundProcessingInterval: TimeInterval = 60.0 // 1 minute
    private var backgroundTimer: Timer?
    
    public init() {
        self.modelLoader = ModelLoader()
        self.progressiveLoader = ProgressiveModelLoader(baseLoader: modelLoader)
        self.thumbnailGenerator = ModelThumbnailGenerator()
        self.lodGenerator = ModelLODGenerator()
        self.persistenceManager = ModelPersistenceManager()
        self.errorHandler = ModelErrorHandler()
        
        setupObservers()
        startBackgroundProcessing()
        
        Task {
            await initialize()
        }
        
        logInfo("Model manager initialized", category: .general)
    }
    
    deinit {
        backgroundTimer?.invalidate()
        logInfo("Model manager deinitialized", category: .general)
    }
    
    // MARK: - Public Methods
    
    /// Initialize the model manager
    public func initialize() async {
        isLoading = true
        
        do {
            // Load model library from persistence
            modelLibrary = try await persistenceManager.loadModelLibrary()
            
            // Generate missing thumbnails in background
            Task {
                await generateMissingThumbnails()
            }
            
            // Generate missing LODs in background
            Task {
                await generateMissingLODs()
            }
            
            updateStatistics()
            
            logInfo("Model manager initialized successfully", category: .general, context: LogContext(customData: [
                "total_models": modelLibrary.allModels.count,
                "collections": modelLibrary.collections.count
            ]))
            
        } catch {
            await handleError(ModelLoadingError.cacheError("Failed to initialize: \(error.localizedDescription)"))
        }
        
        isLoading = false
    }
    
    /// Add a new model to the library
    public func addModel(_ model: Model3D, to collectionID: UUID? = nil) async throws {
        // Validate model file
        try await validateModel(model)
        
        // Generate thumbnail
        if model.thumbnail == nil {
            Task {
                await generateThumbnail(for: model)
            }
        }
        
        // Generate LOD if needed
        if lodGenerator.shouldGenerateLOD(for: model) {
            Task {
                await generateLOD(for: model)
            }
        }
        
        // Add to library
        var updatedModel = model
        updatedModel.isDownloaded = true
        
        if let collectionID = collectionID,
           let collectionIndex = modelLibrary.collections.firstIndex(where: { $0.id == collectionID }) {
            modelLibrary.collections[collectionIndex].models.append(updatedModel)
        } else {
            // Add to default collection
            addToDefaultCollection(updatedModel)
        }
        
        // Save library
        try await persistenceManager.saveModelLibrary(modelLibrary)
        
        updateStatistics()
        
        logInfo("Added model to library", category: .general, context: LogContext(customData: [
            "model_id": model.id.uuidString,
            "model_name": model.name,
            "collection_id": collectionID?.uuidString ?? "default"
        ]))
    }
    
    /// Load a model with progressive loading
    public func loadModel(_ model: Model3D, distance: Float = 5.0) async throws -> Entity {
        // Update recent models
        modelLibrary.addToRecent(model)
        
        // Use progressive loading for complex models
        if model.metadata.complexity.recommendedLOD {
            return try await progressiveLoader.startProgressiveLoading(model, targetDistance: distance)
        } else {
            return try await modelLoader.loadModel(model)
        }
    }
    
    /// Update LOD based on distance
    public func updateModelLOD(_ modelID: UUID, distance: Float) async -> Entity? {
        return await progressiveLoader.updateLODForDistance(modelID, distance: distance)
    }
    
    /// Get model by ID
    public func getModel(_ modelID: UUID) -> Model3D? {
        return modelLibrary.allModels.first { $0.id == modelID }
    }
    
    /// Search models
    public func searchModels(_ query: String) -> [Model3D] {
        return modelLibrary.searchModels(query: query)
    }
    
    /// Get models by category
    public func getModels(in category: ModelCategory) -> [Model3D] {
        return modelLibrary.models(in: category)
    }
    
    /// Toggle favorite status
    public func toggleFavorite(_ modelID: UUID) async {
        modelLibrary.toggleFavorite(modelID)
        
        do {
            try await persistenceManager.saveModelLibrary(modelLibrary)
        } catch {
            await handleError(ModelLoadingError.cacheError("Failed to save favorites"))
        }
    }
    
    /// Delete model
    public func deleteModel(_ modelID: UUID) async throws {
        // Remove from all collections
        for collectionIndex in modelLibrary.collections.indices {
            modelLibrary.collections[collectionIndex].models.removeAll { $0.id == modelID }
        }
        
        // Remove from recents and favorites
        modelLibrary.recentModels.removeAll { $0.id == modelID }
        modelLibrary.favoriteModels.removeAll { $0 == modelID }
        
        // Unload from memory
        modelLoader.unloadModel(modelID)
        progressiveLoader.cancelProgressiveLoading(modelID)
        
        // Delete files
        try await persistenceManager.deleteModelFiles(modelID)
        
        // Save library
        try await persistenceManager.saveModelLibrary(modelLibrary)
        
        updateStatistics()
        
        logInfo("Deleted model", category: .general, context: LogContext(customData: [
            "model_id": modelID.uuidString
        ]))
    }
    
    /// Create new collection
    public func createCollection(_ collection: ModelCollection) async throws {
        modelLibrary.collections.append(collection)
        try await persistenceManager.saveModelLibrary(modelLibrary)
        
        logInfo("Created collection", category: .general, context: LogContext(customData: [
            "collection_id": collection.id.uuidString,
            "collection_name": collection.name
        ]))
    }
    
    /// Import models from URLs
    public func importModels(from urls: [URL]) async throws -> [Model3D] {
        var importedModels: [Model3D] = []
        
        for url in urls {
            do {
                let model = try await importModel(from: url)
                importedModels.append(model)
            } catch {
                await handleError(error as? ModelLoadingError ?? ModelLoadingError.corruptedFile(url.lastPathComponent))
            }
        }
        
        if !importedModels.isEmpty {
            try await persistenceManager.saveModelLibrary(modelLibrary)
            updateStatistics()
        }
        
        return importedModels
    }
    
    /// Export model library
    public func exportLibrary() async throws -> URL {
        return try await persistenceManager.exportLibrary(modelLibrary)
    }
    
    /// Clear all models from memory
    public func clearMemory() {
        modelLoader.clearAllModels()
        
        // Clear progressive loader
        for model in modelLibrary.allModels {
            progressiveLoader.cancelProgressiveLoading(model.id)
        }
        
        updateStatistics()
        
        logInfo("Cleared all models from memory", category: .general)
    }
    
    /// Get loading statistics
    public func getLoadingStatistics() -> ModelStatistics {
        let allModels = modelLibrary.allModels
        let loadedModels = allModels.filter { modelLoader.isModelLoaded($0.id) }.count
        
        var modelsByFormat: [ModelFormat: Int] = [:]
        var modelsByCategory: [ModelCategory: Int] = [:]
        var modelsByComplexity: [ModelComplexity: Int] = [:]
        
        for model in allModels {
            modelsByFormat[model.format, default: 0] += 1
            modelsByCategory[model.category, default: 0] += 1
            modelsByComplexity[model.metadata.complexity, default: 0] += 1
        }
        
        return ModelStatistics(
            totalModels: allModels.count,
            totalFileSize: allModels.reduce(0) { $0 + $1.fileSize },
            totalMemoryUsage: memoryUsage,
            loadedModels: loadedModels,
            modelsByFormat: modelsByFormat,
            modelsByCategory: modelsByCategory,
            modelsByComplexity: modelsByComplexity,
            averageLoadTime: 2.5, // This would be calculated from actual load times
            cacheHitRate: 0.8 // This would be calculated from cache statistics
        )
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observe memory usage from model loader
        modelLoader.$memoryUsage
            .assign(to: \.memoryUsage, on: self)
            .store(in: &cancellables)
        
        // Monitor app lifecycle
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleAppDidEnterBackground()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleAppWillEnterForeground()
                }
            }
            .store(in: &cancellables)
    }
    
    private func startBackgroundProcessing() {
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: backgroundProcessingInterval, repeats: true) { _ in
            Task { @MainActor in
                await self.performBackgroundMaintenance()
            }
        }
    }
    
    private func performBackgroundMaintenance() async {
        // Clean up old thumbnails
        await cleanupOldThumbnails()
        
        // Generate missing LODs
        await generateMissingLODs()
        
        // Update cache statistics
        updateCacheStatistics()
        
        logDebug("Performed background maintenance", category: .general)
    }
    
    private func validateModel(_ model: Model3D) async throws {
        do {
            try errorHandler.validateModel(model)
        } catch {
            throw error
        }
    }
    
    private func importModel(from url: URL) async throws -> Model3D {
        // Extract metadata
        let metadata = try await extractModelMetadata(from: url)
        
        // Create model
        let fileName = url.lastPathComponent
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let format = ModelFormat(rawValue: url.pathExtension.lowercased()) ?? .obj
        
        let model = Model3D(
            name: (fileName as NSString).deletingPathExtension,
            fileName: fileName,
            fileSize: Int64(fileSize),
            format: format,
            metadata: metadata,
            lodLevels: []
        )
        
        // Copy file to models directory
        try await persistenceManager.copyModelFile(from: url, model: model)
        
        // Add to library
        try await addModel(model)
        
        return model
    }
    
    private func extractModelMetadata(from url: URL) async throws -> ModelMetadata {
        // This would analyze the model file to extract metadata
        // For now, return default metadata
        return ModelMetadata(
            triangleCount: 10000,
            vertexCount: 5000,
            materialCount: 1,
            textureCount: 1,
            boundingBox: BoundingBox(
                min: SIMD3<Float>(-1, -1, -1),
                max: SIMD3<Float>(1, 1, 1)
            ),
            complexity: .medium,
            estimatedLoadTime: 2.0
        )
    }
    
    private func generateMissingThumbnails() async {
        let modelsNeedingThumbnails = modelLibrary.allModels.filter { model in
            !thumbnailGenerator.hasCachedThumbnail(for: model)
        }
        
        for model in modelsNeedingThumbnails.prefix(5) { // Process 5 at a time
            await generateThumbnail(for: model)
        }
    }
    
    private func generateThumbnail(for model: Model3D) async {
        do {
            let thumbnailData = try await thumbnailGenerator.generateThumbnail(for: model)
            
            // Update model with thumbnail
            if let modelIndex = findModelIndex(model.id) {
                updateModelThumbnail(at: modelIndex.collection, modelIndex.model, thumbnailData: thumbnailData)
            }
            
        } catch {
            logWarning("Failed to generate thumbnail for \(model.name): \(error)", category: .general)
        }
    }
    
    private func generateMissingLODs() async {
        let modelsNeedingLOD = modelLibrary.allModels.filter { model in
            lodGenerator.shouldGenerateLOD(for: model) && model.lodLevels.isEmpty
        }
        
        for model in modelsNeedingLOD.prefix(2) { // Process 2 at a time (LOD generation is expensive)
            await generateLOD(for: model)
        }
    }
    
    private func generateLOD(for model: Model3D) async {
        do {
            let lodLevels = try await lodGenerator.generateLODLevels(for: model)
            
            // Update model with LOD levels
            if let modelIndex = findModelIndex(model.id) {
                updateModelLODLevels(at: modelIndex.collection, modelIndex.model, lodLevels: lodLevels)
            }
            
        } catch {
            logWarning("Failed to generate LOD for \(model.name): \(error)", category: .general)
        }
    }
    
    private func cleanupOldThumbnails() async {
        // Remove thumbnails for models that no longer exist
        // This would interact with the thumbnail cache
    }
    
    private func updateCacheStatistics() {
        // Calculate cache size
        let cacheURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("ModelCache")
        
        do {
            let resources = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: [.fileSizeKey])
            cacheSize = resources.compactMap { url in
                try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            }.reduce(0, +)
        } catch {
            cacheSize = 0
        }
    }
    
    private func updateStatistics() {
        // Update memory usage and other statistics
        Task {
            updateCacheStatistics()
        }
    }
    
    private func addToDefaultCollection(_ model: Model3D) {
        // Find or create default collection
        if let defaultIndex = modelLibrary.collections.firstIndex(where: { $0.name == "Default" }) {
            modelLibrary.collections[defaultIndex].models.append(model)
        } else {
            let defaultCollection = ModelCollection(
                name: "Default",
                description: "Default model collection",
                models: [model],
                category: model.category
            )
            modelLibrary.collections.append(defaultCollection)
        }
    }
    
    private func findModelIndex(_ modelID: UUID) -> (collection: Int, model: Int)? {
        for (collectionIndex, collection) in modelLibrary.collections.enumerated() {
            if let modelIndex = collection.models.firstIndex(where: { $0.id == modelID }) {
                return (collectionIndex, modelIndex)
            }
        }
        return nil
    }
    
    private func updateModelThumbnail(at collectionIndex: Int, _ modelIndex: Int, thumbnailData: Data) {
        modelLibrary.collections[collectionIndex].models[modelIndex].thumbnail = thumbnailData
        
        Task {
            do {
                try await persistenceManager.saveModelLibrary(modelLibrary)
            } catch {
                await handleError(ModelLoadingError.cacheError("Failed to save thumbnail"))
            }
        }
    }
    
    private func updateModelLODLevels(at collectionIndex: Int, _ modelIndex: Int, lodLevels: [LODLevel]) {
        modelLibrary.collections[collectionIndex].models[modelIndex].lodLevels = lodLevels
        
        Task {
            do {
                try await persistenceManager.saveModelLibrary(modelLibrary)
            } catch {
                await handleError(ModelLoadingError.cacheError("Failed to save LOD levels"))
            }
        }
    }
    
    private func handleError(_ error: ModelLoadingError) async {
        let errorMessage = error.localizedDescription
        
        errorMessages.append(errorMessage)
        
        // Limit error messages
        if errorMessages.count > maxErrorMessages {
            errorMessages.removeFirst(errorMessages.count - maxErrorMessages)
        }
        
        logError("Model manager error: \(errorMessage)", category: .general)
    }
    
    private func handleAppDidEnterBackground() {
        // Save current state
        Task {
            do {
                try await persistenceManager.saveModelLibrary(modelLibrary)
            } catch {
                logError("Failed to save library on background: \(error)", category: .general)
            }
        }
        
        // Clear memory to free resources
        clearMemory()
    }
    
    private func handleAppWillEnterForeground() {
        // Refresh statistics
        updateStatistics()
    }
}

// MARK: - Model Error Handler

public class ModelErrorHandler {
    
    public init() {}
    
    public func validateModel(_ model: Model3D) throws {
        // Validate file name
        if model.fileName.isEmpty {
            throw ModelLoadingError.corruptedFile("Empty file name")
        }
        
        // Validate file size
        if model.fileSize <= 0 {
            throw ModelLoadingError.corruptedFile("Invalid file size")
        }
        
        // Validate format
        if !ModelFormat.allCases.contains(model.format) {
            throw ModelLoadingError.unsupportedFormat(model.format)
        }
        
        // Validate metadata
        if model.metadata.triangleCount <= 0 {
            throw ModelLoadingError.invalidGeometry("Invalid triangle count")
        }
        
        if model.metadata.vertexCount <= 0 {
            throw ModelLoadingError.invalidGeometry("Invalid vertex count")
        }
        
        // Check if file exists
        let fileURL = getModelFileURL(model)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            throw ModelLoadingError.fileNotFound(model.fileName)
        }
    }
    
    private func getModelFileURL(_ model: Model3D) -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Models").appendingPathComponent(model.fileName)
    }
}

// MARK: - Model Persistence Manager

public class ModelPersistenceManager {
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        createDirectories()
    }
    
    private func createDirectories() {
        let urls = [
            getModelsDirectory(),
            getCacheDirectory(),
            getThumbnailDirectory()
        ]
        
        for url in urls {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                logError("Failed to create directory \(url.path): \(error)", category: .general)
            }
        }
    }
    
    public func loadModelLibrary() async throws -> ModelLibrary {
        let libraryURL = getLibraryURL()
        
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            return ModelLibrary() // Return empty library
        }
        
        let data = try Data(contentsOf: libraryURL)
        return try decoder.decode(ModelLibrary.self, from: data)
    }
    
    public func saveModelLibrary(_ library: ModelLibrary) async throws {
        let libraryURL = getLibraryURL()
        let data = try encoder.encode(library)
        try data.write(to: libraryURL)
    }
    
    public func copyModelFile(from sourceURL: URL, model: Model3D) async throws {
        let destinationURL = getModelsDirectory().appendingPathComponent(model.fileName)
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
    
    public func deleteModelFiles(_ modelID: UUID) async throws {
        // This would delete all files associated with the model
        // Including original file, LOD files, thumbnails, etc.
    }
    
    public func exportLibrary(_ library: ModelLibrary) async throws -> URL {
        let exportURL = getDocumentsDirectory().appendingPathComponent("ModelLibraryExport.json")
        let data = try encoder.encode(library)
        try data.write(to: exportURL)
        return exportURL
    }
    
    private func getDocumentsDirectory() -> URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private func getModelsDirectory() -> URL {
        return getDocumentsDirectory().appendingPathComponent("Models")
    }
    
    private func getCacheDirectory() -> URL {
        return getDocumentsDirectory().appendingPathComponent("ModelCache")
    }
    
    private func getThumbnailDirectory() -> URL {
        return getDocumentsDirectory().appendingPathComponent("Thumbnails")
    }
    
    private func getLibraryURL() -> URL {
        return getDocumentsDirectory().appendingPathComponent("ModelLibrary.json")
    }
}