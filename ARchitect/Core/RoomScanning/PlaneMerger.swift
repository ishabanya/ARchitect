import Foundation
import ARKit
import simd

// MARK: - Plane Merger
public class PlaneMerger {
    private var mergingThreshold: Float = 0.1 // 10cm default
    private var minPlaneArea: Float = 0.1 // 0.1 square meters default
    private var maxMergingDistance: Float = 0.5 // 50cm maximum distance for merging
    private var normalSimilarityThreshold: Float = 0.9 // Cosine similarity threshold
    
    public init() {}
    
    // MARK: - Configuration
    
    public func configure(mergingThreshold: Float, minPlaneArea: Float) {
        self.mergingThreshold = mergingThreshold
        self.minPlaneArea = minPlaneArea
        
        logDebug("Plane merger configured", category: .ar, context: LogContext(customData: [
            "merging_threshold": mergingThreshold,
            "min_plane_area": minPlaneArea
        ]))
    }
    
    // MARK: - Public Methods
    
    /// Merge detected planes into logical room surfaces
    public func mergePlanes(_ detectedPlanes: [DetectedPlane]) throws -> [MergedPlane] {
        guard !detectedPlanes.isEmpty else { return [] }
        
        logDebug("Starting plane merging", category: .ar, context: LogContext(customData: [
            "input_planes": detectedPlanes.count
        ]))
        
        // Separate planes by alignment
        let horizontalPlanes = detectedPlanes.filter { $0.alignment == .horizontal }
        let verticalPlanes = detectedPlanes.filter { $0.alignment == .vertical }
        
        var mergedPlanes: [MergedPlane] = []
        
        // Merge horizontal planes (floors, ceilings, surfaces)
        let mergedHorizontal = try mergeHorizontalPlanes(horizontalPlanes)
        mergedPlanes.append(contentsOf: mergedHorizontal)
        
        // Merge vertical planes (walls)
        let mergedVertical = try mergeVerticalPlanes(verticalPlanes)
        mergedPlanes.append(contentsOf: mergedVertical)
        
        // Validate merged planes
        let validatedPlanes = validateMergedPlanes(mergedPlanes)
        
        logDebug("Plane merging completed", category: .ar, context: LogContext(customData: [
            "input_planes": detectedPlanes.count,
            "output_planes": validatedPlanes.count,
            "horizontal_merged": mergedHorizontal.count,
            "vertical_merged": mergedVertical.count
        ]))
        
        return validatedPlanes
    }
    
    // MARK: - Horizontal Plane Merging
    
    private func mergeHorizontalPlanes(_ planes: [DetectedPlane]) throws -> [MergedPlane] {
        guard !planes.isEmpty else { return [] }
        
        // Group planes by height (Y coordinate)
        let heightGroups = groupPlanesByHeight(planes)
        var mergedPlanes: [MergedPlane] = []
        
        for (height, groupPlanes) in heightGroups {
            let merged = try mergeCoplanarHorizontalPlanes(groupPlanes, at: height)
            mergedPlanes.append(contentsOf: merged)
        }
        
        return mergedPlanes
    }
    
    private func groupPlanesByHeight(_ planes: [DetectedPlane]) -> [Float: [DetectedPlane]] {
        var groups: [Float: [DetectedPlane]] = [:]
        
        for plane in planes {
            let height = plane.center.y
            let roundedHeight = round(height / mergingThreshold) * mergingThreshold
            
            if groups[roundedHeight] == nil {
                groups[roundedHeight] = []
            }
            groups[roundedHeight]?.append(plane)
        }
        
        return groups
    }
    
    private func mergeCoplanarHorizontalPlanes(_ planes: [DetectedPlane], at height: Float) throws -> [MergedPlane] {
        guard !planes.isEmpty else { return [] }
        
        // Use clustering to merge adjacent planes
        let clusters = clusterAdjacentPlanes(planes)
        var mergedPlanes: [MergedPlane] = []
        
        for cluster in clusters {
            if let merged = try createMergedHorizontalPlane(from: cluster, at: height) {
                mergedPlanes.append(merged)
            }
        }
        
        return mergedPlanes
    }
    
