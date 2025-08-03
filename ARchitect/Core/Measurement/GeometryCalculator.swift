import Foundation
import simd

// MARK: - Geometry Calculator
public class GeometryCalculator {
    
    public init() {}
    
    // MARK: - Distance Calculations
    
    /// Calculate distance between two points
    public func calculateDistance(from point1: MeasurementPoint, to point2: MeasurementPoint, unitSystem: UnitSystem) throws -> MeasurementValue {
        let distance = simd_distance(point1.position, point2.position)
        
        guard distance > 0 else {
            throw MeasurementError.invalidGeometry("Points are identical")
        }
        
        let unit: MeasurementUnit = unitSystem == .metric ? .meters : .feet
        return MeasurementValue(primary: distance, unit: unit, unitSystem: unitSystem)
    }
    
    /// Calculate height (vertical distance) between two points
    public func calculateHeight(from bottom: MeasurementPoint, to top: MeasurementPoint, unitSystem: UnitSystem) throws -> MeasurementValue {
        let heightDifference = abs(top.position.y - bottom.position.y)
        
        guard heightDifference > 0 else {
            throw MeasurementError.invalidGeometry("Points are at the same height")
        }
        
        let unit: MeasurementUnit = unitSystem == .metric ? .meters : .feet
        return MeasurementValue(primary: heightDifference, unit: unit, unitSystem: unitSystem)
    }
    
    /// Calculate angle between three points
    public func calculateAngle(points: [MeasurementPoint], unitSystem: UnitSystem) throws -> MeasurementValue {
        guard points.count >= 3 else {
            throw MeasurementError.insufficientPoints("Need 3 points to calculate angle")
        }
        
        let center = points[1].position
        let point1 = points[0].position
        let point2 = points[2].position
        
        // Create vectors from center to each point
        let vector1 = simd_normalize(point1 - center)
        let vector2 = simd_normalize(point2 - center)
        
        // Calculate angle using dot product
        let dotProduct = simd_dot(vector1, vector2)
        let angle = acos(max(-1.0, min(1.0, dotProduct))) // Clamp to avoid numerical errors
        let angleInDegrees = angle * 180 / Float.pi
        
        return MeasurementValue(primary: angleInDegrees, unit: .degrees, unitSystem: unitSystem)
    }
    
    // MARK: - Area Calculations
    
    /// Calculate area enclosed by a set of points
    public func calculateArea(points: [MeasurementPoint], unitSystem: UnitSystem) throws -> MeasurementValue {
        guard points.count >= 3 else {
            throw MeasurementError.insufficientPoints("Need at least 3 points to calculate area")
        }
        
        let positions = points.map { $0.position }
        let area = try calculatePolygonArea(positions: positions)
        
        guard area > 0 else {
            throw MeasurementError.invalidGeometry("Points do not form a valid area")
        }
        
        let unit: MeasurementUnit = unitSystem == .metric ? .squareMeters : .squareFeet
        return MeasurementValue(primary: area, unit: unit, unitSystem: unitSystem)
    }
    
    /// Calculate area of a polygon defined by 3D points (projected to best-fit plane)
    private func calculatePolygonArea(positions: [simd_float3]) throws -> Float {
        guard positions.count >= 3 else {
            throw MeasurementError.insufficientPoints("Need at least 3 points")
        }
        
        if positions.count == 3 {
            // Triangle area using cross product
            return calculateTriangleArea(positions[0], positions[1], positions[2])
        }
        
        // For polygons with more than 3 points, use the shoelace formula
        // First, find the best-fit plane and project points onto it
        let (normal, centroid) = try calculateBestFitPlane(positions: positions)
        let projectedPoints = projectOntoPlane(positions: positions, normal: normal, centroid: centroid)
        
        return calculatePolygonAreaShoelace(projectedPoints: projectedPoints)
    }
    
    /// Calculate triangle area using cross product
    private func calculateTriangleArea(_ p1: simd_float3, _ p2: simd_float3, _ p3: simd_float3) -> Float {
        let v1 = p2 - p1
        let v2 = p3 - p1
        let crossProduct = simd_cross(v1, v2)
        return simd_length(crossProduct) / 2.0
    }
    
