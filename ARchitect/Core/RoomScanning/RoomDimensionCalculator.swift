import Foundation
import simd
import ARKit

// MARK: - Room Dimension Calculator
public class RoomDimensionCalculator {
    private let confidenceThreshold: Float = 0.7
    private let minimumWallCount = 2
    private let maximumRoomSize: Float = 50.0 // 50 meters maximum
    private let minimumRoomSize: Float = 0.5 // 0.5 meters minimum
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Calculate room dimensions from merged planes
    public func calculateDimensions(from mergedPlanes: [MergedPlane]) throws -> RoomDimensions {
        guard !mergedPlanes.isEmpty else {
            throw RoomDimensionError.insufficientData("No planes provided")
        }
        
        logDebug("Calculating room dimensions", category: .ar, context: LogContext(customData: [
            "total_planes": mergedPlanes.count,
            "floor_planes": mergedPlanes.filter { $0.type == .floor }.count,
            "wall_planes": mergedPlanes.filter { $0.type == .wall }.count,
            "ceiling_planes": mergedPlanes.filter { $0.type == .ceiling }.count
        ]))
        
        // Separate planes by type
        let floorPlanes = mergedPlanes.filter { $0.type == .floor }
        let wallPlanes = mergedPlanes.filter { $0.type == .wall }
        let ceilingPlanes = mergedPlanes.filter { $0.type == .ceiling }
        
        // Calculate dimensions using different strategies
        let dimensions = try calculateDimensionsWithMultipleStrategies(
            floorPlanes: floorPlanes,
            wallPlanes: wallPlanes,
            ceilingPlanes: ceilingPlanes
        )
        
        // Validate calculated dimensions
        try validateDimensions(dimensions)
        
        logDebug("Room dimensions calculated", category: .ar, context: LogContext(customData: [
            "width": dimensions.width,
            "length": dimensions.length,
            "height": dimensions.height,
            "area": dimensions.area,
            "volume": dimensions.volume,
            "confidence": dimensions.confidence
        ]))
        
        return dimensions
    }
    
    // MARK: - Dimension Calculation Strategies
    
    private func calculateDimensionsWithMultipleStrategies(
        floorPlanes: [MergedPlane],
        wallPlanes: [MergedPlane],
        ceilingPlanes: [MergedPlane]
    ) throws -> RoomDimensions {
        
        var results: [RoomDimensions] = []
        var confidences: [Float] = []
        
        // Strategy 1: Floor-based calculation
        if !floorPlanes.isEmpty {
            if let floorDimensions = try? calculateDimensionsFromFloor(floorPlanes) {
                results.append(floorDimensions)
                confidences.append(0.8) // High confidence for floor-based
            }
        }
        
        // Strategy 2: Wall-based calculation
        if wallPlanes.count >= minimumWallCount {
            if let wallDimensions = try? calculateDimensionsFromWalls(wallPlanes) {
                results.append(wallDimensions)
                confidences.append(0.7) // Medium confidence for wall-based
            }
        }
        
        // Strategy 3: Ceiling-based calculation
        if !ceilingPlanes.isEmpty {
            if let ceilingDimensions = try? calculateDimensionsFromCeiling(ceilingPlanes) {
                results.append(ceilingDimensions)
                confidences.append(0.6) // Lower confidence for ceiling-based
            }
        }
        
        // Strategy 4: Bounding box calculation (fallback)
        let allPlanes = floorPlanes + wallPlanes + ceilingPlanes
        if let boundingDimensions = try? calculateDimensionsFromBoundingBox(allPlanes) {
            results.append(boundingDimensions)
            confidences.append(0.5) // Lowest confidence for bounding box
        }
        
        guard !results.isEmpty else {
            throw RoomDimensionError.calculationFailed("No valid calculation strategy succeeded")
        }
        
        // Combine results using weighted average
        return combineResults(results, confidences: confidences)
    }
    
    // MARK: Floor-Based Calculation
    
