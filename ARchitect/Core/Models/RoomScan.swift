import Foundation
import ARKit
import simd

// MARK: - Room Scan Data Models

/// Represents a complete room scan with all detected geometry and metadata
public struct RoomScan: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let timestamp: Date
    public let scanDuration: TimeInterval
    public let scanQuality: ScanQuality
    public let roomDimensions: RoomDimensions
    public let detectedPlanes: [DetectedPlane]
    public let mergedPlanes: [MergedPlane]
    public let roomBounds: RoomBounds
    public let scanMetadata: ScanMetadata
    
    public init(
        id: UUID = UUID(),
        name: String,
        timestamp: Date = Date(),
        scanDuration: TimeInterval,
        scanQuality: ScanQuality,
        roomDimensions: RoomDimensions,
        detectedPlanes: [DetectedPlane],
        mergedPlanes: [MergedPlane],
        roomBounds: RoomBounds,
        scanMetadata: ScanMetadata
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.scanDuration = scanDuration
        self.scanQuality = scanQuality
        self.roomDimensions = roomDimensions
        self.detectedPlanes = detectedPlanes
        self.mergedPlanes = mergedPlanes
        self.roomBounds = roomBounds
        self.scanMetadata = scanMetadata
    }
}

/// Represents the quality assessment of a room scan
public struct ScanQuality: Codable {
    public let overallScore: Double // 0.0 to 1.0
    public let completeness: Double // How complete the scan is
    public let accuracy: Double // How accurate the measurements are
    public let coverage: Double // How much of the room was scanned
    public let planeQuality: Double // Quality of detected planes
    public let trackingStability: Double // Stability during scanning
    public let issues: [ScanIssue]
    public let recommendations: [String]
    
    public var grade: ScanGrade {
        switch overallScore {
        case 0.9...1.0: return .excellent
        case 0.8..<0.9: return .good
        case 0.7..<0.8: return .fair
        case 0.5..<0.7: return .poor
        default: return .incomplete
        }
    }
    
    public enum ScanGrade: String, Codable, CaseIterable {
        case excellent = "excellent"
        case good = "good"
        case fair = "fair"
        case poor = "poor"
        case incomplete = "incomplete"
        
        public var displayName: String {
            return rawValue.capitalized
        }
        
        public var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "mint"
            case .fair: return "yellow"
            case .poor: return "orange"
            case .incomplete: return "red"
            }
        }
    }
}

/// Issues detected during room scanning
public struct ScanIssue: Codable, Identifiable {
    public let id: UUID
    public let type: IssueType
    public let severity: Severity
    public let description: String
    public let location: simd_float3?
    public let timestamp: Date
    
    public enum IssueType: String, Codable, CaseIterable {
        case missingWall = "missing_wall"
        case poorTracking = "poor_tracking"
        case incompleteFloor = "incomplete_floor"
        case overlappingPlanes = "overlapping_planes"
        case lowLighting = "low_lighting"
        case excessiveMotion = "excessive_motion"
        case occludedSurfaces = "occluded_surfaces"
        case unstableGeometry = "unstable_geometry"
    }
    
    public enum Severity: String, Codable, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
    
    public init(
        id: UUID = UUID(),
        type: IssueType,
        severity: Severity,
        description: String,
        location: simd_float3? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.description = description
        self.location = location
        self.timestamp = timestamp
    }
}

/// Room dimensions calculated from the scan
public struct RoomDimensions: Codable {
    public let width: Float // X dimension in meters
    public let length: Float // Z dimension in meters
    public let height: Float // Y dimension in meters
    public let area: Float // Floor area in square meters
    public let volume: Float // Room volume in cubic meters
    public let perimeter: Float // Room perimeter in meters
    public let confidence: Float // Confidence in measurements (0.0 to 1.0)
    
    public init(width: Float, length: Float, height: Float, confidence: Float = 1.0) {
        self.width = width
        self.length = length
        self.height = height
        self.area = width * length
        self.volume = width * length * height
        self.perimeter = 2 * (width + length)
        self.confidence = confidence
    }
    
    public var displayWidth: String {
        return String(format: "%.2f m", width)
    }
    
