import Foundation
import ARKit
import simd

// MARK: - AR Measurement (for simple distance measurements)

public struct ARMeasurement: Identifiable, Codable {
    public let id: UUID
    public let position: simd_float3
    public let timestamp: Date
    
    public init(id: UUID = UUID(), position: simd_float3, timestamp: Date = Date()) {
        self.id = id
        self.position = position
        self.timestamp = timestamp
    }
}

// MARK: - Measurement Data Models

/// Represents a single measurement in 3D AR space
public struct Measurement: Codable, Identifiable, Equatable {
    public let id: UUID
    public let type: MeasurementType
    public let name: String
    public let timestamp: Date
    public let points: [MeasurementPoint]
    public let value: MeasurementValue
    public let accuracy: MeasurementAccuracy
    public let trackingQuality: Float
    public let sessionState: String
    public var notes: String
    public var isVisible: Bool
    public var color: MeasurementColor
    
    public init(
        id: UUID = UUID(),
        type: MeasurementType,
        name: String,
        timestamp: Date = Date(),
        points: [MeasurementPoint],
        value: MeasurementValue,
        accuracy: MeasurementAccuracy,
        trackingQuality: Float,
        sessionState: String,
        notes: String = "",
        isVisible: Bool = true,
        color: MeasurementColor = .blue
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.timestamp = timestamp
        self.points = points
        self.value = value
        self.accuracy = accuracy
        self.trackingQuality = trackingQuality
        self.sessionState = sessionState
        self.notes = notes
        self.isVisible = isVisible
        self.color = color
    }
    
    /// Get the measurement in the specified unit system
    public func getValue(in unitSystem: UnitSystem) -> MeasurementValue {
        return value.converted(to: unitSystem)
    }
    
    /// Check if measurement is considered accurate enough for use
    public var isAccurate: Bool {
        return accuracy.confidenceScore >= 0.7 && trackingQuality >= 0.6
    }
    
    /// Get a user-friendly accuracy description
    public var accuracyDescription: String {
        switch accuracy.level {
        case .excellent: return "Excellent (±\(String(format: "%.1f", accuracy.errorMargin * 100))cm)"
        case .good: return "Good (±\(String(format: "%.1f", accuracy.errorMargin * 100))cm)"
        case .fair: return "Fair (±\(String(format: "%.1f", accuracy.errorMargin * 100))cm)"
        case .poor: return "Poor (±\(String(format: "%.1f", accuracy.errorMargin * 100))cm)"
        case .unreliable: return "Unreliable (±\(String(format: "%.1f", accuracy.errorMargin * 100))cm)"
        }
    }
}

/// Types of measurements that can be taken
public enum MeasurementType: String, CaseIterable, Codable {
    case distance = "distance"
    case area = "area"
    case volume = "volume"
    case angle = "angle"
    case height = "height"
    case perimeter = "perimeter"
    
    public var displayName: String {
        switch self {
        case .distance: return "Distance"
        case .area: return "Area"
        case .volume: return "Volume"
        case .angle: return "Angle"
        case .height: return "Height"
        case .perimeter: return "Perimeter"
        }
    }
    
    public var icon: String {
        switch self {
        case .distance: return "ruler"
        case .area: return "rectangle"
        case .volume: return "cube"
        case .angle: return "angle"
        case .height: return "arrow.up.and.down"
        case .perimeter: return "rectangle.dashed"
        }
    }
    
    public var minimumPoints: Int {
        switch self {
        case .distance, .height: return 2
        case .area, .perimeter: return 3
        case .volume: return 4
        case .angle: return 3
        }
    }
    
    public var maximumPoints: Int? {
        switch self {
        case .distance, .height, .angle: return 2
        case .area, .perimeter, .volume: return nil // Can have unlimited points
        }
    }
}

/// A point in 3D space with additional metadata
public struct MeasurementPoint: Codable, Identifiable, Equatable {
    public let id: UUID
    public let position: simd_float3
    public let worldTransform: simd_float4x4
    public let timestamp: Date
    public let confidence: Float
    public let trackingQuality: Float
    public let screenPosition: CGPoint?
    public let surfaceNormal: simd_float3?
    public let anchorID: String?
    