    private func createMergedHorizontalPlane(from planes: [DetectedPlane], at height: Float) throws -> MergedPlane? {
        guard !planes.isEmpty else { return nil }
        
        // Combine all geometry points
        var allPoints: [simd_float3] = []
        for plane in planes {
            allPoints.append(contentsOf: plane.geometry)
        }
        
        // Calculate merged geometry using convex hull
        let mergedGeometry = calculateConvexHull(allPoints)
        guard !mergedGeometry.isEmpty else { return nil }
        
        // Calculate properties
        let area = calculatePolygonArea(mergedGeometry)
        guard area >= minPlaneArea else { return nil }
        
        let center = calculateCentroid(mergedGeometry)
        let bounds = PlaneBounds(points: mergedGeometry)
        let confidence = calculateMergedConfidence(planes)
        
        // Determine plane type based on height
        let planeType = determinePlaneType(height: height, area: area, bounds: bounds)
        
        return MergedPlane(
            type: planeType,
            sourceIDs: planes.map { $0.id },
            center: center,
            normal: simd_float3(0, 1, 0), // Horizontal planes have upward normal
            bounds: bounds,
            area: area,
            confidence: confidence,
            geometry: mergedGeometry
        )
    }
    
    private func determinePlaneType(height: Float, area: Float, bounds: PlaneBounds) -> MergedPlane.PlaneType {
        // Simple heuristic: lowest large horizontal plane is floor, highest is ceiling
        if height < -0.5 || (area > 2.0 && height < 0.5) { // Large plane near ground level
            return .floor
        } else if height > 2.0 { // High plane likely ceiling
            return .ceiling
        } else { // Mid-height planes are surfaces (tables, counters, etc.)
            return .surface
        }
    }
    
    // MARK: - Vertical Plane Merging
    
    private func mergeVerticalPlanes(_ planes: [DetectedPlane]) throws -> [MergedPlane] {
        guard !planes.isEmpty else { return [] }
        
        // Group planes by orientation (normal direction)
        let orientationGroups = groupPlanesByOrientation(planes)
        var mergedPlanes: [MergedPlane] = []
        
        for (normal, groupPlanes) in orientationGroups {
            let merged = try mergeCoplanarVerticalPlanes(groupPlanes, with: normal)
            mergedPlanes.append(contentsOf: merged)
        }
        
        return mergedPlanes
    }
    
    private func groupPlanesByOrientation(_ planes: [DetectedPlane]) -> [simd_float3: [DetectedPlane]] {
        var groups: [simd_float3: [DetectedPlane]] = [:]
        
        for plane in planes {
            // Calculate normal from transform (assuming vertical plane)
            let normal = simd_float3(plane.transform.columns.2.x, 0, plane.transform.columns.2.z)
            let normalizedNormal = simd_normalize(normal)
            
            // Round normal to merge similar orientations
            let roundedNormal = roundNormalToGrid(normalizedNormal)
            
            if groups[roundedNormal] == nil {
                groups[roundedNormal] = []
            }
            groups[roundedNormal]?.append(plane)
        }
        
        return groups
    }
    
    private func roundNormalToGrid(_ normal: simd_float3) -> simd_float3 {
        let gridSize: Float = 0.1
        return simd_float3(
            round(normal.x / gridSize) * gridSize,
            round(normal.y / gridSize) * gridSize,
            round(normal.z / gridSize) * gridSize
        )
    }
    
    private func mergeCoplanarVerticalPlanes(_ planes: [DetectedPlane], with normal: simd_float3) throws -> [MergedPlane] {
        guard !planes.isEmpty else { return [] }
        
        // Group by distance from origin along normal
        let distanceGroups = groupPlanesByDistance(planes, normal: normal)
        var mergedPlanes: [MergedPlane] = []
        
        for (_, groupPlanes) in distanceGroups {
            if let merged = try createMergedVerticalPlane(from: groupPlanes, normal: normal) {
                mergedPlanes.append(merged)
            }
        }
        
        return mergedPlanes
    }
    