    /// Calculate polygon area using the shoelace formula (for 2D projected points)
    private func calculatePolygonAreaShoelace(projectedPoints: [simd_float2]) -> Float {
        guard projectedPoints.count >= 3 else { return 0 }
        
        var area: Float = 0
        let n = projectedPoints.count
        
        for i in 0..<n {
            let j = (i + 1) % n
            area += projectedPoints[i].x * projectedPoints[j].y
            area -= projectedPoints[j].x * projectedPoints[i].y
        }
        
        return abs(area) / 2.0
    }
    
    // MARK: - Volume Calculations
    
    /// Calculate volume enclosed by a set of points
    public func calculateVolume(points: [MeasurementPoint], unitSystem: UnitSystem) throws -> MeasurementValue {
        guard points.count >= 4 else {
            throw MeasurementError.insufficientPoints("Need at least 4 points to calculate volume")
        }
        
        let positions = points.map { $0.position }
        let volume = try calculateConvexHullVolume(positions: positions)
        
        guard volume > 0 else {
            throw MeasurementError.invalidGeometry("Points do not form a valid volume")
        }
        
        let unit: MeasurementUnit = unitSystem == .metric ? .cubicMeters : .cubicFeet
        return MeasurementValue(primary: volume, unit: unit, unitSystem: unitSystem)
    }
    
    /// Calculate volume using convex hull approach
    private func calculateConvexHullVolume(positions: [simd_float3]) throws -> Float {
        guard positions.count >= 4 else {
            throw MeasurementError.insufficientPoints("Need at least 4 points for volume")
        }
        
        if positions.count == 4 {
            // Tetrahedron volume
            return calculateTetrahedronVolume(positions[0], positions[1], positions[2], positions[3])
        }
        
        // For more complex shapes, approximate using bounding box
        return calculateBoundingBoxVolume(positions: positions)
    }
    
    /// Calculate tetrahedron volume
    private func calculateTetrahedronVolume(_ p1: simd_float3, _ p2: simd_float3, _ p3: simd_float3, _ p4: simd_float3) -> Float {
        let v1 = p2 - p1
        let v2 = p3 - p1
        let v3 = p4 - p1
        
        let scalarTripleProduct = simd_dot(v1, simd_cross(v2, v3))
        return abs(scalarTripleProduct) / 6.0
    }
    
    /// Calculate volume using axis-aligned bounding box
    private func calculateBoundingBoxVolume(positions: [simd_float3]) -> Float {
        guard !positions.isEmpty else { return 0 }
        
        var minPoint = positions[0]
        var maxPoint = positions[0]
        
        for position in positions {
            minPoint = simd_min(minPoint, position)
            maxPoint = simd_max(maxPoint, position)
        }
        
        let dimensions = maxPoint - minPoint
        return dimensions.x * dimensions.y * dimensions.z
    }
    
    // MARK: - Perimeter Calculations
    
    /// Calculate perimeter of a polygon defined by points
    public func calculatePerimeter(points: [MeasurementPoint], unitSystem: UnitSystem) throws -> MeasurementValue {
        guard points.count >= 3 else {
            throw MeasurementError.insufficientPoints("Need at least 3 points to calculate perimeter")
        }
        
        var totalDistance: Float = 0
        
        // Sum distances between consecutive points
        for i in 0..<points.count {
            let currentPoint = points[i]
            let nextPoint = points[(i + 1) % points.count] // Wrap around to close the polygon
            totalDistance += simd_distance(currentPoint.position, nextPoint.position)
        }
        
        guard totalDistance > 0 else {
            throw MeasurementError.invalidGeometry("Points do not form a valid perimeter")
        }
        
        let unit: MeasurementUnit = unitSystem == .metric ? .meters : .feet
        return MeasurementValue(primary: totalDistance, unit: unit, unitSystem: unitSystem)
    }
    
    // MARK: - Geometric Utilities
    
