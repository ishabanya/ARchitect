import Foundation
import RealityKit
import UIKit
import simd

// MARK: - 3D Model Data Structures

/// Represents a 3D model with metadata and loading state
public struct Model3D: Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let fileName: String
    public let fileSize: Int64
    public let format: ModelFormat
    public let category: ModelCategory
    public let tags: [String]
    public let dateAdded: Date
    public let lastAccessed: Date
    public var isDownloaded: Bool
    public var downloadProgress: Float
    public var thumbnail: Data?
    public let metadata: ModelMetadata
    public let lodLevels: [LODLevel]
    public var memoryFootprint: Int64
    public var isLoaded: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        fileSize: Int64,
        format: ModelFormat,
        category: ModelCategory = .furniture,
        tags: [String] = [],
        dateAdded: Date = Date(),
        lastAccessed: Date = Date(),
        isDownloaded: Bool = false,
        downloadProgress: Float = 0.0,
        thumbnail: Data? = nil,
        metadata: ModelMetadata,
        lodLevels: [LODLevel] = [],
        memoryFootprint: Int64 = 0,
        isLoaded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.fileSize = fileSize
        self.format = format
        self.category = category
        self.tags = tags
        self.dateAdded = dateAdded
        self.lastAccessed = lastAccessed
        self.isDownloaded = isDownloaded
        self.downloadProgress = downloadProgress
        self.thumbnail = thumbnail
        self.metadata = metadata
        self.lodLevels = lodLevels
        self.memoryFootprint = memoryFootprint
        self.isLoaded = isLoaded
    }
    
    /// Get formatted file size string
    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    /// Get formatted memory footprint string
    public var formattedMemoryFootprint: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: memoryFootprint)
    }
    
    /// Check if model supports LOD
    public var supportsLOD: Bool {
        return !lodLevels.isEmpty
    }
    
    /// Get appropriate LOD level based on distance
    public func getLODLevel(for distance: Float) -> LODLevel? {
        let sortedLevels = lodLevels.sorted { $0.maxDistance < $1.maxDistance }
        return sortedLevels.first { distance <= $0.maxDistance }
    }
    
    /// Get thumbnail image
    public var thumbnailImage: UIImage? {
        guard let thumbnailData = thumbnail else { return nil }
        return UIImage(data: thumbnailData)
    }
    
    public static func == (lhs: Model3D, rhs: Model3D) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Supported 3D model formats
public enum ModelFormat: String, CaseIterable, Codable {
    case usdz = "usdz"
    case reality = "reality"
    case obj = "obj"
    case dae = "dae"
    case fbx = "fbx"
    case gltf = "gltf"
    
    public var displayName: String {
        switch self {
        case .usdz: return "USDZ"
        case .reality: return "Reality"
        case .obj: return "OBJ"
        case .dae: return "Collada"
        case .fbx: return "FBX"
        case .gltf: return "glTF"
        }
    }
    
    public var fileExtension: String {
        return rawValue
    }
    
    public var supportedByRealityKit: Bool {
        switch self {
        case .usdz, .reality: return true
        case .obj, .dae, .fbx, .gltf: return false // Require conversion
        }
    }
    
    public var requiresConversion: Bool {
        return !supportedByRealityKit
    }
    
    public var icon: String {
        switch self {
        case .usdz: return "cube.fill"
        case .reality: return "cube.transparent"
        case .obj: return "cube"
        case .dae: return "cube.box"
        case .fbx: return "cube.box.fill"
        case .gltf: return "cube.transparent.fill"
        }
    }
}

/// Model categories for organization
public enum ModelCategory: String, CaseIterable, Codable {
    case furniture = "furniture"
    case decoration = "decoration"
    case lighting = "lighting"
    case appliances = "appliances"
    case plants = "plants"
    case architectural = "architectural"
    case vehicles = "vehicles"
    case people = "people"
    case other = "other"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var icon: String {
        switch self {
        case .furniture: return "chair.fill"
        case .decoration: return "paintbrush.fill"
        case .lighting: return "lightbulb.fill"
        case .appliances: return "tv.fill"
        case .plants: return "leaf.fill"
        case .architectural: return "building.2.fill"
        case .vehicles: return "car.fill"
        case .people: return "person.fill"
        case .other: return "cube.fill"
        }
    }
}

/// Model metadata containing detailed information
public struct ModelMetadata: Codable, Equatable {
    public let triangleCount: Int
    public let vertexCount: Int
    public let materialCount: Int
    public let textureCount: Int
    public let boundingBox: BoundingBox
    public let hasAnimations: Bool
    public let animationNames: [String]
    public let complexity: ModelComplexity
    public let estimatedLoadTime: TimeInterval
    public let recommendedLOD: Bool
    public let author: String?
    public let license: String?
    public let description: String?
    public let version: String?
    