    private func groupPlanesByDistance(_ planes: [DetectedPlane], normal: simd_float3) -> [Float: [DetectedPlane]] {
        var groups: [Float: [DetectedPlane]] = [:]
        
        for plane in planes {
            let distance = simd_dot(plane.center, normal)
            let roundedDistance = round(distance / mergingThreshold) * mergingThreshold
            
            if groups[roundedDistance] == nil {
                groups[roundedDistance] = []
            }
            groups[roundedDistance]?.append(plane)
        }
        
        return groups
    }
    
    private func createMergedVerticalPlane(from planes: [DetectedPlane], normal: simd_float3) throws -> MergedPlane? {
        guard !planes.isEmpty else { return nil }
        
        // Combine all geometry points
        var allPoints: [simd_float3] = []
        for plane in planes {
            allPoints.append(contentsOf: plane.geometry)
        }
        
        // Project points to 2D plane for merging
        let projectedPoints = projectPointsToPlane(allPoints, normal: normal)
        let mergedPolygon = calculateConvexHull2D(projectedPoints)
        
        // Project back to 3D
        let mergedGeometry = projectPointsFrom2D(mergedPolygon, normal: normal, points: allPoints)
        guard !mergedGeometry.isEmpty else { return nil }
        
        // Calculate properties
        let area = calculatePolygonArea(mergedGeometry)
        guard area >= minPlaneArea else { return nil }
        
        let center = calculateCentroid(mergedGeometry)
        let bounds = PlaneBounds(points: mergedGeometry)
        let confidence = calculateMergedConfidence(planes)
        
        return MergedPlane(
            type: .wall, // Vertical planes are typically walls
            sourceIDs: planes.map { $0.id },
            center: center,
            normal: normal,
            bounds: bounds,
            area: area,
            confidence: confidence,
            geometry: mergedGeometry
        )
    }
    
    // MARK: - Clustering Algorithms
    
    private func clusterAdjacentPlanes(_ planes: [DetectedPlane]) -> [[DetectedPlane]] {
        var clusters: [[DetectedPlane]] = []
        var visited = Set<UUID>()
        
        for plane in planes {
            if visited.contains(plane.id) { continue }
            
            let cluster = findConnectedPlanes(plane, in: planes, visited: &visited)
            if !cluster.isEmpty {
                clusters.append(cluster)
            }
        }
        
        return clusters
    }
    
    private func findConnectedPlanes(_ startPlane: DetectedPlane, in planes: [DetectedPlane], visited: inout Set<UUID>) -> [DetectedPlane] {
        var cluster: [DetectedPlane] = []
        var queue: [DetectedPlane] = [startPlane]
        
        while !queue.isEmpty {
            let currentPlane = queue.removeFirst()
            
            if visited.contains(currentPlane.id) { continue }
            visited.insert(currentPlane.id)
            cluster.append(currentPlane)
            
            // Find adjacent planes
            for plane in planes {
                if !visited.contains(plane.id) && areAdjacent(currentPlane, plane) {
                    queue.append(plane)
                }
            }
        }
        
        return cluster
    }
    
    private func areAdjacent(_ plane1: DetectedPlane, _ plane2: DetectedPlane) -> Bool {
        // Check if planes are close enough to merge
        let distance = simd_distance(plane1.center, plane2.center)
        guard distance <= maxMergingDistance else { return false }
        
        // Check if planes have similar normals (for same alignment)
        if plane1.alignment == plane2.alignment {
            // For same alignment, check if they're coplanar or adjacent
            return distance <= mergingThreshold * 3 // Allow some tolerance
        }
        
        return false
    }
    
    // MARK: - Geometry Calculations
    
