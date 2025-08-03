import Foundation
import simd

// MARK: - Scan Quality Assessor
public class ScanQualityAssessor {
    private let minAcceptableScore: Float = 0.3
    private let excellentScoreThreshold: Float = 0.9
    private let goodScoreThreshold: Float = 0.8
    private let fairScoreThreshold: Float = 0.7
    private let poorScoreThreshold: Float = 0.5
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Assess the overall quality of a room scan
    public func assessQuality(
        detectedPlanes: [DetectedPlane],
        mergedPlanes: [MergedPlane],
        roomDimensions: RoomDimensions?,
        scanDuration: TimeInterval,
        trackingQuality: Float,
        issues: [ScanIssue]
    ) -> ScanQuality {
        
        logDebug("Assessing scan quality", category: .ar, context: LogContext(customData: [
            "detected_planes": detectedPlanes.count,
            "merged_planes": mergedPlanes.count,
            "scan_duration": scanDuration,
            "tracking_quality": trackingQuality,
            "issues_count": issues.count
        ]))
        
        // Calculate individual quality metrics
        let completeness = calculateCompleteness(detectedPlanes: detectedPlanes, mergedPlanes: mergedPlanes)
        let accuracy = calculateAccuracy(detectedPlanes: detectedPlanes, mergedPlanes: mergedPlanes, roomDimensions: roomDimensions)
        let coverage = calculateCoverage(mergedPlanes: mergedPlanes)
        let planeQuality = calculatePlaneQuality(detectedPlanes: detectedPlanes, mergedPlanes: mergedPlanes)
        let trackingStability = min(trackingQuality, 1.0)
        
        // Calculate overall score with weighted factors
        let overallScore = calculateOverallScore(
            completeness: completeness,
            accuracy: accuracy,
            coverage: coverage,
            planeQuality: planeQuality,
            trackingStability: trackingStability,
            scanDuration: scanDuration,
            issues: issues
        )
        
        // Generate recommendations
        let recommendations = generateRecommendations(
            completeness: completeness,
            accuracy: accuracy,
            coverage: coverage,
            planeQuality: planeQuality,
            trackingStability: trackingStability,
            issues: issues
        )
        
        let quality = ScanQuality(
            overallScore: overallScore,
            completeness: completeness,
            accuracy: accuracy,
            coverage: coverage,
            planeQuality: planeQuality,
            trackingStability: trackingStability,
            issues: issues,
            recommendations: recommendations
        )
        
        logDebug("Scan quality assessment completed", category: .ar, context: LogContext(customData: [
            "overall_score": overallScore,
            "grade": quality.grade.rawValue,
            "completeness": completeness,
            "accuracy": accuracy,
            "coverage": coverage,
            "plane_quality": planeQuality,
            "tracking_stability": trackingStability
        ]))
        
        return quality
    }
    
    // MARK: - Completeness Assessment
    
    private func calculateCompleteness(detectedPlanes: [DetectedPlane], mergedPlanes: [MergedPlane]) -> Float {
        // Completeness is based on whether we have essential room components
        var completenessScore: Float = 0.0
        
        let floorPlanes = mergedPlanes.filter { $0.type == .floor }
        let wallPlanes = mergedPlanes.filter { $0.type == .wall }
        let ceilingPlanes = mergedPlanes.filter { $0.type == .ceiling }
        
        // Floor presence (essential) - 40% of completeness
        if !floorPlanes.isEmpty {
            let floorScore = min(Float(floorPlanes.count) / 1.0, 1.0) // One good floor is sufficient
            completenessScore += floorScore * 0.4
        }
        
        // Wall presence (essential) - 50% of completeness
        if !wallPlanes.isEmpty {
            let expectedWalls = 4 // Typical rectangular room
            let wallScore = min(Float(wallPlanes.count) / Float(expectedWalls), 1.0)
            completenessScore += wallScore * 0.5
        }
        
        // Ceiling presence (nice to have) - 10% of completeness
        if !ceilingPlanes.isEmpty {
            completenessScore += 0.1
        }
        
        // Bonus for having all plane types
        if !floorPlanes.isEmpty && !wallPlanes.isEmpty && !ceilingPlanes.isEmpty {
            completenessScore += 0.05 // 5% bonus
        }
        
        return min(completenessScore, 1.0)
    }
    