    /// Calculate the best-fit plane for a set of 3D points
    private func calculateBestFitPlane(positions: [simd_float3]) throws -> (normal: simd_float3, centroid: simd_float3) {
        guard positions.count >= 3 else {
            throw MeasurementError.insufficientPoints("Need at least 3 points for plane fitting")
        }
        
        // Calculate centroid
        let centroid = positions.reduce(simd_float3(0, 0, 0), +) / Float(positions.count)
        
        // For simple cases, use cross product of first three points
        if positions.count == 3 {
            let v1 = positions[1] - positions[0]
            let v2 = positions[2] - positions[0]
            let normal = simd_normalize(simd_cross(v1, v2))
            return (normal, centroid)
        }
        
        // For more points, use PCA (simplified version)
        // In a full implementation, this would use proper principal component analysis
        let v1 = simd_normalize(positions[1] - positions[0])
        let v2 = simd_normalize(positions[2] - positions[0])
        let normal = simd_normalize(simd_cross(v1, v2))
        
        return (normal, centroid)
    }
    
    /// Project 3D points onto a 2D plane for area calculations
    private func projectOntoPlane(positions: [simd_float3], normal: simd_float3, centroid: simd_float3) -> [simd_float2] {
        // Create orthonormal basis for the plane
        let up = abs(simd_dot(normal, simd_float3(0, 1, 0))) < 0.9 ? simd_float3(0, 1, 0) : simd_float3(1, 0, 0)
        let u = simd_normalize(simd_cross(normal, up))
        let v = simd_cross(normal, u)
        
        // Project each point onto the plane
        return positions.map { position in
            let relative = position - centroid
            let x = simd_dot(relative, u)
            let y = simd_dot(relative, v)
            return simd_float2(x, y)
        }
    }
    
    /// Check if points are coplanar within a tolerance
    public func arePointsCoplanar(positions: [simd_float3], tolerance: Float = 0.01) -> Bool {
        guard positions.count >= 4 else { return true } // 3 or fewer points are always coplanar
        
        do {
            let (normal, centroid) = try calculateBestFitPlane(positions: Array(positions.prefix(3)))
            
            // Check if all other points lie on the plane within tolerance
            for i in 3..<positions.count {
                let distance = abs(simd_dot(positions[i] - centroid, normal))
                if distance > tolerance {
                    return false
                }
            }
            
            return true
        } catch {
            return false
        }
    }
    
