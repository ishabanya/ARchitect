import Foundation
import ARKit

/// Analyzes AR tracking quality and provides recommendations following single responsibility principle
final class ARTrackingQualityAnalyzer {
    
    // MARK: - Properties
    private var qualityHistory: [TrackingQualitySnapshot] = []
    private let maxHistorySize = 100
    
    // MARK: - Quality Analysis
    
    /// Analyzes current tracking state and determines quality level
    /// - Parameters:
    ///   - trackingState: Current camera tracking state
    ///   - planeCount: Number of detected planes
    ///   - sessionDuration: How long the session has been running
    /// - Returns: Calculated tracking quality
    func analyzeTrackingQuality(
        trackingState: ARCamera.TrackingState,
        planeCount: Int,
        sessionDuration: TimeInterval
    ) -> ARTrackingQuality {
        let quality = calculateQuality(
            trackingState: trackingState,
            planeCount: planeCount,
            sessionDuration: sessionDuration
        )
        
        // Store in history
        addToHistory(TrackingQualitySnapshot(
            quality: quality,
            trackingState: trackingState,
            planeCount: planeCount,
            timestamp: Date()
        ))
        
        return quality
    }
    
    /// Gets tracking quality trends over time
    /// - Parameter duration: Time period to analyze (in seconds)
    /// - Returns: Quality trends analysis
    func getQualityTrends(for duration: TimeInterval = 60) -> TrackingQualityTrends {
        let cutoffTime = Date().addingTimeInterval(-duration)
        let recentHistory = qualityHistory.filter { $0.timestamp >= cutoffTime }
        
        guard !recentHistory.isEmpty else {
            return TrackingQualityTrends(
                averageQuality: .unavailable,
                qualityStability: .unstable,
                improvementTrend: .declining,
                recommendations: ["Initialize AR session to begin tracking"]
            )
        }
        
        let averageScore = recentHistory.map { $0.quality.score }.reduce(0, +) / Double(recentHistory.count)
        let averageQuality = qualityFromScore(averageScore)
        
        let stability = calculateStability(from: recentHistory)
        let trend = calculateTrend(from: recentHistory)
        let recommendations = generateRecommendations(
            averageQuality: averageQuality,
            stability: stability,
            trend: trend,
            recentHistory: recentHistory
        )
        
        return TrackingQualityTrends(
            averageQuality: averageQuality,
            qualityStability: stability,
            improvementTrend: trend,
            recommendations: recommendations
        )
    }
    
    /// Provides specific recommendations for improving tracking quality
    /// - Parameter currentState: Current tracking state
    /// - Returns: Array of actionable recommendations
    func getImprovementRecommendations(for currentState: ARCamera.TrackingState) -> [String] {
        switch currentState {
        case .notAvailable:
            return [
                "Ensure AR is supported on this device",
                "Check camera permissions",
                "Restart the AR session"
            ]
            
        case .normal:
            return [
                "Tracking is working well",
                "Continue current scanning pattern"
            ]
            
        case .limited(let reason):
            return getRecommendationsForLimitedTracking(reason: reason)
        }
    }
    
    /// Detects tracking issues and suggests solutions
    /// - Returns: Array of detected issues with solutions
    func detectTrackingIssues() -> [TrackingIssue] {
        var issues: [TrackingIssue] = []
        
        let recentHistory = qualityHistory.suffix(10)
        
        // Check for consistently poor quality
        let poorQualityCount = recentHistory.filter { $0.quality == .poor || $0.quality == .unavailable }.count
        if poorQualityCount >= 7 {
            issues.append(TrackingIssue(
                type: .consistentlyPoorQuality,
                severity: .high,
                description: "Tracking quality has been poor for an extended period",
                solutions: [
                    "Move to a well-lit area",
                    "Point camera at textured surfaces",
                    "Move device more slowly",
                    "Reset AR session"
                ]
            ))
        }
        
        // Check for rapid quality changes
        let qualityChanges = calculateQualityChanges(from: recentHistory)
        if qualityChanges > 5 {
            issues.append(TrackingIssue(
                type: .unstableTracking,
                severity: .medium,
                description: "Tracking quality is fluctuating rapidly",
                solutions: [
                    "Reduce device movement speed",
                    "Avoid pointing camera at reflective surfaces",
                    "Ensure consistent lighting"
                ]
            ))
        }
        
        // Check for lack of plane detection
        let latestSnapshot = recentHistory.last
        if let latest = latestSnapshot, latest.planeCount == 0 && latest.timestamp.timeIntervalSinceNow > -30 {
            issues.append(TrackingIssue(
                type: .noPlaneDetection,
                severity: .medium,
                description: "No planes detected after 30 seconds",
                solutions: [
                    "Point camera at flat surfaces like floors or tables",
                    "Move camera slowly across surfaces",
                    "Ensure adequate lighting"
                ]
            ))
        }
        
        return issues
    }
    
    // MARK: - Private Methods
    
    private func calculateQuality(
        trackingState: ARCamera.TrackingState,
        planeCount: Int,
        sessionDuration: TimeInterval
    ) -> ARTrackingQuality {
        switch trackingState {
        case .normal:
            return calculateNormalTrackingQuality(planeCount: planeCount, sessionDuration: sessionDuration)
            
        case .limited(let reason):
            return calculateLimitedTrackingQuality(reason: reason)
            
        case .notAvailable:
            return .unavailable
        }
    }
    
    private func calculateNormalTrackingQuality(planeCount: Int, sessionDuration: TimeInterval) -> ARTrackingQuality {
        // Base quality on plane count and session duration
        if planeCount >= 5 && sessionDuration > 10 {
            return .excellent
        } else if planeCount >= 3 && sessionDuration > 5 {
            return .good
        } else if planeCount >= 1 && sessionDuration > 2 {
            return .fair
        } else {
            return .fair
        }
    }
    