    private func calculateDimensionsFromFloor(_ floorPlanes: [MergedPlane]) throws -> RoomDimensions {
        guard !floorPlanes.isEmpty else {
            throw RoomDimensionError.insufficientData("No floor planes provided")
        }
        
        // Use the largest floor plane (most likely the main floor)
        let mainFloor = floorPlanes.max { $0.area < $1.area }!
        
        // Calculate width and length from floor geometry
        let floorBounds = mainFloor.bounds
        let width = floorBounds.size.x
        let length = floorBounds.size.z
        
        // Estimate height using geometric analysis
        let height = estimateHeightFromFloor(mainFloor, floorPlanes: floorPlanes)
        
        let confidence = calculateFloorBasedConfidence(mainFloor, estimatedHeight: height)
        
        return RoomDimensions(
            width: width,
            length: length,
            height: height,
            confidence: confidence
        )
    }
    
    private func estimateHeightFromFloor(_ mainFloor: MergedPlane, floorPlanes: [MergedPlane]) -> Float {
        // Default room height if no other information available
        var estimatedHeight: Float = 2.4 // Standard room height
        
        // Try to find ceiling planes at consistent height above floor
        let floorHeight = mainFloor.center.y
        
        // Look for surfaces significantly above the floor
        let potentialCeilings = floorPlanes.filter { plane in
            let heightDifference = plane.center.y - floorHeight
            return heightDifference > 1.8 && heightDifference < 4.0 // Reasonable ceiling height range
        }
        
        if let ceiling = potentialCeilings.first {
            estimatedHeight = ceiling.center.y - floorHeight
        }
        
        return max(2.0, min(estimatedHeight, 5.0)) // Clamp to reasonable range
    }
    
    private func calculateFloorBasedConfidence(_ floor: MergedPlane, estimatedHeight: Float) -> Float {
        var confidence = floor.confidence
        
        // Adjust confidence based on floor area (larger floors are more reliable)
        let areaBonus = min(floor.area / 20.0, 0.2) // Up to 20% bonus for large floors
        confidence += areaBonus
        
        // Adjust confidence based on geometry regularity
        let regularityScore = calculateGeometryRegularity(floor.geometry)
        confidence *= regularityScore
        
        // Adjust confidence based on height estimation reliability
        if estimatedHeight > 1.8 && estimatedHeight < 4.0 {
            confidence += 0.1 // Bonus for reasonable height
        }
        
        return min(confidence, 1.0)
    }
    
    // MARK: Wall-Based Calculation
    
    private func calculateDimensionsFromWalls(_ wallPlanes: [MergedPlane]) throws -> RoomDimensions {
        guard wallPlanes.count >= minimumWallCount else {
            throw RoomDimensionError.insufficientData("Insufficient wall planes")
        }
        
        // Group walls by orientation to find perpendicular pairs
        let wallGroups = groupWallsByOrientation(wallPlanes)
        
        guard wallGroups.count >= 2 else {
            throw RoomDimensionError.calculationFailed("Cannot find perpendicular walls")
        }
        
        // Find the two most perpendicular wall groups
        let (group1, group2) = findMostPerpendicularGroups(wallGroups)
        
        // Calculate room dimensions from wall positions
        let width = calculateDistanceBetweenWallGroups(group1)
        let length = calculateDistanceBetweenWallGroups(group2)
        let height = calculateHeightFromWalls(wallPlanes)
        
        let confidence = calculateWallBasedConfidence(wallPlanes, width: width, length: length, height: height)
        
        return RoomDimensions(
            width: width,
            length: length,
            height: height,
            confidence: confidence
        )
    }
    
    private func groupWallsByOrientation(_ walls: [MergedPlane]) -> [[MergedPlane]] {
        var groups: [[MergedPlane]] = []
        let orientationThreshold: Float = 0.1 // 10-degree tolerance
        
        for wall in walls {
            let normal = wall.normal
            
            // Find existing group with similar orientation
            var foundGroup = false
            for i in 0..<groups.count {
                if let firstWall = groups[i].first {
                    let similarity = abs(simd_dot(normal, firstWall.normal))
                    if similarity > (1.0 - orientationThreshold) {
                        groups[i].append(wall)
                        foundGroup = true
                        break
                    }
                }
            }
            
            if !foundGroup {
                groups.append([wall])
            }
        }
        
        return groups
    }
    