    /// Calculate the convex hull of a set of 2D points (simplified Graham scan)
    public func calculateConvexHull2D(points: [simd_float2]) -> [simd_float2] {
        guard points.count >= 3 else { return points }
        
        // Sort points by x-coordinate (and by y-coordinate if x is equal)
        let sortedPoints = points.sorted { point1, point2 in
            if point1.x == point2.x {
                return point1.y < point2.y
            }
            return point1.x < point2.x
        }
        
        // Build lower hull
        var lower: [simd_float2] = []
        for point in sortedPoints {
            while lower.count >= 2 && crossProduct(lower[lower.count-2], lower[lower.count-1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        
        // Build upper hull
        var upper: [simd_float2] = []
        for point in sortedPoints.reversed() {
            while upper.count >= 2 && crossProduct(upper[upper.count-2], upper[upper.count-1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        
        // Remove last point of each half because it's repeated
        lower.removeLast()
        upper.removeLast()
        
        return lower + upper
    }
    
    /// Calculate cross product for 2D points (z-component of 3D cross product)
    private func crossProduct(_ p1: simd_float2, _ p2: simd_float2, _ p3: simd_float2) -> Float {
        return (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
    }
    
    /// Calculate the center point of a set of positions
    public func calculateCentroid(positions: [simd_float3]) -> simd_float3 {
        guard !positions.isEmpty else { return simd_float3(0, 0, 0) }
        
        let sum = positions.reduce(simd_float3(0, 0, 0), +)
        return sum / Float(positions.count)
    }
    
    /// Calculate bounding box of a set of positions
    public func calculateBoundingBox(positions: [simd_float3]) -> (min: simd_float3, max: simd_float3, size: simd_float3) {
        guard !positions.isEmpty else {
            let zero = simd_float3(0, 0, 0)
            return (zero, zero, zero)
        }
        
        var minPoint = positions[0]
        var maxPoint = positions[0]
        
        for position in positions {
            minPoint = simd_min(minPoint, position)
            maxPoint = simd_max(maxPoint, position)
        }
        
        let size = maxPoint - minPoint
        return (minPoint, maxPoint, size)
    }
    
    /// Check if a polygon is convex
    public func isPolygonConvex(points: [simd_float2]) -> Bool {
        guard points.count >= 3 else { return true }
        
        var sign: Float = 0
        let n = points.count
        
        for i in 0..<n {
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            
            let cross = crossProduct(p1, p2, p3)
            
            if abs(cross) > 1e-6 { // Not zero within tolerance
                if sign == 0 {
                    sign = cross > 0 ? 1 : -1
                } else if (cross > 0 ? 1 : -1) != sign {
                    return false // Found different orientation
                }
            }
        }
        
        return true
    }
    
    /// Calculate the area of intersection between two polygons (simplified)
    public func calculatePolygonIntersectionArea(polygon1: [simd_float2], polygon2: [simd_float2]) -> Float {
        // This is a complex computational geometry problem
        // For now, return 0 as a placeholder
        // A full implementation would use Sutherland-Hodgman clipping or similar algorithm
        return 0.0
    }
    
    /// Simplify a polygon by removing collinear points
    public func simplifyPolygon(points: [simd_float2], tolerance: Float = 0.01) -> [simd_float2] {
        guard points.count > 2 else { return points }
        
        var simplified: [simd_float2] = [points[0]]
        
        for i in 1..<(points.count - 1) {
            let prev = simplified.last!
            let current = points[i]
            let next = points[i + 1]
            
            // Check if current point is collinear with prev and next
            let cross = abs(crossProduct(prev, current, next))
            
            if cross > tolerance {
                simplified.append(current)
            }
        }
        
        simplified.append(points.last!)
        
        return simplified
    }
}

// MARK: - Accuracy Assessor

public class AccuracyAssessor {
    
    public init() {}
    
    /// Assess the accuracy of a measurement based on various factors
    public func assessMeasurementAccuracy(
        measurementType: MeasurementType,
        points: [MeasurementPoint],
        value: MeasurementValue,
        environment: MeasurementEnvironment
    ) -> MeasurementAccuracy {
        
        var factors: [AccuracyFactor] = []
        var baseScore: Float = 0.8 // Start with good base score
        var errorMargin: Float = 0.02 // Base 2cm error margin
        
        // Point-based assessment
        let pointAssessment = assessPointsAccuracy(points: points)
        baseScore *= pointAssessment.score
        errorMargin += pointAssessment.additionalError
        factors.append(contentsOf: pointAssessment.factors)
        
        // Measurement type specific assessment
        let typeAssessment = assessMeasurementTypeAccuracy(type: measurementType, points: points)
        baseScore *= typeAssessment.score
        errorMargin += typeAssessment.additionalError
        factors.append(contentsOf: typeAssessment.factors)
        
        // Environmental assessment
        let envAssessment = assessEnvironmentalFactors(environment: environment)
        baseScore *= envAssessment.score
        errorMargin += envAssessment.additionalError
        factors.append(contentsOf: envAssessment.factors)
        
        // Determine accuracy level
        let level = determineAccuracyLevel(score: baseScore)
        
        return MeasurementAccuracy(
            level: level,
            confidenceScore: baseScore,
            errorMargin: errorMargin,
            factors: factors
        )
    }
    
    private func assessPointsAccuracy(points: [MeasurementPoint]) -> (score: Float, additionalError: Float, factors: [AccuracyFactor]) {
        var score: Float = 1.0
        var additionalError: Float = 0.0
        var factors: [AccuracyFactor] = []
        
        // Average point confidence
        let averageConfidence = points.map { $0.confidence }.reduce(0, +) / Float(points.count)
        score *= averageConfidence
        
        if averageConfidence < 0.6 {
            factors.append(.lowConfidence)
            additionalError += 0.01
        }
        
        // Average tracking quality
        let averageTrackingQuality = points.map { $0.trackingQuality }.reduce(0, +) / Float(points.count)
        score *= averageTrackingQuality
        
        if averageTrackingQuality < 0.6 {
            factors.append(.unstableTracking)
            additionalError += 0.015
        }
        
        // Point distribution (for multi-point measurements)
        if points.count > 2 {
            let distributionScore = assessPointDistribution(points: points)
            score *= distributionScore
        }
        
        return (score, additionalError, factors)
    }
    
    private func assessMeasurementTypeAccuracy(type: MeasurementType, points: [MeasurementPoint]) -> (score: Float, additionalError: Float, factors: [AccuracyFactor]) {
        var score: Float = 1.0
        var additionalError: Float = 0.0
        var factors: [AccuracyFactor] = []
        
        switch type {
        case .distance, .height:
            // Distance measurements are generally most accurate
            let distance = simd_distance(points[0].position, points[1].position)
            if distance > 10.0 {
                score *= 0.8
                additionalError += distance * 0.002 // 0.2cm per meter beyond 10m
                factors.append(.longDistance)
            }
            
        case .area:
            // Area accuracy depends on polygon regularity
            if points.count > 4 {
                score *= 0.9 // Slight penalty for complex polygons
            }
            
        case .volume:
            // Volume is least accurate due to 3D complexity
            score *= 0.7
            additionalError += 0.05
            
        case .angle:
            // Angle accuracy depends on arm lengths
            let arm1Length = simd_distance(points[1].position, points[0].position)
            let arm2Length = simd_distance(points[1].position, points[2].position)
            
            if min(arm1Length, arm2Length) < 0.1 {
                score *= 0.6 // Short arms reduce angle accuracy
                additionalError += 5.0 // 5 degrees additional error
            }
            
        case .perimeter:
            // Perimeter accuracy similar to area
            score *= 0.85
        }
        
        return (score, additionalError, factors)
    }
    
    private func assessEnvironmentalFactors(environment: MeasurementEnvironment) -> (score: Float, additionalError: Float, factors: [AccuracyFactor]) {
        var score: Float = 1.0
        var additionalError: Float = 0.0
        var factors: [AccuracyFactor] = []
        
        // Lighting conditions
        switch environment.lighting {
        case .poor:
            score *= 0.7
            additionalError += 0.01
            factors.append(.poorLighting)
        case .excellent:
            score *= 1.1 // Bonus for excellent lighting
        default:
            break
        }
        
        // Surface reflectivity
        if environment.hasReflectiveSurfaces {
            score *= 0.8
            additionalError += 0.005
            factors.append(.surfaceReflection)
        }
        
        // Movement during measurement
        if environment.deviceMovementSpeed > 0.5 {
            score *= 0.7
            additionalError += 0.01
            factors.append(.fastMovement)
        }
        
        return (score, additionalError, factors)
    }
    
    private func assessPointDistribution(points: [MeasurementPoint]) -> Float {
        // Check if points are well distributed (not clustered)
        let positions = points.map { $0.position }
        let centroid = positions.reduce(simd_float3(0, 0, 0), +) / Float(positions.count)
        
        let distances = positions.map { simd_distance($0, centroid) }
        let averageDistance = distances.reduce(0, +) / Float(distances.count)
        
        if averageDistance < 0.1 {
            return 0.6 // Points too clustered
        }
        
        return 1.0
    }
    
    private func determineAccuracyLevel(score: Float) -> AccuracyLevel {
        if score >= 0.9 {
            return .excellent
        } else if score >= 0.8 {
            return .good
        } else if score >= 0.6 {
            return .fair
        } else if score >= 0.4 {
            return .poor
        } else {
            return .unreliable
        }
    }
}

// MARK: - Supporting Types

public struct MeasurementEnvironment {
    public let lighting: LightingCondition
    public let hasReflectiveSurfaces: Bool
    public let deviceMovementSpeed: Float // m/s
    public let temperature: Float? // For material expansion considerations
    public let humidity: Float? // For material considerations
    
    public init(
        lighting: LightingCondition = .good,
        hasReflectiveSurfaces: Bool = false,
        deviceMovementSpeed: Float = 0.0,
        temperature: Float? = nil,
        humidity: Float? = nil
    ) {
        self.lighting = lighting
        self.hasReflectiveSurfaces = hasReflectiveSurfaces
        self.deviceMovementSpeed = deviceMovementSpeed
        self.temperature = temperature
        self.humidity = humidity
    }
}