    public var displayLength: String {
        return String(format: "%.2f m", length)
    }
    
    public var displayHeight: String {
        return String(format: "%.2f m", height)
    }
    
    public var displayArea: String {
        return String(format: "%.2f m²", area)
    }
    
    public var displayVolume: String {
        return String(format: "%.2f m³", volume)
    }
}

/// Individual detected plane from ARKit
public struct DetectedPlane: Codable, Identifiable {
    public let id: UUID
    public let arIdentifier: String // ARPlaneAnchor identifier
    public let alignment: PlaneAlignment
    public let center: simd_float3
    public let extent: simd_float2
    public let transform: simd_float4x4
    public let geometry: [simd_float3] // Boundary points
    public let area: Float
    public let confidence: Float
    public let timestamp: Date
    public let trackingQuality: Float
    
    public enum PlaneAlignment: String, Codable, CaseIterable {
        case horizontal = "horizontal"
        case vertical = "vertical"
        case unknown = "unknown"
        
        public init(from arAlignment: ARPlaneAnchor.Alignment) {
            switch arAlignment {
            case .horizontal:
                self = .horizontal
            case .vertical:
                self = .vertical
            @unknown default:
                self = .unknown
            }
        }
    }
    
    public init(from anchor: ARPlaneAnchor, trackingQuality: Float = 1.0) {
        self.id = UUID()
        self.arIdentifier = anchor.identifier.uuidString
        self.alignment = PlaneAlignment(from: anchor.alignment)
        self.center = anchor.center
        self.extent = anchor.extent
        self.transform = anchor.transform
        self.area = anchor.extent.x * anchor.extent.z
        self.confidence = 1.0 // ARKit doesn't provide confidence directly
        self.timestamp = Date()
        self.trackingQuality = trackingQuality
        
        // Extract boundary geometry if available
        if let geometry = anchor.geometry {
            self.geometry = geometry.boundaryVertices.map { vertex in
                let worldPos = anchor.transform * simd_float4(vertex.x, vertex.y, vertex.z, 1.0)
                return simd_float3(worldPos.x, worldPos.y, worldPos.z)
            }
        } else {
            // Create simple rectangle boundary
            let halfX = anchor.extent.x / 2
            let halfZ = anchor.extent.z / 2
            let corners = [
                simd_float3(-halfX, 0, -halfZ),
                simd_float3(halfX, 0, -halfZ),
                simd_float3(halfX, 0, halfZ),
                simd_float3(-halfX, 0, halfZ)
            ]
            
            self.geometry = corners.map { corner in
                let worldPos = anchor.transform * simd_float4(corner.x, corner.y, corner.z, 1.0)
                return simd_float3(worldPos.x, worldPos.y, worldPos.z)
            }
        }
    }
}

/// Merged planes created by combining adjacent detected planes
public struct MergedPlane: Codable, Identifiable {
    public let id: UUID
    public let type: PlaneType
    public let sourceIDs: [UUID] // IDs of DetectedPlanes that were merged
    public let center: simd_float3
    public let normal: simd_float3
    public let bounds: PlaneBounds
    public let area: Float
    public let confidence: Float
    public let geometry: [simd_float3] // Merged boundary points
    
    public enum PlaneType: String, Codable, CaseIterable {
        case floor = "floor"
        case ceiling = "ceiling"
        case wall = "wall"
        case surface = "surface" // Tables, counters, etc.
        
        public var displayName: String {
            return rawValue.capitalized
        }
    }
    
    public init(
        id: UUID = UUID(),
        type: PlaneType,
        sourceIDs: [UUID],
        center: simd_float3,
        normal: simd_float3,
        bounds: PlaneBounds,
        area: Float,
        confidence: Float,
        geometry: [simd_float3]
    ) {
        self.id = id
        self.type = type
        self.sourceIDs = sourceIDs
        self.center = center
        self.normal = normal
        self.bounds = bounds
        self.area = area
        self.confidence = confidence
        self.geometry = geometry
    }
}