    public init(
        id: UUID = UUID(),
        position: simd_float3,
        worldTransform: simd_float4x4,
        timestamp: Date = Date(),
        confidence: Float = 1.0,
        trackingQuality: Float = 1.0,
        screenPosition: CGPoint? = nil,
        surfaceNormal: simd_float3? = nil,
        anchorID: String? = nil
    ) {
        self.id = id
        self.position = position
        self.worldTransform = worldTransform
        self.timestamp = timestamp
        self.confidence = confidence
        self.trackingQuality = trackingQuality
        self.screenPosition = screenPosition
        self.surfaceNormal = surfaceNormal
        self.anchorID = anchorID
    }
    
    /// Distance from this point to another point
    public func distance(to other: MeasurementPoint) -> Float {
        return simd_distance(position, other.position)
    }
    
    /// Get position in a specific coordinate system
    public func position(in transform: simd_float4x4) -> simd_float3 {
        let worldPos = simd_float4(position.x, position.y, position.z, 1.0)
        let transformedPos = transform * worldPos
        return simd_float3(transformedPos.x, transformedPos.y, transformedPos.z)
    }
}

/// Represents a measurement value with different units
public struct MeasurementValue: Codable, Equatable {
    public let primary: Float // Always stored in meters for distance/length
    public let secondary: Float? // For area (m²) or volume (m³)
    public let tertiary: Float? // For volume calculations
    public let unit: MeasurementUnit
    public let unitSystem: UnitSystem
    
    public init(
        primary: Float,
        secondary: Float? = nil,
        tertiary: Float? = nil,
        unit: MeasurementUnit,
        unitSystem: UnitSystem = .metric
    ) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.unit = unit
        self.unitSystem = unitSystem
    }
    
    /// Convert this measurement to a different unit system
    public func converted(to targetSystem: UnitSystem) -> MeasurementValue {
        guard targetSystem != unitSystem else { return self }
        
        let convertedPrimary: Float
        let convertedSecondary: Float?
        let convertedTertiary: Float?
        let newUnit: MeasurementUnit
        
        switch unit.category {
        case .length:
            if targetSystem == .imperial {
                convertedPrimary = primary * 3.28084 // meters to feet
                newUnit = .feet
            } else {
                convertedPrimary = primary / 3.28084 // feet to meters
                newUnit = .meters
            }
            convertedSecondary = secondary
            convertedTertiary = tertiary
            
        case .area:
            if targetSystem == .imperial {
                convertedPrimary = primary * 10.7639 // m² to ft²
                newUnit = .squareFeet
            } else {
                convertedPrimary = primary / 10.7639 // ft² to m²
                newUnit = .squareMeters
            }
            convertedSecondary = secondary
            convertedTertiary = tertiary
            
        case .volume:
            if targetSystem == .imperial {
                convertedPrimary = primary * 35.3147 // m³ to ft³
                newUnit = .cubicFeet
            } else {
                convertedPrimary = primary / 35.3147 // ft³ to m³
                newUnit = .cubicMeters
            }
            convertedSecondary = secondary
            convertedTertiary = tertiary
            
        case .angle:
            // Angles don't need conversion
            convertedPrimary = primary
            convertedSecondary = secondary
            convertedTertiary = tertiary
            newUnit = unit
        }
        
        return MeasurementValue(
            primary: convertedPrimary,
            secondary: convertedSecondary,
            tertiary: convertedTertiary,
            unit: newUnit,
            unitSystem: targetSystem
        )
    }
    
    /// Get a formatted string representation
    public var formattedString: String {
        switch unit.category {
        case .length:
            if unitSystem == .metric {
                if primary < 1.0 {
                    return String(format: "%.1f cm", primary * 100)
                } else {
                    return String(format: "%.2f m", primary)
                }
            } else {
                let totalInches = primary * 12
                let feet = Int(primary)
                let inches = totalInches - Float(feet * 12)
                if feet > 0 {
                    return String(format: "%d' %.1f\"", feet, inches)
                } else {
                    return String(format: "%.1f\"", inches)
                }
            }
            
        case .area:
            if unitSystem == .metric {
                return String(format: "%.2f m²", primary)
            } else {
                return String(format: "%.2f ft²", primary)
            }
            
        case .volume:
            if unitSystem == .metric {
                return String(format: "%.2f m³", primary)
            } else {
                return String(format: "%.2f ft³", primary)
            }
            
        case .angle:
            return String(format: "%.1f°", primary)
        }
    }
    
    /// Get a short formatted string
    public var shortFormattedString: String {
        switch unit.category {
        case .length:
            if unitSystem == .metric {
                if primary < 1.0 {
                    return String(format: "%.0fcm", primary * 100)
                } else {
                    return String(format: "%.1fm", primary)
                }
            } else {
                let totalInches = primary * 12
                let feet = Int(primary)
                let inches = totalInches - Float(feet * 12)
                if feet > 0 {
                    return String(format: "%d'%.0f\"", feet, inches)
                } else {
                    return String(format: "%.0f\"", inches)
                }
            }
            
        case .area:
            return unitSystem == .metric ? String(format: "%.1fm²", primary) : String(format: "%.1fft²", primary)
            
        case .volume:
            return unitSystem == .metric ? String(format: "%.1fm³", primary) : String(format: "%.1fft³", primary)
            
        case .angle:
            return String(format: "%.0f°", primary)
        }
    }
}