    private func calculateLimitedTrackingQuality(reason: ARCamera.TrackingState.Reason) -> ARTrackingQuality {
        switch reason {
        case .initializing:
            return .fair
        case .relocalizing:
            return .poor
        case .excessiveMotion:
            return .poor
        case .insufficientFeatures:
            return .poor
        @unknown default:
            return .poor
        }
    }
    
    private func addToHistory(_ snapshot: TrackingQualitySnapshot) {
        qualityHistory.append(snapshot)
        
        // Keep history size manageable
        if qualityHistory.count > maxHistorySize {
            qualityHistory.removeFirst()
        }
    }
    
    private func calculateStability(from history: [TrackingQualitySnapshot]) -> QualityStability {
        guard history.count >= 5 else { return .unknown }
        
        let qualityChanges = calculateQualityChanges(from: history)
        
        if qualityChanges <= 1 {
            return .stable
        } else if qualityChanges <= 3 {
            return .moderate
        } else {
            return .unstable
        }
    }
    
    private func calculateQualityChanges(from history: [TrackingQualitySnapshot]) -> Int {
        guard history.count >= 2 else { return 0 }
        
        var changes = 0
        for i in 1..<history.count {
            if history[i].quality != history[i-1].quality {
                changes += 1
            }
        }
        
        return changes
    }
    
    private func calculateTrend(from history: [TrackingQualitySnapshot]) -> QualityTrend {
        guard history.count >= 3 else { return .stable }
        
        let firstHalf = Array(history.prefix(history.count / 2))
        let secondHalf = Array(history.suffix(history.count / 2))
        
        let firstAverage = firstHalf.map { $0.quality.score }.reduce(0, +) / Double(firstHalf.count)
        let secondAverage = secondHalf.map { $0.quality.score }.reduce(0, +) / Double(secondHalf.count)
        
        let difference = secondAverage - firstAverage
        
        if difference > 0.1 {
            return .improving
        } else if difference < -0.1 {
            return .declining
        } else {
            return .stable
        }
    }
    
    private func qualityFromScore(_ score: Double) -> ARTrackingQuality {
        if score >= 0.9 {
            return .excellent
        } else if score >= 0.7 {
            return .good
        } else if score >= 0.5 {
            return .fair
        } else if score >= 0.3 {
            return .poor
        } else {
            return .unavailable
        }
    }
    
    private func getRecommendationsForLimitedTracking(reason: ARCamera.TrackingState.Reason) -> [String] {
        switch reason {
        case .excessiveMotion:
            return [
                "Move the device more slowly",
                "Hold the device steadier",
                "Avoid rapid movements"
            ]
            
        case .insufficientFeatures:
            return [
                "Point camera at textured surfaces",
                "Avoid blank walls or uniform surfaces",
                "Improve lighting conditions",
                "Move to an area with more visual details"
            ]
            
        case .initializing:
            return [
                "Keep the device steady while AR initializes",
                "Point camera at a textured surface",
                "Ensure good lighting"
            ]
            
        case .relocalizing:
            return [
                "Return to previously scanned area",
                "Move slowly while system relocates",
                "Point camera at recognizable features"
            ]
            
        @unknown default:
            return [
                "Check AR system status",
                "Restart AR session if problems persist"
            ]
        }
    }
    
    private func generateRecommendations(
        averageQuality: ARTrackingQuality,
        stability: QualityStability,
        trend: QualityTrend,
        recentHistory: [TrackingQualitySnapshot]
    ) -> [String] {
        var recommendations: [String] = []
        
        // Quality-based recommendations
        switch averageQuality {
        case .excellent:
            recommendations.append("Tracking quality is excellent, continue current approach")
        case .good:
            recommendations.append("Good tracking quality, minor improvements possible")
        case .fair:
            recommendations.append("Moderate tracking quality, follow improvement suggestions")
        case .poor, .unavailable:
            recommendations.append("Poor tracking quality, significant improvements needed")
        }
        
        // Stability-based recommendations
        switch stability {
        case .unstable:
            recommendations.append("Reduce device movement speed for more stable tracking")
        case .moderate:
            recommendations.append("Tracking stability could be improved")
        case .stable:
            recommendations.append("Tracking stability is good")
        case .unknown:
            recommendations.append("Continue scanning to assess tracking stability")
        }
        
        // Trend-based recommendations
        switch trend {
        case .declining:
            recommendations.append("Tracking quality is declining, consider changing approach")
        case .improving:
            recommendations.append("Tracking quality is improving, continue current method")
        case .stable:
            break // No specific recommendation needed
        }
        
        return recommendations
    }
}

// MARK: - Supporting Types

private struct TrackingQualitySnapshot {
    let quality: ARTrackingQuality
    let trackingState: ARCamera.TrackingState
    let planeCount: Int
    let timestamp: Date
}

struct TrackingQualityTrends {
    let averageQuality: ARTrackingQuality
    let qualityStability: QualityStability
    let improvementTrend: QualityTrend
    let recommendations: [String]
}

enum QualityStability {
    case stable
    case moderate
    case unstable
    case unknown
}

enum QualityTrend {
    case improving
    case declining
    case stable
}

struct TrackingIssue {
    let type: TrackingIssueType
    let severity: IssueSeverity
    let description: String
    let solutions: [String]
}

enum TrackingIssueType {
    case consistentlyPoorQuality
    case unstableTracking
    case noPlaneDetection
    case rapidQualityChanges
}

enum IssueSeverity {
    case low
    case medium
    case high
    case critical
}