    private func calculateConvexHull(_ points: [simd_float3]) -> [simd_float3] {
        guard points.count >= 3 else { return points }
        
        // Simple convex hull in 3D (using gift wrapping approach projected to best plane)
        // For simplicity, we'll project to XZ plane for horizontal surfaces
        let projectedPoints = points.map { simd_float2($0.x, $0.z) }
        let hull2D = calculateConvexHull2D(projectedPoints)
        
        // Map back to 3D using original Y values
        return hull2D.compactMap { point2D in
            // Find corresponding 3D point
            for point3D in points {
                if abs(point3D.x - point2D.x) < 0.01 && abs(point3D.z - point2D.y) < 0.01 {
                    return point3D
                }
            }
            return nil
        }
    }
    
    private func calculateConvexHull2D(_ points: [simd_float2]) -> [simd_float2] {
        guard points.count >= 3 else { return points }
        
        // Graham scan algorithm
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
    
    private func crossProduct(_ p1: simd_float2, _ p2: simd_float2, _ p3: simd_float2) -> Float {
        return (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
    }
    
    private func calculatePolygonArea(_ points: [simd_float3]) -> Float {
        guard points.count >= 3 else { return 0 }
        
        // Shoelace formula for polygon area (projected to best plane)
        var area: Float = 0
        
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            area += points[i].x * points[j].z - points[j].x * points[i].z
        }
        
        return abs(area) / 2.0
    }
    
    private func calculateCentroid(_ points: [simd_float3]) -> simd_float3 {
        guard !points.isEmpty else { return simd_float3(0, 0, 0) }
        
        let sum = points.reduce(simd_float3(0, 0, 0)) { $0 + $1 }
        return sum / Float(points.count)
    }
    
    private func calculateMergedConfidence(_ planes: [DetectedPlane]) -> Float {
        guard !planes.isEmpty else { return 0 }
        
        // Weighted average based on area
        let totalArea = planes.reduce(0) { $0 + $1.area }
        let weightedConfidence = planes.reduce(0) { $0 + ($1.confidence * $1.area) }
        
        return totalArea > 0 ? weightedConfidence / totalArea : 0
    }
    
    // MARK: - Projection Utilities
    
    private func projectPointsToPlane(_ points: [simd_float3], normal: simd_float3) -> [simd_float2] {
        // Create a coordinate system on the plane
        let up = abs(simd_dot(normal, simd_float3(0, 1, 0))) < 0.9 ? simd_float3(0, 1, 0) : simd_float3(1, 0, 0)
        let u = simd_normalize(simd_cross(normal, up))
        let v = simd_cross(normal, u)
        
        return points.map { point in
            simd_float2(simd_dot(point, u), simd_dot(point, v))
        }
    }
    
    private func projectPointsFrom2D(_ points2D: [simd_float2], normal: simd_float3, points: [simd_float3]) -> [simd_float3] {
        // This is a simplified back-projection
        // In practice, you'd need to maintain the coordinate system used in projection
        return points2D.compactMap { point2D in
            // Find closest original 3D point (simplified approach)
            var closestPoint: simd_float3?
            var minDistance: Float = Float.greatestFiniteMagnitude
            
            for point3D in points {
                let projected = simd_float2(point3D.x, point3D.z) // Simplified projection
                let distance = simd_distance(projected, point2D)
                
                if distance < minDistance {
                    minDistance = distance
                    closestPoint = point3D
                }
            }
            
            return closestPoint
        }
    }
    
    // MARK: - Validation
    
    private func validateMergedPlanes(_ planes: [MergedPlane]) -> [MergedPlane] {
        return planes.filter { plane in
            // Validate area
            guard plane.area >= minPlaneArea else { return false }
            
            // Validate geometry
            guard plane.geometry.count >= 3 else { return false }
            
            // Validate bounds
            guard plane.bounds.size.x > 0 && plane.bounds.size.z > 0 else { return false }
            
            return true
        }
    }
}

// MARK: - Plane Merger Error Types
public enum PlaneMergerError: Error, LocalizedError {
    case insufficientPoints
    case invalidGeometry
    case mergingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .insufficientPoints:
            return "Insufficient points to create merged plane"
        case .invalidGeometry:
            return "Invalid geometry detected during plane merging"
        case .mergingFailed(let reason):
            return "Plane merging failed: \(reason)"
        }
    }
}