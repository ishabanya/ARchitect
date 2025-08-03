import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - Before/After Comparison Visualization System

@MainActor
public class ComparisonVisualizationSystem: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var comparisonState: ComparisonState = .idle
    @Published public var currentComparison: LayoutComparison?
    @Published public var visualizationMode: VisualizationMode = .sideBySide
    @Published public var transitionProgress: Double = 0.0
    @Published public var isAnimating: Bool = false
    
    // MARK: - Private Properties
    private let renderingEngine: ComparisonRenderingEngine
    private let animationController: ComparisonAnimationController
    private let metricsCalculator: ComparisonMetricsCalculator
    private let imageGenerator: ComparisonImageGenerator
    
    private var comparisonTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        self.renderingEngine = ComparisonRenderingEngine()
        self.animationController = ComparisonAnimationController()
        self.metricsCalculator = ComparisonMetricsCalculator()
        self.imageGenerator = ComparisonImageGenerator()
        
        setupObservers()
        
        logDebug("Comparison visualization system initialized", category: .general)
    }
    
    // MARK: - Comparison States
    
    public enum ComparisonState {
        case idle
        case preparing
        case rendering
        case analyzing
        case ready
        case failed(Error)
        
        var description: String {
            switch self {
            case .idle: return "Ready to create comparison"
            case .preparing: return "Preparing comparison data..."
            case .rendering: return "Rendering visualization..."
            case .analyzing: return "Analyzing differences..."
            case .ready: return "Comparison ready"
            case .failed(let error): return "Failed: \(error.localizedDescription)"
            }
        }
    }
    
    public enum VisualizationMode: String, CaseIterable {
        case sideBySide = "Side by Side"
        case overlay = "Overlay"
        case animatedTransition = "Animated Transition"
        case splitView = "Split View"
        case heatmap = "Heatmap"
        case metrics = "Metrics Only"
        
        var icon: String {
            switch self {
            case .sideBySide: return "rectangle.split.2x1"
            case .overlay: return "square.stack"
            case .animatedTransition: return "arrow.right.arrow.left"
            case .splitView: return "rectangle.split.1x2"
            case .heatmap: return "thermometer"
            case .metrics: return "chart.bar"
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        $visualizationMode
            .sink { [weak self] mode in
                self?.updateVisualizationForMode(mode)
            }
            .store(in: &cancellables)
        
        $isAnimating
            .sink { [weak self] animating in
                if animating {
                    self?.startAnimationTimer()
                } else {
                    self?.stopAnimationTimer()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Main Comparison Method
    
    public func createComparison(
        originalLayout: FurnitureArrangement,
        optimizedLayout: FurnitureArrangement,
        roomAnalysis: RoomAnalysisResults,
        preferences: UserPreferences
    ) async throws -> LayoutComparison {
        
        comparisonState = .preparing
        
        do {
            // Step 1: Validate layouts for comparison
            let validationResult = validateLayoutsForComparison(
                original: originalLayout,
                optimized: optimizedLayout
            )
            
            guard validationResult.isValid else {
                throw ComparisonError.invalidLayouts(validationResult.issues)
            }
            
            // Step 2: Generate comparison data
            comparisonState = .analyzing
            let comparisonData = try await generateComparisonData(
                original: originalLayout,
                optimized: optimizedLayout,
                roomAnalysis: roomAnalysis,
                preferences: preferences
            )
            
            // Step 3: Render visualizations
            comparisonState = .rendering
            let visualizations = try await renderingEngine.generateVisualizations(
                comparisonData: comparisonData,
                roomGeometry: roomAnalysis.shape,
                roomDimensions: roomAnalysis.dimensions
            )
            
            // Step 4: Calculate metrics and insights
            let metrics = try await metricsCalculator.calculateImprovementMetrics(
                original: originalLayout,
                optimized: optimizedLayout,
                roomAnalysis: roomAnalysis
            )
            
            // Step 5: Generate insights and recommendations
            let insights = generateComparisonInsights(
                metrics: metrics,
                comparisonData: comparisonData,
                preferences: preferences
            )
            
            // Create final comparison object
            let comparison = LayoutComparison(
                id: UUID(),
                originalLayout: originalLayout,
                optimizedLayout: optimizedLayout,
                comparisonData: comparisonData,
                visualizations: visualizations,
                metrics: metrics,
                insights: insights,
                createdAt: Date()
            )
            
            self.currentComparison = comparison
            comparisonState = .ready
            
            logInfo("Layout comparison created successfully", category: .general, context: LogContext(customData: [
                "original_fitness": originalLayout.fitnessScore,
                "optimized_fitness": optimizedLayout.fitnessScore,
                "improvement": metrics.overallImprovement
            ]))
            
            return comparison
            
        } catch {
            comparisonState = .failed(error)
            logError("Comparison creation failed", category: .general, error: error)
            throw error
        }
    }
    
    // MARK: - Comparison Data Generation
    
    private func generateComparisonData(
        original: FurnitureArrangement,
        optimized: FurnitureArrangement,
        roomAnalysis: RoomAnalysisResults,
        preferences: UserPreferences
    ) async throws -> ComparisonData {
        
        // Calculate differences between layouts
        let itemDifferences = calculateItemDifferences(
            original: original.placedItems,
            optimized: optimized.placedItems
        )
        
        // Analyze spatial changes
        let spatialChanges = analyzeSpatialChanges(
            original: original,
            optimized: optimized,
            roomDimensions: roomAnalysis.dimensions
        )
        
        // Calculate traffic flow improvements
        let trafficFlowChanges = try await analyzeTrafficFlowChanges(
            original: original,
            optimized: optimized,
            roomShape: roomAnalysis.shape,
            roomDimensions: roomAnalysis.dimensions
        )
        
        // Analyze lighting improvements
        let lightingChanges = try await analyzeLightingChanges(
            original: original,
            optimized: optimized,
            roomAnalysis: roomAnalysis
        )
        
        // Calculate functional improvements
        let functionalChanges = analyzeFunctionalChanges(
            original: original,
            optimized: optimized,
            preferences: preferences
        )
        
        return ComparisonData(
            itemDifferences: itemDifferences,
            spatialChanges: spatialChanges,
            trafficFlowChanges: trafficFlowChanges,
            lightingChanges: lightingChanges,
            functionalChanges: functionalChanges,
            overallScore: calculateOverallImprovementScore(
                optimized.fitnessScore - original.fitnessScore
            )
        )
    }
    
    // MARK: - Visualization Updates
    
    private func updateVisualizationForMode(_ mode: VisualizationMode) {
        guard let comparison = currentComparison else { return }
        
        switch mode {
        case .animatedTransition:
            startAnimatedTransition()
        case .overlay:
            renderOverlayVisualization(comparison)
        case .sideBySide:
            renderSideBySideVisualization(comparison)
        case .splitView:
            renderSplitViewVisualization(comparison)
        case .heatmap:
            renderHeatmapVisualization(comparison)
        case .metrics:
            renderMetricsVisualization(comparison)
        }
    }
    
    // MARK: - Animation Control
    
    public func startAnimatedTransition() {
        guard let comparison = currentComparison else { return }
        
        isAnimating = true
        transitionProgress = 0.0
        
        animationController.startTransition(
            from: comparison.originalLayout,
            to: comparison.optimizedLayout,
            duration: 3.0,
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    self?.transitionProgress = progress
                }
            },
            completionCallback: { [weak self] in
                Task { @MainActor in
                    self?.isAnimating = false
                    self?.transitionProgress = 1.0
                }
            }
        )
    }
    
    public func pauseAnimation() {
        animationController.pauseTransition()
        isAnimating = false
    }
    
    public func resumeAnimation() {
        animationController.resumeTransition()
        isAnimating = true
    }
    
    public func resetAnimation() {
        animationController.resetTransition()
        transitionProgress = 0.0
        isAnimating = false
    }
    
    public func setTransitionProgress(_ progress: Double) {
        transitionProgress = max(0.0, min(1.0, progress))
        animationController.setTransitionProgress(progress)
    }
    
    // MARK: - Visualization Rendering Methods
    
    private func renderSideBySideVisualization(_ comparison: LayoutComparison) {
        // Implementation would render two views side by side
        logDebug("Rendering side-by-side visualization", category: .general)
    }
    
    private func renderOverlayVisualization(_ comparison: LayoutComparison) {
        // Implementation would render overlaid views with transparency
        logDebug("Rendering overlay visualization", category: .general)
    }
    
    private func renderSplitViewVisualization(_ comparison: LayoutComparison) {
        // Implementation would render with vertical/horizontal split
        logDebug("Rendering split view visualization", category: .general)
    }
    
    private func renderHeatmapVisualization(_ comparison: LayoutComparison) {
        // Implementation would render heatmap showing improvements
        logDebug("Rendering heatmap visualization", category: .general)
    }
    
    private func renderMetricsVisualization(_ comparison: LayoutComparison) {
        // Implementation would render metrics-only view
        logDebug("Rendering metrics visualization", category: .general)
    }
    
    // MARK: - Analysis Methods
    
    private func calculateItemDifferences(
        original: [PlacedFurnitureItem],
        optimized: [PlacedFurnitureItem]
    ) -> [ItemDifference] {
        
        var differences: [ItemDifference] = []
        
        // Create lookup dictionaries
        let originalItems = Dictionary(uniqueKeysWithValues: original.map { ($0.item.id, $0) })
        let optimizedItems = Dictionary(uniqueKeysWithValues: optimized.map { ($0.item.id, $0) })
        
        // Find moved items
        for (itemId, originalItem) in originalItems {
            if let optimizedItem = optimizedItems[itemId] {
                let positionChange = simd_distance(originalItem.position, optimizedItem.position)
                let rotationChange = abs(originalItem.rotation - optimizedItem.rotation)
                
                if positionChange > 0.1 || rotationChange > 0.1 {
                    differences.append(ItemDifference(
                        itemId: itemId,
                        type: .moved,
                        originalPosition: originalItem.position,
                        newPosition: optimizedItem.position,
                        originalRotation: originalItem.rotation,
                        newRotation: optimizedItem.rotation,
                        magnitude: max(positionChange, rotationChange * 2.0) // Weight rotation changes
                    ))
                }
            } else {
                // Item was removed
                differences.append(ItemDifference(
                    itemId: itemId,
                    type: .removed,
                    originalPosition: originalItem.position,
                    newPosition: nil,
                    originalRotation: originalItem.rotation,
                    newRotation: nil,
                    magnitude: 1.0
                ))
            }
        }
        
        // Find added items
        for (itemId, optimizedItem) in optimizedItems {
            if originalItems[itemId] == nil {
                differences.append(ItemDifference(
                    itemId: itemId,
                    type: .added,
                    originalPosition: nil,
                    newPosition: optimizedItem.position,
                    originalRotation: nil,
                    newRotation: optimizedItem.rotation,
                    magnitude: 1.0
                ))
            }
        }
        
        return differences.sorted { $0.magnitude > $1.magnitude }
    }
    
    private func analyzeSpatialChanges(
        original: FurnitureArrangement,
        optimized: FurnitureArrangement,
        roomDimensions: RoomDimensions
    ) -> SpatialChanges {
        
        let originalSpaceUtilization = calculateSpaceUtilization(original, roomDimensions: roomDimensions)
        let optimizedSpaceUtilization = calculateSpaceUtilization(optimized, roomDimensions: roomDimensions)
        
        let originalClearance = calculateAverageClearance(original, roomDimensions: roomDimensions)
        let optimizedClearance = calculateAverageClearance(optimized, roomDimensions: roomDimensions)
        
        return SpatialChanges(
            spaceUtilizationChange: optimizedSpaceUtilization - originalSpaceUtilization,
            clearanceImprovement: optimizedClearance - originalClearance,
            centerOfMassShift: calculateCenterOfMassShift(original: original, optimized: optimized),
            symmetryImprovement: calculateSymmetryImprovement(original: original, optimized: optimized)
        )
    }
    
    private func generateComparisonInsights(
        metrics: ImprovementMetrics,
        comparisonData: ComparisonData,
        preferences: UserPreferences
    ) -> [ComparisonInsight] {
        
        var insights: [ComparisonInsight] = []
        
        // Overall improvement insight
        if metrics.overallImprovement > 0.1 {
            insights.append(ComparisonInsight(
                type: .improvement,
                title: "Significant Layout Improvement",
                description: "The optimized layout shows a \(Int(metrics.overallImprovement * 100))% improvement in overall functionality and aesthetics.",
                impact: .high,
                confidence: 0.9
            ))
        }
        
        // Traffic flow insights
        if comparisonData.trafficFlowChanges.flowImprovement > 0.2 {
            insights.append(ComparisonInsight(
                type: .trafficFlow,
                title: "Better Traffic Flow",
                description: "Movement through the room is now \(Int(comparisonData.trafficFlowChanges.flowImprovement * 100))% more efficient with clearer pathways.",
                impact: .medium,
                confidence: 0.8
            ))
        }
        
        // Lighting insights
        if comparisonData.lightingChanges.naturalLightImprovement > 0.15 {
            insights.append(ComparisonInsight(
                type: .lighting,
                title: "Enhanced Natural Light",
                description: "The new arrangement makes better use of natural light, improving the overall ambiance.",
                impact: .medium,
                confidence: 0.7
            ))
        }
        
        // Space utilization insights
        if comparisonData.spatialChanges.spaceUtilizationChange > 0.1 {
            insights.append(ComparisonInsight(
                type: .spatial,
                title: "More Efficient Space Use",
                description: "The optimized layout uses available space more effectively while maintaining comfort.",
                impact: .medium,
                confidence: 0.8
            ))
        }
        
        // Functional improvements
        if comparisonData.functionalChanges.functionalityScore > 0.2 {
            let topFunction = preferences.functionalPriorities.first?.rawValue ?? "room function"
            insights.append(ComparisonInsight(
                type: .functional,
                title: "Better Functional Layout",
                description: "The arrangement now better supports \(topFunction) and other key activities.",
                impact: .high,
                confidence: 0.85
            ))
        }
        
        return insights.sorted { $0.impact.rawValue > $1.impact.rawValue }
    }
    
    // MARK: - Helper Methods
    
    private func validateLayoutsForComparison(
        original: FurnitureArrangement,
        optimized: FurnitureArrangement
    ) -> ValidationResult {
        
        var issues: [String] = []
        
        // Check if layouts are substantially different
        let similarity = calculateLayoutSimilarity(original, optimized)
        if similarity > 0.95 {
            issues.append("Layouts are too similar for meaningful comparison")
        }
        
        // Check if furniture sets are compatible
        let originalItemIds = Set(original.placedItems.map { $0.item.id })
        let optimizedItemIds = Set(optimized.placedItems.map { $0.item.id })
        
        let commonItems = originalItemIds.intersection(optimizedItemIds)
        if commonItems.count < originalItemIds.count / 2 {
            issues.append("Layouts contain significantly different furniture sets")
        }
        
        return ValidationResult(
            isValid: issues.isEmpty,
            issues: issues
        )
    }
    
    private func calculateOverallImprovementScore(_ fitnessDifference: Float) -> Float {
        // Normalize fitness difference to a 0-1 scale
        return max(0.0, min(1.0, fitnessDifference * 2.0))
    }
    
    private func calculateSpaceUtilization(
        _ arrangement: FurnitureArrangement,
        roomDimensions: RoomDimensions
    ) -> Float {
        let totalRoomArea = roomDimensions.area
        let usedArea = arrangement.placedItems.reduce(0) { $0 + $1.item.footprint }
        return usedArea / totalRoomArea
    }
    
    private func calculateAverageClearance(
        _ arrangement: FurnitureArrangement,
        roomDimensions: RoomDimensions
    ) -> Float {
        // Simplified clearance calculation
        let totalArea = roomDimensions.area
        let usedArea = arrangement.totalFootprint
        let clearArea = totalArea - usedArea
        return sqrt(clearArea / Float.pi) // Approximate average clearance radius
    }
    
    private func calculateCenterOfMassShift(
        original: FurnitureArrangement,
        optimized: FurnitureArrangement
    ) -> Float {
        let originalCenter = calculateCenterOfMass(original)
        let optimizedCenter = calculateCenterOfMass(optimized)
        return simd_distance(originalCenter, optimizedCenter)
    }
    
    private func calculateCenterOfMass(_ arrangement: FurnitureArrangement) -> SIMD3<Float> {
        let totalMass = arrangement.placedItems.reduce(0) { $0 + $1.item.footprint }
        let weightedSum = arrangement.placedItems.reduce(SIMD3<Float>.zero) { result, item in
            return result + (item.position * item.item.footprint)
        }
        return totalMass > 0 ? weightedSum / totalMass : SIMD3<Float>.zero
    }
    
    private func calculateSymmetryImprovement(
        original: FurnitureArrangement,
        optimized: FurnitureArrangement
    ) -> Float {
        let originalSymmetry = calculateSymmetryScore(original)
        let optimizedSymmetry = calculateSymmetryScore(optimized)
        return optimizedSymmetry - originalSymmetry
    }
    
    private func calculateSymmetryScore(_ arrangement: FurnitureArrangement) -> Float {
        // Simplified symmetry calculation
        let centerOfMass = calculateCenterOfMass(arrangement)
        let symmetryScore = arrangement.placedItems.reduce(0.0) { score, item in
            let distance = simd_distance(item.position, centerOfMass)
            return score + (1.0 / (1.0 + distance)) // Closer to center = higher symmetry contribution
        }
        return symmetryScore / Float(arrangement.placedItems.count)
    }
    
    private func calculateLayoutSimilarity(
        _ layout1: FurnitureArrangement,
        _ layout2: FurnitureArrangement
    ) -> Float {
        // Calculate similarity based on item positions
        let commonItems = Set(layout1.placedItems.map { $0.item.id })
            .intersection(Set(layout2.placedItems.map { $0.item.id }))
        
        guard !commonItems.isEmpty else { return 0.0 }
        
        let layout1Items = Dictionary(uniqueKeysWithValues: layout1.placedItems.map { ($0.item.id, $0) })
        let layout2Items = Dictionary(uniqueKeysWithValues: layout2.placedItems.map { ($0.item.id, $0) })
        
        let totalSimilarity = commonItems.reduce(0.0) { total, itemId in
            guard let item1 = layout1Items[itemId],
                  let item2 = layout2Items[itemId] else { return total }
            
            let positionDistance = simd_distance(item1.position, item2.position)
            let rotationDifference = abs(item1.rotation - item2.rotation)
            
            let similarity = 1.0 / (1.0 + positionDistance + rotationDifference)
            return total + similarity
        }
        
        return totalSimilarity / Float(commonItems.count)
    }
    
    // MARK: - Timer Management
    
    private func startAnimationTimer() {
        stopAnimationTimer()
        comparisonTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            // Update animation at 60fps
            self?.updateAnimation()
        }
    }
    
    private func stopAnimationTimer() {
        comparisonTimer?.invalidate()
        comparisonTimer = nil
    }
    
    private func updateAnimation() {
        // Animation update logic would be implemented here
        // This would update the visualization based on current animation state
    }
    
    // MARK: - Public Interface
    
    public func exportComparison(_ comparison: LayoutComparison, format: ExportFormat) async throws -> Data {
        return try await imageGenerator.generateExport(
            comparison: comparison,
            format: format,
            visualizationMode: visualizationMode
        )
    }
    
    public func shareComparison(_ comparison: LayoutComparison) -> ShareData {
        return ShareData(
            title: "Layout Comparison - \(comparison.insights.first?.title ?? "Room Improvement")",
            description: "See the improvements made to this room layout",
            imageData: comparison.visualizations.thumbnail,
            url: nil // Could generate a shareable link
        )
    }
}

// MARK: - Supporting Data Structures

public struct LayoutComparison: Identifiable {
    public let id: UUID
    public let originalLayout: FurnitureArrangement
    public let optimizedLayout: FurnitureArrangement
    public let comparisonData: ComparisonData
    public let visualizations: ComparisonVisualizations
    public let metrics: ImprovementMetrics
    public let insights: [ComparisonInsight]
    public let createdAt: Date
}

public struct ComparisonData {
    public let itemDifferences: [ItemDifference]
    public let spatialChanges: SpatialChanges
    public let trafficFlowChanges: TrafficFlowChanges
    public let lightingChanges: LightingChanges
    public let functionalChanges: FunctionalChanges
    public let overallScore: Float
}

public struct ItemDifference {
    public let itemId: UUID
    public let type: DifferenceType
    public let originalPosition: SIMD3<Float>?
    public let newPosition: SIMD3<Float>?
    public let originalRotation: Float?
    public let newRotation: Float?
    public let magnitude: Float
    
    public enum DifferenceType {
        case moved
        case added
        case removed
        case rotated
    }
}

public struct SpatialChanges {
    public let spaceUtilizationChange: Float
    public let clearanceImprovement: Float
    public let centerOfMassShift: Float
    public let symmetryImprovement: Float
}

public struct TrafficFlowChanges {
    public let flowImprovement: Float
    public let pathwayChanges: [PathwayChange]
    public let congestionReduction: Float
    public let accessibilityImprovement: Float
}

public struct LightingChanges {
    public let naturalLightImprovement: Float
    public let lightDistributionChange: Float
    public let glareReduction: Float
    public let shadowImprovement: Float
}

public struct FunctionalChanges {
    public let functionalityScore: Float
    public let activityZoneImprovements: [ActivityZoneImprovement]
    public let ergonomicImprovements: [ErgonomicImprovement]
    public let storageAccessImprovement: Float
}

public struct ComparisonInsight {
    public let type: InsightType
    public let title: String
    public let description: String
    public let impact: ImpactLevel
    public let confidence: Float
    
    public enum InsightType {
        case improvement
        case trafficFlow
        case lighting
        case spatial
        case functional
        case aesthetic
    }
    
    public enum ImpactLevel: Int, CaseIterable {
        case low = 1
        case medium = 2
        case high = 3
        
        var description: String {
            switch self {
            case .low: return "Minor improvement"
            case .medium: return "Moderate improvement"
            case .high: return "Significant improvement"
            }
        }
    }
}

public struct ComparisonVisualizations {
    public let thumbnail: Data
    public let sideBySideImage: Data
    public let overlayImage: Data
    public let heatmapImage: Data
    public let animationFrames: [Data]
}

public struct ImprovementMetrics {
    public let overallImprovement: Float
    public let functionalImprovement: Float
    public let spatialImprovement: Float
    public let aestheticImprovement: Float
    public let efficiencyImprovement: Float
}

public struct ValidationResult {
    public let isValid: Bool
    public let issues: [String]
}

public enum ComparisonError: Error {
    case invalidLayouts([String])
    case renderingFailed(String)
    case analysisError(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidLayouts(let issues):
            return "Invalid layouts for comparison: \(issues.joined(separator: ", "))"
        case .renderingFailed(let reason):
            return "Visualization rendering failed: \(reason)"
        case .analysisError(let reason):
            return "Comparison analysis failed: \(reason)"
        }
    }
}

public enum ExportFormat {
    case png
    case pdf
    case video
    case interactiveHTML
}

public struct ShareData {
    public let title: String
    public let description: String
    public let imageData: Data
    public let url: URL?
}

// Additional supporting classes would be implemented:
// - ComparisonRenderingEngine
// - ComparisonAnimationController
// - ComparisonMetricsCalculator
// - ComparisonImageGenerator