/// Available measurement units
public enum MeasurementUnit: String, CaseIterable, Codable {
    // Length
    case meters = "m"
    case centimeters = "cm"
    case millimeters = "mm"
    case feet = "ft"
    case inches = "in"
    
    // Area
    case squareMeters = "m²"
    case squareFeet = "ft²"
    
    // Volume
    case cubicMeters = "m³"
    case cubicFeet = "ft³"
    
    // Angle
    case degrees = "°"
    case radians = "rad"
    
    public var category: MeasurementCategory {
        switch self {
        case .meters, .centimeters, .millimeters, .feet, .inches:
            return .length
        case .squareMeters, .squareFeet:
            return .area
        case .cubicMeters, .cubicFeet:
            return .volume
        case .degrees, .radians:
            return .angle
        }
    }
    
    public var displayName: String {
        switch self {
        case .meters: return "Meters"
        case .centimeters: return "Centimeters"
        case .millimeters: return "Millimeters"
        case .feet: return "Feet"
        case .inches: return "Inches"
        case .squareMeters: return "Square Meters"
        case .squareFeet: return "Square Feet"
        case .cubicMeters: return "Cubic Meters"
        case .cubicFeet: return "Cubic Feet"
        case .degrees: return "Degrees"
        case .radians: return "Radians"
        }
    }
}

public enum MeasurementCategory: String, CaseIterable, Codable {
    case length = "length"
    case area = "area"
    case volume = "volume"
    case angle = "angle"
}

public enum UnitSystem: String, CaseIterable, Codable {
    case metric = "metric"
    case imperial = "imperial"
    
    public var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }
}

/// Measurement accuracy information
public struct MeasurementAccuracy: Codable, Equatable {
    public let level: AccuracyLevel
    public let confidenceScore: Float // 0.0 to 1.0
    public let errorMargin: Float // In meters
    public let factors: [AccuracyFactor]
    
    public init(
        level: AccuracyLevel,
        confidenceScore: Float,
        errorMargin: Float,
        factors: [AccuracyFactor] = []
    ) {
        self.level = level
        self.confidenceScore = max(0.0, min(1.0, confidenceScore))
        self.errorMargin = max(0.0, errorMargin)
        self.factors = factors
    }
    