    // MARK: - Accuracy Assessment
    
    private func calculateAccuracy(
        detectedPlanes: [DetectedPlane],
        mergedPlanes: [MergedPlane],
        roomDimensions: RoomDimensions?
    ) -> Float {
        var accuracyScore: Float = 0.0
        var scoreComponents = 0
        
        // Plane confidence average - 30% of accuracy
        if !detectedPlanes.isEmpty {
            let avgPlaneConfidence = detectedPlanes.map { $0.confidence }.reduce(0, +) / Float(detectedPlanes.count)
            accuracyScore += avgPlaneConfidence * 0.3
            scoreComponents += 1
        }
        
        // Merged plane confidence - 30% of accuracy
        if !mergedPlanes.isEmpty {
            let avgMergedConfidence = mergedPlanes.map { $0.confidence }.reduce(0, +) / Float(mergedPlanes.count)
            accuracyScore += avgMergedConfidence * 0.3
            scoreComponents += 1
        }
        
        // Dimension confidence - 25% of accuracy
        if let dimensions = roomDimensions {
            accuracyScore += dimensions.confidence * 0.25
            scoreComponents += 1
        }
        
        // Geometric consistency - 15% of accuracy
        let geometryScore = calculateGeometricConsistency(mergedPlanes: mergedPlanes)
        accuracyScore += geometryScore * 0.15
        scoreComponents += 1
        
        return min(accuracyScore, 1.0)
    }
    
    private func calculateGeometricConsistency(mergedPlanes: [MergedPlane]) -> Float {
        guard mergedPlanes.count >= 2 else { return 0.5 }
        
        var consistencyScore: Float = 1.0
        let wallPlanes = mergedPlanes.filter { $0.type == .wall }
        
        // Check if walls are properly perpendicular
        if wallPlanes.count >= 2 {
            var perpendicularityScores: [Float] = []
            
            for i in 0..<wallPlanes.count {
                for j in (i+1)..<wallPlanes.count {
                    let dot = abs(simd_dot(wallPlanes[i].normal, wallPlanes[j].normal))
                    let perpendicularityScore = 1.0 - dot // Lower dot product = more perpendicular
                    perpendicularityScores.append(perpendicularityScore)
                }
            }
            
            if !perpendicularityScores.isEmpty {
                let avgPerpendicularity = perpendicularityScores.reduce(0, +) / Float(perpendicularityScores.count)
                consistencyScore *= (0.5 + avgPerpendicularity * 0.5) // Scale to 0.5-1.0 range
            }
        }
        
        // Check floor-wall alignment
        let floorPlanes = mergedPlanes.filter { $0.type == .floor }
        if !floorPlanes.isEmpty && !wallPlanes.isEmpty {
            let floor = floorPlanes[0]
            let floorHeight = floor.center.y
            
            // Check if walls start near floor level
            let wallFloorAlignment = wallPlanes.map { wall in
                let wallBottomHeight = wall.bounds.min.y
                let heightDifference = abs(wallBottomHeight - floorHeight)
                return max(0.0, 1.0 - heightDifference) // Closer to floor = higher score
            }.reduce(0, +) / Float(wallPlanes.count)
            
            consistencyScore *= (0.7 + wallFloorAlignment * 0.3)
        }
        
        return max(consistencyScore, 0.1)
    }
    
    // MARK: - Coverage Assessment
    