    public init(
        triangleCount: Int,
        vertexCount: Int,
        materialCount: Int,
        textureCount: Int,
        boundingBox: BoundingBox,
        hasAnimations: Bool = false,
        animationNames: [String] = [],
        complexity: ModelComplexity,
        estimatedLoadTime: TimeInterval,
        recommendedLOD: Bool = false,
        author: String? = nil,
        license: String? = nil,
        description: String? = nil,
        version: String? = nil
    ) {
        self.triangleCount = triangleCount
        self.vertexCount = vertexCount
        self.materialCount = materialCount
        self.textureCount = textureCount
        self.boundingBox = boundingBox
        self.hasAnimations = hasAnimations
        self.animationNames = animationNames
        self.complexity = complexity
        self.estimatedLoadTime = estimatedLoadTime
        self.recommendedLOD = recommendedLOD
        self.author = author
        self.license = license
        self.description = description
        self.version = version
    }
}

/// Model complexity levels
public enum ModelComplexity: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case extreme = "extreme"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .extreme: return "red"
        }
    }
    
    public var maxTriangles: Int {
        switch self {
        case .low: return 10000
        case .medium: return 50000
        case .high: return 200000
        case .extreme: return Int.max
        }
    }
    
    public var recommendedLOD: Bool {
        switch self {
        case .low, .medium: return false
        case .high, .extreme: return true
        }
    }
}

/// 3D bounding box
public struct BoundingBox: Codable, Equatable {
    public let min: SIMD3<Float>
    public let max: SIMD3<Float>
    
    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }
    
    public var size: SIMD3<Float> {
        return max - min
    }
    
    public var center: SIMD3<Float> {
        return (min + max) / 2
    }
    
    public var volume: Float {
        let dimensions = size
        return dimensions.x * dimensions.y * dimensions.z
    }
    
    public var largestDimension: Float {
        let dimensions = size
        return max(dimensions.x, max(dimensions.y, dimensions.z))
    }
}

/// Level of Detail configuration
public struct LODLevel: Codable, Identifiable, Equatable {
    public let id: UUID
    public let level: Int
    public let maxDistance: Float
    public let triangleReduction: Float // 0.0 to 1.0
    public let fileName: String?
    public let fileSize: Int64
    public let triangleCount: Int
    public let qualityLevel: LODQuality
    
    public init(
        id: UUID = UUID(),
        level: Int,
        maxDistance: Float,
        triangleReduction: Float,
        fileName: String? = nil,
        fileSize: Int64,
        triangleCount: Int,
        qualityLevel: LODQuality
    ) {
        self.id = id
        self.level = level
        self.maxDistance = maxDistance
        self.triangleReduction = triangleReduction
        self.fileName = fileName
        self.fileSize = fileSize
        self.triangleCount = triangleCount
        self.qualityLevel = qualityLevel
    }
}

/// LOD quality levels
public enum LODQuality: String, CaseIterable, Codable {
    case original = "original"
    case high = "high"
    case medium = "medium"
    case low = "low"
    case minimal = "minimal"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var reductionFactor: Float {
        switch self {
        case .original: return 0.0
        case .high: return 0.25
        case .medium: return 0.5
        case .low: return 0.75
        case .minimal: return 0.9
        }
    }
    
    public var maxDistance: Float {
        switch self {
        case .original: return 2.0
        case .high: return 5.0
        case .medium: return 10.0
        case .low: return 20.0
        case .minimal: return Float.greatestFiniteMagnitude
        }
    }
}

/// Model loading state
public enum ModelLoadingState: Equatable {
    case notLoaded
    case loading(progress: Float)
    case loaded(entity: Entity)
    case failed(error: ModelLoadingError)
    
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
    
    public var hasFailed: Bool {
        if case .failed = self { return true }
        return false
    }
    
    public var loadingProgress: Float {
        if case .loading(let progress) = self { return progress }
        return 0.0
    }
    
    public var loadedEntity: Entity? {
        if case .loaded(let entity) = self { return entity }
        return nil
    }
    
