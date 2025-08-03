import Foundation
import ARKit
import RealityKit
import simd

// MARK: - Room Analysis Engine

@MainActor
public class RoomAnalysisEngine: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var analysisState: AnalysisState = .idle
    @Published public var roomDimensions: RoomDimensions?
    @Published public var roomShape: RoomShape?
    @Published public var analysisProgress: Double = 0.0
    @Published public var analysisResults: RoomAnalysisResults?
    
    // MARK: - Private Properties
    private var meshAnalyzer: MeshAnalyzer
    private var geometryProcessor: GeometryProcessor
    private var spatialAnalyzer: SpatialAnalyzer
    private let analysisQueue = DispatchQueue(label: "room.analysis", qos: .userInitiated)
    
    // MARK: - Dependencies
    private let hapticFeedback = HapticFeedbackManager.shared
    private let accessibilityManager = AccessibilityManager.shared
    
    public init() {
        self.meshAnalyzer = MeshAnalyzer()
        self.geometryProcessor = GeometryProcessor()
        self.spatialAnalyzer = SpatialAnalyzer()
        
        logDebug("Room analysis engine initialized", category: .general)
    }
    
    // MARK: - Analysis States
    
    public enum AnalysisState {
        case idle
        case scanning
        case processing
        case analyzing
        case completed
        case failed(Error)
        
        var description: String {
            switch self {
            case .idle: return "Ready to analyze"
            case .scanning: return "Scanning room..."
            case .processing: return "Processing mesh data..."
            case .analyzing: return "Analyzing room layout..."
            case .completed: return "Analysis complete"
            case .failed(let error): return "Analysis failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Room Analysis
    
    public func analyzeRoom(from arSession: ARSession) async throws {
        analysisState = .scanning
        analysisProgress = 0.0
        
        do {
            // Step 1: Extract mesh data from AR session
            analysisState = .scanning
            let meshData = try await extractMeshData(from: arSession)
            analysisProgress = 0.2
            
            // Step 2: Process geometry
            analysisState = .processing
            let processedGeometry = try await geometryProcessor.processGeometry(meshData)
            analysisProgress = 0.4
            
            // Step 3: Analyze room dimensions
            let dimensions = try await analyzeDimensions(from: processedGeometry)
            roomDimensions = dimensions
            analysisProgress = 0.6
            
            // Step 4: Determine room shape
            let shape = try await analyzeShape(from: processedGeometry)
            roomShape = shape
            analysisProgress = 0.8
            
            // Step 5: Perform spatial analysis
            analysisState = .analyzing
            let spatialResults = try await spatialAnalyzer.analyzeSpatialFeatures(
                geometry: processedGeometry,
                dimensions: dimensions,
                shape: shape
            )
            analysisProgress = 1.0
            
            // Compile final results
            let results = RoomAnalysisResults(
                dimensions: dimensions,
                shape: shape,
                spatialFeatures: spatialResults,
                confidence: calculateConfidence(
                    meshQuality: meshData.quality,
                    geometryComplexity: processedGeometry.complexity,
                    analysisAccuracy: spatialResults.accuracy
                ),
                timestamp: Date()
            )
            
            analysisResults = results
            analysisState = .completed
            
            hapticFeedback.operationSuccess()
            accessibilityManager.announceSuccess("Room analysis completed successfully")
            
            logInfo("Room analysis completed", category: .general, context: LogContext(customData: [
                "room_area": dimensions.area,
                "room_shape": shape.type.rawValue,
                "analysis_confidence": results.confidence
            ]))
            
        } catch {
            analysisState = .failed(error)
            hapticFeedback.operationError()
            accessibilityManager.announceError("Room analysis failed")
            
            logError("Room analysis failed", category: .general, error: error)
            throw error
        }
    }
    
    // MARK: - Mesh Data Extraction
    
    private func extractMeshData(from arSession: ARSession) async throws -> MeshData {
        return try await withCheckedThrowingContinuation { continuation in
            analysisQueue.async {
                do {
                    let meshData = try self.meshAnalyzer.extractMeshFromSession(arSession)
                    continuation.resume(returning: meshData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Dimension Analysis
    
    private func analyzeDimensions(from geometry: ProcessedGeometry) async throws -> RoomDimensions {
        return try await withCheckedThrowingContinuation { continuation in
            analysisQueue.async {
                do {
                    let bounds = geometry.calculateBounds()
                    let floorPlane = try geometry.extractFloorPlane()
                    let ceilingHeight = try geometry.calculateCeilingHeight()
                    
                    let dimensions = RoomDimensions(
                        width: bounds.width,
                        length: bounds.length,
                        height: ceilingHeight,
                        area: bounds.width * bounds.length,
                        volume: bounds.width * bounds.length * ceilingHeight,
                        floorBounds: floorPlane.bounds,
                        usableArea: self.calculateUsableArea(from: floorPlane, bounds: bounds)
                    )
                    
                    continuation.resume(returning: dimensions)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Shape Analysis
    
    private func analyzeShape(from geometry: ProcessedGeometry) async throws -> RoomShape {
        return try await withCheckedThrowingContinuation { continuation in
            analysisQueue.async {
                do {
                    let corners = try geometry.detectCorners()
                    let walls = try geometry.extractWalls()
                    let doorways = try geometry.detectDoorways()
                    let windows = try geometry.detectWindows()
                    
                    let shapeType = self.classifyRoomShape(corners: corners, walls: walls)
                    let complexity = self.calculateShapeComplexity(corners: corners, walls: walls)
                    
                    let roomShape = RoomShape(
                        type: shapeType,
                        corners: corners,
                        walls: walls,
                        doorways: doorways,
                        windows: windows,
                        complexity: complexity,
                        symmetry: self.calculateSymmetry(corners: corners),
                        irregularities: self.detectIrregularities(walls: walls)
                    )
                    
                    continuation.resume(returning: roomShape)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateUsableArea(from floorPlane: FloorPlane, bounds: RoomBounds) -> Float {
        // Calculate area excluding permanent fixtures and obstacles
        let totalArea = bounds.width * bounds.length
        let obstacleArea = floorPlane.obstacles.reduce(0) { $0 + $1.area }
        return max(0, totalArea - obstacleArea)
    }
    
    private func classifyRoomShape(corners: [RoomCorner], walls: [Wall]) -> RoomShapeType {
        let cornerCount = corners.count
        let wallCount = walls.count
        
        switch cornerCount {
        case 4:
            if isRectangular(corners: corners) {
                return isSquare(corners: corners) ? .square : .rectangular
            } else {
                return .irregular
            }
        case 6:
            return .lShaped
        case 8:
            return .uShaped
        default:
            if cornerCount < 4 {
                return .triangular
            } else {
                return .irregular
            }
        }
    }
    
    private func isRectangular(corners: [RoomCorner]) -> Bool {
        guard corners.count == 4 else { return false }
        
        let angles = corners.map { $0.angle }
        let rightAngles = angles.filter { abs($0 - .pi/2) < 0.1 }
        return rightAngles.count >= 3
    }
    
    private func isSquare(corners: [RoomCorner]) -> Bool {
        guard isRectangular(corners: corners) else { return false }
        
        let sides = calculateSideLengths(corners: corners)
        let averageLength = sides.reduce(0, +) / Float(sides.count)
        let variance = sides.map { pow($0 - averageLength, 2) }.reduce(0, +) / Float(sides.count)
        
        return sqrt(variance) < 0.3 // Within 30cm tolerance
    }
    
    private func calculateSideLengths(corners: [RoomCorner]) -> [Float] {
        var lengths: [Float] = []
        for i in 0..<corners.count {
            let nextIndex = (i + 1) % corners.count
            let distance = simd_distance(corners[i].position, corners[nextIndex].position)
            lengths.append(distance)
        }
        return lengths
    }
    
    private func calculateShapeComplexity(corners: [RoomCorner], walls: [Wall]) -> ShapeComplexity {
        let cornerCount = corners.count
        let wallCount = walls.count
        let irregularCorners = corners.filter { abs($0.angle - .pi/2) > 0.2 }.count
        
        if cornerCount <= 4 && irregularCorners == 0 {
            return .simple
        } else if cornerCount <= 6 && irregularCorners <= 2 {
            return .moderate
        } else {
            return .complex
        }
    }
    
    private func calculateSymmetry(corners: [RoomCorner]) -> Float {
        // Simplified symmetry calculation
        // In a real implementation, this would analyze geometric symmetry
        guard corners.count >= 4 else { return 0.0 }
        
        let center = corners.reduce(SIMD3<Float>.zero) { $0 + $1.position } / Float(corners.count)
        let distances = corners.map { simd_distance($0.position, center) }
        let averageDistance = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.map { pow($0 - averageDistance, 2) }.reduce(0, +) / Float(distances.count)
        
        return max(0, 1.0 - sqrt(variance) / averageDistance)
    }
    
    private func detectIrregularities(walls: [Wall]) -> [Irregularity] {
        var irregularities: [Irregularity] = []
        
        for wall in walls {
            // Check for non-straight walls
            if wall.curvature > 0.1 {
                irregularities.append(Irregularity(
                    type: .curvedWall,
                    position: wall.centerPoint,
                    severity: wall.curvature,
                    description: "Wall has significant curvature"
                ))
            }
            
            // Check for angled walls
            if abs(wall.angle) > 0.1 {
                irregularities.append(Irregularity(
                    type: .angledWall,
                    position: wall.centerPoint,
                    severity: abs(wall.angle),
                    description: "Wall is not perpendicular"
                ))
            }
        }
        
        return irregularities
    }
    
    private func calculateConfidence(
        meshQuality: Float,
        geometryComplexity: Float,
        analysisAccuracy: Float
    ) -> Float {
        let weights: [Float] = [0.4, 0.3, 0.3]
        let scores = [meshQuality, 1.0 - geometryComplexity, analysisAccuracy]
        
        return zip(weights, scores).map(*).reduce(0, +)
    }
    
    // MARK: - Public Analysis Methods
    
    public func getRoomCharacteristics() -> RoomCharacteristics? {
        guard let dimensions = roomDimensions,
              let shape = roomShape else { return nil }
        
        return RoomCharacteristics(
            size: classifyRoomSize(area: dimensions.area),
            proportions: calculateProportions(dimensions: dimensions),
            shape: shape.type,
            complexity: shape.complexity,
            accessibility: assessAccessibility(shape: shape),
            naturalFeatures: identifyNaturalFeatures(shape: shape)
        )
    }
    
    private func classifyRoomSize(area: Float) -> RoomSize {
        switch area {
        case 0..<10: return .small
        case 10..<25: return .medium
        case 25..<50: return .large
        default: return .extraLarge
        }
    }
    
    private func calculateProportions(dimensions: RoomDimensions) -> RoomProportions {
        let aspectRatio = dimensions.width / dimensions.length
        let heightRatio = dimensions.height / max(dimensions.width, dimensions.length)
        
        return RoomProportions(
            aspectRatio: aspectRatio,
            heightRatio: heightRatio,
            isWellProportioned: aspectRatio > 0.6 && aspectRatio < 1.67 && heightRatio > 0.4
        )
    }
    
    private func assessAccessibility(shape: RoomShape) -> AccessibilityFeatures {
        let clearPathways = shape.doorways.count >= 1
        let wheelchairAccessible = shape.doorways.allSatisfy { $0.width >= 0.81 } // 32 inches minimum
        let hasObstacles = !shape.walls.allSatisfy { $0.obstacles.isEmpty }
        
        return AccessibilityFeatures(
            clearPathways: clearPathways,
            wheelchairAccessible: wheelchairAccessible,
            hasObstacles: hasObstacles,
            minimumClearance: calculateMinimumClearance(shape: shape)
        )
    }
    
    private func identifyNaturalFeatures(shape: RoomShape) -> [NaturalFeature] {
        var features: [NaturalFeature] = []
        
        // Windows for natural light
        for window in shape.windows {
            features.append(NaturalFeature(
                type: .window,
                position: window.position,
                size: window.size,
                orientation: window.orientation,
                impact: .lighting
            ))
        }
        
        // Architectural features
        for wall in shape.walls {
            if wall.hasArchitecturalFeatures {
                features.append(NaturalFeature(
                    type: .architecturalFeature,
                    position: wall.centerPoint,
                    size: SIMD2<Float>(wall.length, wall.height),
                    orientation: wall.orientation,
                    impact: .aesthetic
                ))
            }
        }
        
        return features
    }
    
    private func calculateMinimumClearance(shape: RoomShape) -> Float {
        // Calculate the narrowest passable area in the room
        var minClearance: Float = Float.greatestFiniteMagnitude
        
        // Check doorway clearances
        for doorway in shape.doorways {
            minClearance = min(minClearance, doorway.width)
        }
        
        // Check corridor clearances between obstacles
        // This would involve more complex spatial analysis in a real implementation
        
        return minClearance == Float.greatestFiniteMagnitude ? 0.0 : minClearance
    }
}

// MARK: - Supporting Data Structures

public struct RoomDimensions {
    public let width: Float
    public let length: Float
    public let height: Float
    public let area: Float
    public let volume: Float
    public let floorBounds: RoomBounds
    public let usableArea: Float
    
    public var aspectRatio: Float {
        return width / length
    }
    
    public var isSquare: Bool {
        return abs(aspectRatio - 1.0) < 0.1
    }
}

public struct RoomShape {
    public let type: RoomShapeType
    public let corners: [RoomCorner]
    public let walls: [Wall]
    public let doorways: [Doorway]
    public let windows: [Window]
    public let complexity: ShapeComplexity
    public let symmetry: Float
    public let irregularities: [Irregularity]
}

public enum RoomShapeType: String, CaseIterable {
    case rectangular = "Rectangular"
    case square = "Square"
    case lShaped = "L-Shaped"
    case uShaped = "U-Shaped"
    case triangular = "Triangular"
    case circular = "Circular"
    case irregular = "Irregular"
    
    public var description: String {
        return rawValue
    }
    
    public var layoutComplexity: Float {
        switch self {
        case .square, .rectangular: return 0.2
        case .lShaped: return 0.5
        case .uShaped: return 0.7
        case .triangular: return 0.6
        case .circular: return 0.4
        case .irregular: return 0.9
        }
    }
}

public enum ShapeComplexity: String, CaseIterable {
    case simple = "Simple"
    case moderate = "Moderate"
    case complex = "Complex"
    
    public var multiplier: Float {
        switch self {
        case .simple: return 1.0
        case .moderate: return 1.3
        case .complex: return 1.7
        }
    }
}

public struct RoomCorner {
    public let position: SIMD3<Float>
    public let angle: Float
    public let isRightAngle: Bool
    
    public init(position: SIMD3<Float>, angle: Float) {
        self.position = position
        self.angle = angle
        self.isRightAngle = abs(angle - .pi/2) < 0.1
    }
}

public struct Wall {
    public let startPoint: SIMD3<Float>
    public let endPoint: SIMD3<Float>
    public let centerPoint: SIMD3<Float>
    public let length: Float
    public let height: Float
    public let orientation: Float
    public let curvature: Float
    public let angle: Float
    public let obstacles: [Obstacle]
    public let hasArchitecturalFeatures: Bool
    
    public init(
        startPoint: SIMD3<Float>,
        endPoint: SIMD3<Float>,
        height: Float,
        curvature: Float = 0.0,
        angle: Float = 0.0,
        obstacles: [Obstacle] = [],
        hasArchitecturalFeatures: Bool = false
    ) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.centerPoint = (startPoint + endPoint) / 2
        self.length = simd_distance(startPoint, endPoint)
        self.height = height
        self.orientation = atan2(endPoint.z - startPoint.z, endPoint.x - startPoint.x)
        self.curvature = curvature
        self.angle = angle
        self.obstacles = obstacles
        self.hasArchitecturalFeatures = hasArchitecturalFeatures
    }
}

public struct Doorway {
    public let position: SIMD3<Float>
    public let width: Float
    public let height: Float
    public let orientation: Float
    public let isMainEntrance: Bool
    
    public init(position: SIMD3<Float>, width: Float, height: Float, orientation: Float, isMainEntrance: Bool = false) {
        self.position = position
        self.width = width
        self.height = height
        self.orientation = orientation
        self.isMainEntrance = isMainEntrance
    }
}

public struct Window {
    public let position: SIMD3<Float>
    public let size: SIMD2<Float>
    public let orientation: Float
    public let lightDirection: SIMD3<Float>
    public let estimatedLightIntensity: Float
    
    public init(position: SIMD3<Float>, size: SIMD2<Float>, orientation: Float, lightDirection: SIMD3<Float>, estimatedLightIntensity: Float = 1000.0) {
        self.position = position
        self.size = size
        self.orientation = orientation
        self.lightDirection = lightDirection
        self.estimatedLightIntensity = estimatedLightIntensity
    }
}

public struct Obstacle {
    public let position: SIMD3<Float>
    public let bounds: RoomBounds
    public let type: ObstacleType
    public let isMovable: Bool
    public let area: Float
    
    public init(position: SIMD3<Float>, bounds: RoomBounds, type: ObstacleType, isMovable: Bool = false) {
        self.position = position
        self.bounds = bounds
        self.type = type
        self.isMovable = isMovable
        self.area = bounds.width * bounds.length
    }
}

public enum ObstacleType: String, CaseIterable {
    case column = "Column"
    case fixture = "Fixture"
    case builtin = "Built-in"
    case temporary = "Temporary"
}

public struct Irregularity {
    public let type: IrregularityType
    public let position: SIMD3<Float>
    public let severity: Float
    public let description: String
}

public enum IrregularityType: String, CaseIterable {
    case curvedWall = "Curved Wall"
    case angledWall = "Angled Wall"
    case unevenFloor = "Uneven Floor"
    case lowCeiling = "Low Ceiling"
    case narrowPassage = "Narrow Passage"
}

public struct RoomBounds {
    public let minX: Float
    public let maxX: Float
    public let minZ: Float
    public let maxZ: Float
    
    public var width: Float { maxX - minX }
    public var length: Float { maxZ - minZ }
    public var center: SIMD2<Float> { SIMD2((minX + maxX) / 2, (minZ + maxZ) / 2) }
}

public struct RoomAnalysisResults {
    public let dimensions: RoomDimensions
    public let shape: RoomShape
    public let spatialFeatures: SpatialAnalysisResults
    public let confidence: Float
    public let timestamp: Date
    
    public var summary: String {
        return "\(shape.type.rawValue) room, \(Int(dimensions.area))m² area, \(Int(confidence * 100))% confidence"
    }
}

public struct RoomCharacteristics {
    public let size: RoomSize
    public let proportions: RoomProportions
    public let shape: RoomShapeType
    public let complexity: ShapeComplexity
    public let accessibility: AccessibilityFeatures
    public let naturalFeatures: [NaturalFeature]
}

public enum RoomSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"
    
    public var description: String {
        switch self {
        case .small: return "Compact space (under 10m²)"
        case .medium: return "Medium space (10-25m²)"
        case .large: return "Large space (25-50m²)"
        case .extraLarge: return "Extra large space (over 50m²)"
        }
    }
}

public struct RoomProportions {
    public let aspectRatio: Float
    public let heightRatio: Float
    public let isWellProportioned: Bool
}

public struct AccessibilityFeatures {
    public let clearPathways: Bool
    public let wheelchairAccessible: Bool
    public let hasObstacles: Bool
    public let minimumClearance: Float
}

public struct NaturalFeature {
    public let type: NaturalFeatureType
    public let position: SIMD3<Float>
    public let size: SIMD2<Float>
    public let orientation: Float
    public let impact: FeatureImpact
}

public enum NaturalFeatureType: String, CaseIterable {
    case window = "Window"
    case skylight = "Skylight"
    case architecturalFeature = "Architectural Feature"
    case alcove = "Alcove"
    case column = "Column"
}

public enum FeatureImpact: String, CaseIterable {
    case lighting = "Lighting"
    case ventilation = "Ventilation"
    case aesthetic = "Aesthetic"
    case structural = "Structural"
    case functional = "Functional"
}