    private func calculateCoverage(mergedPlanes: [MergedPlane]) -> Float {
        // Coverage measures how much of the expected room surfaces are detected
        var coverageScore: Float = 0.0
        
        let floorPlanes = mergedPlanes.filter { $0.type == .floor }
        let wallPlanes = mergedPlanes.filter { $0.type == .wall }
        
        // Floor coverage - 50% of total coverage
        if !floorPlanes.isEmpty {
            let totalFloorArea = floorPlanes.map { $0.area }.reduce(0, +)
            // Normalize against expected room area (assume reasonable room size)
            let expectedMinArea: Float = 4.0 // 2m x 2m minimum room
            let floorCoverage = min(totalFloorArea / expectedMinArea, 1.0)
            coverageScore += floorCoverage * 0.5
        }
        
        // Wall coverage - 50% of total coverage
        if !wallPlanes.isEmpty {
            let totalWallArea = wallPlanes.map { $0.area }.reduce(0, +)
            // Estimate expected wall area based on floor area
            if !floorPlanes.isEmpty {
                let floorArea = floorPlanes.map { $0.area }.reduce(0, +)
                let estimatedRoomPerimeter = 4 * sqrt(floorArea) // Assume square room
                let estimatedWallHeight: Float = 2.5 // Standard ceiling height
                let expectedWallArea = estimatedRoomPerimeter * estimatedWallHeight
                
                let wallCoverage = min(totalWallArea / expectedWallArea, 1.0)
                coverageScore += wallCoverage * 0.5
            } else {
                // Fallback: assume each wall should be at least 2m² (1m x 2m)
                let expectedWalls = 4
                let minWallArea: Float = 2.0
                let expectedTotalWallArea = Float(expectedWalls) * minWallArea
                let wallCoverage = min(totalWallArea / expectedTotalWallArea, 1.0)
                coverageScore += wallCoverage * 0.5
            }
        }
        
        return min(coverageScore, 1.0)
    }
    
    // MARK: - Plane Quality Assessment
    
    private func calculatePlaneQuality(detectedPlanes: [DetectedPlane], mergedPlanes: [MergedPlane]) -> Float {
        var qualityScore: Float = 0.0
        var components = 0
        
        // Average detected plane area quality - 40% of plane quality
        if !detectedPlanes.isEmpty {
            let avgArea = detectedPlanes.map { $0.area }.reduce(0, +) / Float(detectedPlanes.count)
            let minGoodArea: Float = 1.0 // 1 square meter
            let areaQuality = min(avgArea / minGoodArea, 1.0)
            qualityScore += areaQuality * 0.4
            components += 1
        }
        
        // Merge efficiency - 30% of plane quality
        if !detectedPlanes.isEmpty && !mergedPlanes.isEmpty {
            let mergeEfficiency = Float(mergedPlanes.count) / Float(detectedPlanes.count)
            // Good merging should reduce plane count but not too aggressively
            let optimalEfficiency: Float = 0.3 // 30% of original planes after merging
            let efficiencyScore = 1.0 - abs(mergeEfficiency - optimalEfficiency) / optimalEfficiency
            qualityScore += max(efficiencyScore, 0.0) * 0.3
            components += 1
        }
        
        // Plane size distribution - 30% of plane quality
        if !mergedPlanes.isEmpty {
            let areas = mergedPlanes.map { $0.area }
            let avgArea = areas.reduce(0, +) / Float(areas.count)
            let areaVariance = areas.map { pow($0 - avgArea, 2) }.reduce(0, +) / Float(areas.count)
            let areaStdDev = sqrt(areaVariance)
            
            // Lower variance (more consistent plane sizes) is better
            let consistencyScore = max(0.0, 1.0 - (areaStdDev / avgArea))
            qualityScore += consistencyScore * 0.3
            components += 1
        }
        
        return components > 0 ? qualityScore : 0.5
    }
    
    // MARK: - Overall Score Calculation
    
    private func calculateOverallScore(
        completeness: Float,
        accuracy: Float,
        coverage: Float,
        planeQuality: Float,
        trackingStability: Float,
        scanDuration: TimeInterval,
        issues: [ScanIssue]
    ) -> Float {
        
        // Base score from weighted metrics
        var score = completeness * 0.25 +      // 25% - Most important
                   accuracy * 0.25 +          // 25% - Very important
                   coverage * 0.20 +          // 20% - Important
                   planeQuality * 0.15 +      // 15% - Moderately important
                   trackingStability * 0.15   // 15% - Moderately important
        
        // Apply scan duration modifier
        let durationModifier = calculateDurationModifier(scanDuration)
        score *= durationModifier
        
        // Apply issue penalties
        let issuePenalty = calculateIssuePenalty(issues)
        score *= (1.0 - issuePenalty)
        
        return max(min(score, 1.0), 0.0)
    }
    
    private func calculateDurationModifier(_ duration: TimeInterval) -> Float {
        // Optimal scan duration is between 30 seconds and 3 minutes
        let optimalMin: TimeInterval = 30
        let optimalMax: TimeInterval = 180
        
        if duration < optimalMin {
            // Too fast - might have missed details
            return Float(duration / optimalMin) * 0.8 + 0.2 // Scale from 0.2 to 1.0
        } else if duration <= optimalMax {
            // Optimal range
            return 1.0
        } else {
            // Too long - might indicate problems
            let excess = duration - optimalMax
            let penalty = min(Float(excess / 300), 0.3) // Max 30% penalty for very long scans
            return 1.0 - penalty
        }
    }
    