    private func findMostPerpendicularGroups(_ groups: [[MergedPlane]]) -> ([MergedPlane], [MergedPlane]) {
        var bestGroup1: [MergedPlane] = []
        var bestGroup2: [MergedPlane] = []
        var bestPerpendicularityScore: Float = 0
        
        for i in 0..<groups.count {
            for j in (i+1)..<groups.count {
                if let wall1 = groups[i].first, let wall2 = groups[j].first {
                    let perpendicularity = abs(simd_dot(wall1.normal, wall2.normal))
                    let score = 1.0 - perpendicularity // Lower dot product means more perpendicular
                    
                    if score > bestPerpendicularityScore {
                        bestPerpendicularityScore = score
                        bestGroup1 = groups[i]
                        bestGroup2 = groups[j]
                    }
                }
            }
        }
        
        return (bestGroup1, bestGroup2)
    }
    
    private func calculateDistanceBetweenWallGroups(_ walls: [MergedPlane]) -> Float {
        guard walls.count >= 2 else { return 0 }
        
        // Find the two walls that are farthest apart
        var maxDistance: Float = 0
        
        for i in 0..<walls.count {
            for j in (i+1)..<walls.count {
                let distance = simd_distance(walls[i].center, walls[j].center)
                maxDistance = max(maxDistance, distance)
            }
        }
        
        return maxDistance
    }
    
    private func calculateHeightFromWalls(_ walls: [MergedPlane]) -> Float {
        // Find the average height of walls
        let heights = walls.map { $0.bounds.size.y }
        let averageHeight = heights.reduce(0, +) / Float(heights.count)
        
        // Use the maximum height if significantly different from average
        let maxHeight = heights.max() ?? averageHeight
        
        if maxHeight > averageHeight * 1.5 {
            return maxHeight
        } else {
            return averageHeight
        }
    }
    
    private func calculateWallBasedConfidence(_ walls: [MergedPlane], width: Float, length: Float, height: Float) -> Float {
        let baseConfidence = walls.map { $0.confidence }.reduce(0, +) / Float(walls.count)
        
        // Adjust based on wall count (more walls = higher confidence)
        let wallCountBonus = min(Float(walls.count - minimumWallCount) * 0.1, 0.3)
        
        // Adjust based on dimension reasonableness
        let dimensionScore = calculateDimensionReasonability(width: width, length: length, height: height)
        
        return min(baseConfidence + wallCountBonus, 1.0) * dimensionScore
    }
    
    // MARK: Ceiling-Based Calculation
    
    private func calculateDimensionsFromCeiling(_ ceilingPlanes: [MergedPlane]) throws -> RoomDimensions {
        guard !ceilingPlanes.isEmpty else {
            throw RoomDimensionError.insufficientData("No ceiling planes provided")
        }
        
        // Use the largest ceiling plane
        let mainCeiling = ceilingPlanes.max { $0.area < $1.area }!
        
        let ceilingBounds = mainCeiling.bounds
        let width = ceilingBounds.size.x
        let length = ceilingBounds.size.z
        
        // Estimate height from ceiling position
        let height = abs(mainCeiling.center.y) // Assuming floor is at y=0
        
        let confidence = calculateCeilingBasedConfidence(mainCeiling, estimatedHeight: height)
        
        return RoomDimensions(
            width: width,
            length: length,
            height: height,
            confidence: confidence
        )
    }
    
    private func calculateCeilingBasedConfidence(_ ceiling: MergedPlane, estimatedHeight: Float) -> Float {
        var confidence = ceiling.confidence * 0.8 // Ceiling-based is less reliable
        
        // Adjust based on height reasonableness
        if estimatedHeight > 1.8 && estimatedHeight < 4.0 {
            confidence += 0.1
        } else {
            confidence *= 0.7 // Penalty for unreasonable height
        }
        
        return min(confidence, 1.0)
    }
    
    // MARK: Bounding Box Calculation (Fallback)
    
    private func calculateDimensionsFromBoundingBox(_ planes: [MergedPlane]) throws -> RoomDimensions {
        guard !planes.isEmpty else {
            throw RoomDimensionError.insufficientData("No planes for bounding box calculation")
        }
        
        let roomBounds = RoomBounds(from: planes)
        
        return RoomDimensions(
            width: roomBounds.size.x,
            length: roomBounds.size.z,
            height: roomBounds.size.y,
            confidence: 0.5 // Low confidence for bounding box approach
        )
    }
    