/// Bounds of a plane in 3D space
public struct PlaneBounds: Codable {
    public let min: simd_float3
    public let max: simd_float3
    public let size: simd_float3
    
    public init(min: simd_float3, max: simd_float3) {
        self.min = min
        self.max = max
        self.size = max - min
    }
    
    public init(points: [simd_float3]) {
        guard !points.isEmpty else {
            self.min = simd_float3(0, 0, 0)
            self.max = simd_float3(0, 0, 0)
            self.size = simd_float3(0, 0, 0)
            return
        }
        
        var minPoint = points[0]
        var maxPoint = points[0]
        
        for point in points {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }
        
        self.min = minPoint
        self.max = maxPoint
        self.size = maxPoint - minPoint
    }
}

/// Overall room bounds
public struct RoomBounds: Codable {
    public let min: simd_float3
    public let max: simd_float3
    public let center: simd_float3
    public let size: simd_float3
    
    public init(min: simd_float3, max: simd_float3) {
        self.min = min
        self.max = max
        self.center = (min + max) / 2
        self.size = max - min
    }
    
    public init(from planes: [MergedPlane]) {
        guard !planes.isEmpty else {
            self.min = simd_float3(0, 0, 0)
            self.max = simd_float3(0, 0, 0)
            self.center = simd_float3(0, 0, 0)
            self.size = simd_float3(0, 0, 0)
            return
        }
        
        var minPoint = planes[0].bounds.min
        var maxPoint = planes[0].bounds.max
        
        for plane in planes {
            minPoint = simd_min(minPoint, plane.bounds.min)
            maxPoint = simd_max(maxPoint, plane.bounds.max)
        }
        
        self.min = minPoint
        self.max = maxPoint
        self.center = (minPoint + maxPoint) / 2
        self.size = maxPoint - minPoint
    }
}

/// Metadata about the scanning process
public struct ScanMetadata: Codable {
    public let deviceModel: String
    public let systemVersion: String
    public let appVersion: String
    public let arKitVersion: String
    public let startTime: Date
    public let endTime: Date
    public let totalFrames: Int
    public let averageTrackingQuality: Float
    public let memoryUsage: Int // Peak memory usage in bytes
    public let scanSettings: ScanSettings
    
    public init(
        deviceModel: String = UIDevice.current.model,
        systemVersion: String = UIDevice.current.systemVersion,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
        arKitVersion: String = "ARKit 6.0", // This could be detected dynamically
        startTime: Date,
        endTime: Date = Date(),
        totalFrames: Int = 0,
        averageTrackingQuality: Float = 0.0,
        memoryUsage: Int = 0,
        scanSettings: ScanSettings
    ) {
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.appVersion = appVersion
        self.arKitVersion = arKitVersion
        self.startTime = startTime
        self.endTime = endTime
        self.totalFrames = totalFrames
        self.averageTrackingQuality = averageTrackingQuality
        self.memoryUsage = memoryUsage
        self.scanSettings = scanSettings
    }
}

/// Settings used during the scanning process
public struct ScanSettings: Codable {
    public let planeDetection: [String] // horizontal, vertical
    public let sceneReconstruction: String
    public let environmentTexturing: String
    public let qualityMode: QualityMode
    public let timeoutDuration: TimeInterval
    public let minPlaneArea: Float
    public let maxPlanesCount: Int
    public let mergingThreshold: Float
    
    public enum QualityMode: String, Codable, CaseIterable {
        case fast = "fast"
        case balanced = "balanced"
        case accurate = "accurate"
        
        public var displayName: String {
            return rawValue.capitalized
        }
    }
    
    public static let `default` = ScanSettings(
        planeDetection: ["horizontal", "vertical"],
        sceneReconstruction: "meshWithClassification",
        environmentTexturing: "automatic",
        qualityMode: .balanced,
        timeoutDuration: 300, // 5 minutes
        minPlaneArea: 0.1, // 0.1 square meters
        maxPlanesCount: 50,
        mergingThreshold: 0.1 // 10 cm
    )
    