    /// Create accuracy assessment from tracking conditions
    public static func assess(
        trackingQuality: Float,
        distance: Float,
        pointConfidence: Float,
        lightingConditions: LightingCondition = .good
    ) -> MeasurementAccuracy {
        
        var score = trackingQuality * 0.4 + pointConfidence * 0.4
        var errorMargin: Float = 0.02 // Base 2cm error
        var factors: [AccuracyFactor] = []
        
        // Distance affects accuracy
        if distance > 5.0 {
            score *= 0.8
            errorMargin += distance * 0.005 // 0.5cm per meter beyond 5m
            factors.append(.longDistance)
        }
        
        // Lighting affects accuracy
        switch lightingConditions {
        case .poor:
            score *= 0.7
            errorMargin += 0.01
            factors.append(.poorLighting)
        case .excellent:
            score *= 1.1
            errorMargin *= 0.8
        default:
            break
        }
        
        // Determine accuracy level
        let level: AccuracyLevel
        if score >= 0.9 {
            level = .excellent
        } else if score >= 0.8 {
            level = .good
        } else if score >= 0.6 {
            level = .fair
        } else if score >= 0.4 {
            level = .poor
        } else {
            level = .unreliable
        }
        
        return MeasurementAccuracy(
            level: level,
            confidenceScore: min(score, 1.0),
            errorMargin: errorMargin,
            factors: factors
        )
    }
}

public enum AccuracyLevel: String, CaseIterable, Codable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case unreliable = "unreliable"
    
    public var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "mint"
        case .fair: return "yellow"
        case .poor: return "orange"
        case .unreliable: return "red"
        }
    }
    
    public var icon: String {
        switch self {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .fair: return "exclamationmark.triangle"
        case .poor: return "exclamationmark.triangle.fill"
        case .unreliable: return "xmark.circle.fill"
        }
    }
}

public enum AccuracyFactor: String, CaseIterable, Codable {
    case longDistance = "long_distance"
    case poorLighting = "poor_lighting"
    case fastMovement = "fast_movement"
    case unstableTracking = "unstable_tracking"
    case lowConfidence = "low_confidence"
    case surfaceReflection = "surface_reflection"
    
    public var description: String {
        switch self {
        case .longDistance: return "Long distance measurement"
        case .poorLighting: return "Poor lighting conditions"
        case .fastMovement: return "Fast device movement"
        case .unstableTracking: return "Unstable AR tracking"
        case .lowConfidence: return "Low point confidence"
        case .surfaceReflection: return "Reflective surface detected"
        }
    }
}

public enum LightingCondition: String, CaseIterable, Codable {
    case poor = "poor"
    case fair = "fair"
    case good = "good"
    case excellent = "excellent"
}

/// Color options for measurements
public enum MeasurementColor: String, CaseIterable, Codable {
    case red = "red"
    case blue = "blue"
    case green = "green"
    case orange = "orange"
    case purple = "purple"
    case yellow = "yellow"
    case pink = "pink"
    case cyan = "cyan"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var hexValue: String {
        switch self {
        case .red: return "#FF3B30"
        case .blue: return "#007AFF"
        case .green: return "#34C759"
        case .orange: return "#FF9500"
        case .purple: return "#AF52DE"
        case .yellow: return "#FFCC00"
        case .pink: return "#FF2D92"
        case .cyan: return "#5AC8FA"
        }
    }
}

// MARK: - Measurement Session

/// Represents a measurement session with multiple measurements
public struct MeasurementSession: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let timestamp: Date
    public var measurements: [Measurement]
    public let roomScanID: UUID? // Reference to associated room scan
    public var notes: String
    public var preferredUnitSystem: UnitSystem
    
    public init(
        id: UUID = UUID(),
        name: String,
        timestamp: Date = Date(),
        measurements: [Measurement] = [],
        roomScanID: UUID? = nil,
        notes: String = "",
        preferredUnitSystem: UnitSystem = .metric
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.measurements = measurements
        self.roomScanID = roomScanID
        self.notes = notes
        self.preferredUnitSystem = preferredUnitSystem
    }
    
    /// Get measurements by type
    public func measurements(of type: MeasurementType) -> [Measurement] {
        return measurements.filter { $0.type == type }
    }
    
    /// Get total count of accurate measurements
    public var accurateMeasurementsCount: Int {
        return measurements.filter { $0.isAccurate }.count
    }
    
    /// Get session summary statistics
    public var summary: MeasurementSessionSummary {
        let totalMeasurements = measurements.count
        let accurateMeasurements = accurateMeasurementsCount
        let measurementTypes = Set(measurements.map { $0.type }).count
        let averageAccuracy = measurements.isEmpty ? 0.0 : 
            measurements.map { $0.accuracy.confidenceScore }.reduce(0, +) / Float(measurements.count)
        
        return MeasurementSessionSummary(
            totalMeasurements: totalMeasurements,
            accurateMeasurements: accurateMeasurements,
            measurementTypes: measurementTypes,
            averageAccuracy: averageAccuracy
        )
    }
}