    public var error: ModelLoadingError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// Model loading errors
public enum ModelLoadingError: LocalizedError, Equatable {
    case fileNotFound(String)
    case unsupportedFormat(ModelFormat)
    case corruptedFile(String)
    case invalidGeometry(String)
    case memoryLimitExceeded
    case networkError(String)
    case conversionFailed(String)
    case thumbnailGenerationFailed
    case lodGenerationFailed
    case cacheError(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Model file not found: \(path)"
        case .unsupportedFormat(let format):
            return "Unsupported model format: \(format.displayName)"
        case .corruptedFile(let fileName):
            return "Corrupted model file: \(fileName)"
        case .invalidGeometry(let reason):
            return "Invalid model geometry: \(reason)"
        case .memoryLimitExceeded:
            return "Model exceeds memory limit"
        case .networkError(let message):
            return "Network error: \(message)"
        case .conversionFailed(let reason):
            return "Model conversion failed: \(reason)"
        case .thumbnailGenerationFailed:
            return "Failed to generate model thumbnail"
        case .lodGenerationFailed:
            return "Failed to generate LOD levels"
        case .cacheError(let message):
            return "Cache error: \(message)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Check if the file exists and is accessible"
        case .unsupportedFormat:
            return "Convert the model to a supported format (USDZ or Reality)"
        case .corruptedFile:
            return "Try re-downloading or replacing the model file"
        case .invalidGeometry:
            return "Check the model in a 3D editor and fix geometry issues"
        case .memoryLimitExceeded:
            return "Use a lower quality model or enable LOD"
        case .networkError:
            return "Check your internet connection and try again"
        case .conversionFailed:
            return "Try converting the model with a different tool"
        case .thumbnailGenerationFailed:
            return "Thumbnail will be generated later"
        case .lodGenerationFailed:
            return "LOD optimization will be disabled"
        case .cacheError:
            return "Clear the model cache and try again"
        }
    }
}

/// Model collection for organizing models
public struct ModelCollection: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let models: [Model3D]
    public let category: ModelCategory
    public let tags: [String]
    public let dateCreated: Date
    public let isBuiltIn: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        models: [Model3D] = [],
        category: ModelCategory,
        tags: [String] = [],
        dateCreated: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.models = models
        self.category = category
        self.tags = tags
        self.dateCreated = dateCreated
        self.isBuiltIn = isBuiltIn
    }
    
    public var modelCount: Int {
        return models.count
    }
    
    public var totalFileSize: Int64 {
        return models.reduce(0) { $0 + $1.fileSize }
    }
    
    public var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalFileSize)
    }
}

/// Model library containing all collections and models
public struct ModelLibrary: Codable {
    public var collections: [ModelCollection]
    public var recentModels: [Model3D]
    public var favoriteModels: [UUID]
    public let maxRecentModels: Int
    public let version: String
    
    public init(
        collections: [ModelCollection] = [],
        recentModels: [Model3D] = [],
        favoriteModels: [UUID] = [],
        maxRecentModels: Int = 20,
        version: String = "1.0"
    ) {
        self.collections = collections
        self.recentModels = recentModels
        self.favoriteModels = favoriteModels
        self.maxRecentModels = maxRecentModels
        self.version = version
    }
    
    /// Get all models across all collections
    public var allModels: [Model3D] {
        return collections.flatMap { $0.models }
    }
    
    /// Add model to recent models list
    public mutating func addToRecent(_ model: Model3D) {
        // Remove if already exists
        recentModels.removeAll { $0.id == model.id }
        
        // Add to front
        recentModels.insert(model, at: 0)
        
        // Maintain limit
        if recentModels.count > maxRecentModels {
            recentModels = Array(recentModels.prefix(maxRecentModels))
        }
    }
    
    /// Toggle favorite status
    public mutating func toggleFavorite(_ modelID: UUID) {
        if favoriteModels.contains(modelID) {
            favoriteModels.removeAll { $0 == modelID }
        } else {
            favoriteModels.append(modelID)
        }
    }
    
    /// Check if model is favorite
    public func isFavorite(_ modelID: UUID) -> Bool {
        return favoriteModels.contains(modelID)
    }
    
    /// Search models by name, tags, or category
    public func searchModels(query: String) -> [Model3D] {
        let lowercaseQuery = query.lowercased()
        return allModels.filter { model in
            model.name.lowercased().contains(lowercaseQuery) ||
            model.tags.contains { $0.lowercased().contains(lowercaseQuery) } ||
            model.category.displayName.lowercased().contains(lowercaseQuery)
        }
    }
    
    /// Get models by category
    public func models(in category: ModelCategory) -> [Model3D] {
        return allModels.filter { $0.category == category }
    }
    
    /// Get favorite models
    public var favorites: [Model3D] {
        return allModels.filter { favoriteModels.contains($0.id) }
    }
}

// MARK: - SIMD Extensions for Codable Support

extension SIMD3: Codable where Scalar: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Scalar.self)
        let y = try container.decode(Scalar.self)
        let z = try container.decode(Scalar.self)
        self.init(x, y, z)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
    }
}

// MARK: - Model Statistics

public struct ModelStatistics {
    public let totalModels: Int
    public let totalFileSize: Int64
    public let totalMemoryUsage: Int64
    public let loadedModels: Int
    public let modelsByFormat: [ModelFormat: Int]
    public let modelsByCategory: [ModelCategory: Int]
    public let modelsByComplexity: [ModelComplexity: Int]
    public let averageLoadTime: TimeInterval
    public let cacheHitRate: Float
    
    public var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalFileSize)
    }
    
    public var formattedMemoryUsage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: totalMemoryUsage)
    }
    
    public var memoryEfficiency: Float {
        guard totalFileSize > 0 else { return 0 }
        return Float(totalMemoryUsage) / Float(totalFileSize)
    }
}