    public init(
        planeDetection: [String],
        sceneReconstruction: String,
        environmentTexturing: String,
        qualityMode: QualityMode,
        timeoutDuration: TimeInterval,
        minPlaneArea: Float,
        maxPlanesCount: Int,
        mergingThreshold: Float
    ) {
        self.planeDetection = planeDetection
        self.sceneReconstruction = sceneReconstruction
        self.environmentTexturing = environmentTexturing
        self.qualityMode = qualityMode
        self.timeoutDuration = timeoutDuration
        self.minPlaneArea = minPlaneArea
        self.maxPlanesCount = maxPlanesCount
        self.mergingThreshold = mergingThreshold
    }
}

// MARK: - Scanning State Management

/// Current state of the room scanning process
public enum ScanState: String, CaseIterable {
    case notStarted = "not_started"
    case initializing = "initializing"
    case scanning = "scanning"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    
    public var displayName: String {
        switch self {
        case .notStarted: return "Ready to Scan"
        case .initializing: return "Initializing..."
        case .scanning: return "Scanning Room"
        case .processing: return "Processing Scan"
        case .completed: return "Scan Complete"
        case .failed: return "Scan Failed"
        case .cancelled: return "Scan Cancelled"
        }
    }
    
    public var isActive: Bool {
        return self == .initializing || self == .scanning || self == .processing
    }
}

/// Progress information during scanning
public struct ScanProgress: Codable {
    public let completionPercentage: Float // 0.0 to 1.0
    public let detectedPlanes: Int
    public let floorCoverage: Float // Percentage of expected floor covered
    public let wallCoverage: Float // Percentage of expected walls detected
    public let scanDuration: TimeInterval
    public let currentPhase: ScanPhase
    public let estimatedTimeRemaining: TimeInterval?
    
    public enum ScanPhase: String, Codable, CaseIterable {
        case floorDetection = "floor_detection"
        case wallDetection = "wall_detection"
        case detailScanning = "detail_scanning"
        case optimization = "optimization"
        case finalization = "finalization"
        
        public var displayName: String {
            switch self {
            case .floorDetection: return "Detecting Floor"
            case .wallDetection: return "Detecting Walls"
            case .detailScanning: return "Scanning Details"
            case .optimization: return "Optimizing"
            case .finalization: return "Finalizing"
            }
        }
        
        public var instruction: String {
            switch self {
            case .floorDetection: return "Point camera at the floor and move slowly"
            case .wallDetection: return "Scan each wall by pointing camera at them"
            case .detailScanning: return "Scan corners and details for accuracy"
            case .optimization: return "Processing scan data..."
            case .finalization: return "Completing scan..."
            }
        }
    }
    
    public init(
        completionPercentage: Float = 0.0,
        detectedPlanes: Int = 0,
        floorCoverage: Float = 0.0,
        wallCoverage: Float = 0.0,
        scanDuration: TimeInterval = 0.0,
        currentPhase: ScanPhase = .floorDetection,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.completionPercentage = completionPercentage
        self.detectedPlanes = detectedPlanes
        self.floorCoverage = floorCoverage
        self.wallCoverage = wallCoverage
        self.scanDuration = scanDuration
        self.currentPhase = currentPhase
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}

// MARK: - Extensions for SIMD Types Codable Support

extension simd_float2: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        self.init(x, y)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
    }
}

extension simd_float3: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        let z = try container.decode(Float.self)
        self.init(x, y, z)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
    }
}

extension simd_float4x4: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var columns: [simd_float4] = []
        
        for _ in 0..<4 {
            var columnContainer = try container.nestedUnkeyedContainer()
            let x = try columnContainer.decode(Float.self)
            let y = try columnContainer.decode(Float.self)
            let z = try columnContainer.decode(Float.self)
            let w = try columnContainer.decode(Float.self)
            columns.append(simd_float4(x, y, z, w))
        }
        
        self.init(columns[0], columns[1], columns[2], columns[3])
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        
        for column in [columns.0, columns.1, columns.2, columns.3] {
            var columnContainer = container.nestedUnkeyedContainer()
            try columnContainer.encode(column.x)
            try columnContainer.encode(column.y)
            try columnContainer.encode(column.z)
            try columnContainer.encode(column.w)
        }
    }
}