public struct MeasurementSessionSummary {
    public let totalMeasurements: Int
    public let accurateMeasurements: Int
    public let measurementTypes: Int
    public let averageAccuracy: Float
    
    public var accuracyPercentage: Int {
        return Int(averageAccuracy * 100)
    }
    
    public var reliabilityScore: Float {
        guard totalMeasurements > 0 else { return 0 }
        return Float(accurateMeasurements) / Float(totalMeasurements)
    }
}

// MARK: - Measurement History

/// Represents the measurement history with filtering and search capabilities
public struct MeasurementHistory: Codable {
    public var sessions: [MeasurementSession]
    public let maxSessions: Int
    public let maxMeasurementsPerSession: Int
    
    public init(
        sessions: [MeasurementSession] = [],
        maxSessions: Int = 50,
        maxMeasurementsPerSession: Int = 100
    ) {
        self.sessions = sessions
        self.maxSessions = maxSessions
        self.maxMeasurementsPerSession = maxMeasurementsPerSession
    }
    
    /// Add a new session
    public mutating func addSession(_ session: MeasurementSession) {
        sessions.append(session)
        
        // Maintain session limit
        if sessions.count > maxSessions {
            sessions.removeFirst(sessions.count - maxSessions)
        }
        
        sessions.sort { $0.timestamp > $1.timestamp }
    }
    
    /// Get all measurements across all sessions
    public var allMeasurements: [Measurement] {
        return sessions.flatMap { $0.measurements }
    }
    
    /// Search measurements by name or notes
    public func searchMeasurements(query: String) -> [Measurement] {
        let lowercaseQuery = query.lowercased()
        return allMeasurements.filter { measurement in
            measurement.name.lowercased().contains(lowercaseQuery) ||
            measurement.notes.lowercased().contains(lowercaseQuery)
        }
    }
    
    /// Filter measurements by type
    public func measurements(of type: MeasurementType) -> [Measurement] {
        return allMeasurements.filter { $0.type == type }
    }
    
    /// Get measurements from a specific date range
    public func measurements(from startDate: Date, to endDate: Date) -> [Measurement] {
        return allMeasurements.filter { measurement in
            measurement.timestamp >= startDate && measurement.timestamp <= endDate
        }
    }
    
    /// Get statistics for the entire history
    public var statistics: MeasurementHistoryStatistics {
        let allMeasurements = self.allMeasurements
        let totalMeasurements = allMeasurements.count
        let accurateMeasurements = allMeasurements.filter { $0.isAccurate }.count
        
        var typeCounts: [MeasurementType: Int] = [:]
        for type in MeasurementType.allCases {
            typeCounts[type] = allMeasurements.filter { $0.type == type }.count
        }
        
        let averageAccuracy = allMeasurements.isEmpty ? 0.0 :
            allMeasurements.map { $0.accuracy.confidenceScore }.reduce(0, +) / Float(allMeasurements.count)
        
        return MeasurementHistoryStatistics(
            totalSessions: sessions.count,
            totalMeasurements: totalMeasurements,
            accurateMeasurements: accurateMeasurements,
            measurementsByType: typeCounts,
            averageAccuracy: averageAccuracy
        )
    }
}

public struct MeasurementHistoryStatistics {
    public let totalSessions: Int
    public let totalMeasurements: Int
    public let accurateMeasurements: Int
    public let measurementsByType: [MeasurementType: Int]
    public let averageAccuracy: Float
    
    public var accuracyPercentage: Int {
        return Int(averageAccuracy * 100)
    }
    
    public var mostUsedMeasurementType: MeasurementType? {
        return measurementsByType.max { $0.value < $1.value }?.key
    }
}