    // MARK: Result Combination
    
    private func combineResults(_ results: [RoomDimensions], confidences: [Float]) -> RoomDimensions {
        guard !results.isEmpty else {
            return RoomDimensions(width: 0, length: 0, height: 0, confidence: 0)
        }
        
        if results.count == 1 {
            return results[0]
        }
        
        // Weighted average based on confidence
        let totalConfidence = confidences.reduce(0, +)
        guard totalConfidence > 0 else {
            return results[0] // Fallback to first result
        }
        
        var weightedWidth: Float = 0
        var weightedLength: Float = 0
        var weightedHeight: Float = 0
        
        for i in 0..<results.count {
            let weight = confidences[i] / totalConfidence
            weightedWidth += results[i].width * weight
            weightedLength += results[i].length * weight
            weightedHeight += results[i].height * weight
        }
        
        // Calculate combined confidence
        let maxConfidence = confidences.max() ?? 0
        let averageConfidence = confidences.reduce(0, +) / Float(confidences.count)
        let combinedConfidence = (maxConfidence + averageConfidence) / 2.0
        
        return RoomDimensions(
            width: weightedWidth,
            length: weightedLength,
            height: weightedHeight,
            confidence: combinedConfidence
        )
    }
    
    // MARK: Utility Methods
    
    private func calculateGeometryRegularity(_ geometry: [simd_float3]) -> Float {
        guard geometry.count > 3 else { return 0.5 }
        
        // Calculate how close the geometry is to a rectangle
        // This is a simplified regularity check
        let bounds = PlaneBounds(points: geometry)
        let expectedArea = bounds.size.x * bounds.size.z
        let actualArea = calculatePolygonArea(geometry)
        
        let regularityScore = min(actualArea / expectedArea, 1.0)
        return max(regularityScore, 0.3) // Minimum score to avoid extreme penalties
    }
    
    private func calculatePolygonArea(_ points: [simd_float3]) -> Float {
        guard points.count >= 3 else { return 0 }
        
        var area: Float = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            area += points[i].x * points[j].z - points[j].x * points[i].z
        }
        
        return abs(area) / 2.0
    }
    
    private func calculateDimensionReasonability(width: Float, length: Float, height: Float) -> Float {
        var score: Float = 1.0
        
        // Check if dimensions are within reasonable bounds
        if width < minimumRoomSize || width > maximumRoomSize {
            score *= 0.5
        }
        
        if length < minimumRoomSize || length > maximumRoomSize {
            score *= 0.5
        }
        
        if height < 1.8 || height > 5.0 {
            score *= 0.7
        }
        
        // Check aspect ratio reasonability
        let aspectRatio = max(width, length) / min(width, length)
        if aspectRatio > 10.0 { // Very elongated rooms are less likely
            score *= 0.8
        }
        
        return max(score, 0.1) // Minimum score
    }
    
    private func validateDimensions(_ dimensions: RoomDimensions) throws {
        guard dimensions.width > 0 && dimensions.length > 0 && dimensions.height > 0 else {
            throw RoomDimensionError.invalidDimensions("Dimensions must be positive")
        }
        
        guard dimensions.width <= maximumRoomSize && 
              dimensions.length <= maximumRoomSize && 
              dimensions.height <= maximumRoomSize else {
            throw RoomDimensionError.invalidDimensions("Dimensions exceed maximum allowed size")
        }
        
        guard dimensions.confidence > 0 else {
            throw RoomDimensionError.invalidDimensions("Confidence must be positive")
        }
    }
}

// MARK: - Room Dimension Error Types
public enum RoomDimensionError: Error, LocalizedError {
    case insufficientData(String)
    case calculationFailed(String)
    case invalidDimensions(String)
    
    public var errorDescription: String? {
        switch self {
        case .insufficientData(let reason):
            return "Insufficient data for dimension calculation: \(reason)"
        case .calculationFailed(let reason):
            return "Dimension calculation failed: \(reason)"
        case .invalidDimensions(let reason):
            return "Invalid dimensions: \(reason)"
        }
    }
}