    private func calculateIssuePenalty(_ issues: [ScanIssue]) -> Float {
        var totalPenalty: Float = 0.0
        
        for issue in issues {
            let penalty: Float
            switch issue.severity {
            case .critical:
                penalty = 0.2 // 20% penalty
            case .high:
                penalty = 0.15 // 15% penalty
            case .medium:
                penalty = 0.1 // 10% penalty
            case .low:
                penalty = 0.05 // 5% penalty
            }
            
            totalPenalty += penalty
        }
        
        return min(totalPenalty, 0.6) // Maximum 60% penalty from issues
    }
    
    // MARK: - Recommendations Generation
    
    private func generateRecommendations(
        completeness: Float,
        accuracy: Float,
        coverage: Float,
        planeQuality: Float,
        trackingStability: Float,
        issues: [ScanIssue]
    ) -> [String] {
        
        var recommendations: [String] = []
        
        // Completeness recommendations
        if completeness < 0.7 {
            recommendations.append("Scan more surfaces to improve completeness - ensure you capture floor and all walls")
        }
        
        // Accuracy recommendations
        if accuracy < 0.7 {
            recommendations.append("Move more slowly and maintain good lighting for better accuracy")
        }
        
        // Coverage recommendations
        if coverage < 0.7 {
            recommendations.append("Cover more area of each surface - scan the entire floor and each wall section")
        }
        
        // Plane quality recommendations
        if planeQuality < 0.7 {
            recommendations.append("Focus on flat surfaces and avoid scanning furniture or clutter")
        }
        
        // Tracking stability recommendations
        if trackingStability < 0.7 {
            recommendations.append("Improve lighting conditions and reduce device movement speed")
        }
        
        // Issue-specific recommendations
        let criticalIssues = issues.filter { $0.severity == .critical }
        if !criticalIssues.isEmpty {
            recommendations.append("Address critical issues before finalizing the scan")
        }
        
        let trackingIssues = issues.filter { $0.type == .poorTracking || $0.type == .excessiveMotion }
        if trackingIssues.count > 2 {
            recommendations.append("Move device more slowly and ensure stable hand movements")
        }
        
        let lightingIssues = issues.filter { $0.type == .lowLighting }
        if !lightingIssues.isEmpty {
            recommendations.append("Improve room lighting or move to a better-lit area")
        }
        
        // General recommendations based on overall quality
        let overallScore = calculateOverallScore(
            completeness: completeness,
            accuracy: accuracy,
            coverage: coverage,
            planeQuality: planeQuality,
            trackingStability: trackingStability,
            scanDuration: 120, // Default duration for this calculation
            issues: issues
        )
        
        if overallScore >= excellentScoreThreshold {
            recommendations.append("Excellent scan quality! This scan is ready for use.")
        } else if overallScore >= goodScoreThreshold {
            recommendations.append("Good scan quality. Minor improvements could enhance accuracy.")
        } else if overallScore >= fairScoreThreshold {
            recommendations.append("Fair scan quality. Consider rescanning problem areas for better results.")
        } else {
            recommendations.append("Poor scan quality. Consider starting over with better conditions.")
        }
        
        return recommendations
    }
    
    // MARK: - Quality Validation
    
    /// Validate if a scan meets minimum quality requirements
    public func validateScanQuality(_ quality: ScanQuality) -> (isValid: Bool, reason: String?) {
        if quality.overallScore < minAcceptableScore {
            return (false, "Overall scan quality is too low (\(String(format: "%.1f", quality.overallScore * 100))%)")
        }
        
        if quality.completeness < 0.3 {
            return (false, "Scan is too incomplete - missing essential room surfaces")
        }
        
        if quality.accuracy < 0.3 {
            return (false, "Scan accuracy is too low - measurements may be unreliable")
        }
        
        let criticalIssues = quality.issues.filter { $0.severity == .critical }
        if criticalIssues.count > 2 {
            return (false, "Too many critical issues detected during scanning")
        }
        
        return (true, nil)
    }
}