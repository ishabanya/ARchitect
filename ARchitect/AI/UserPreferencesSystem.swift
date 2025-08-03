import Foundation
import SwiftUI
import Combine

// MARK: - User Preferences and Constraints System

@MainActor
public class UserPreferencesSystem: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var currentPreferences: UserPreferences
    @Published public var activeConstraints: UserConstraints
    @Published public var preferenceLearning: PreferenceLearningData
    @Published public var isLearningEnabled: Bool = true
    
    // MARK: - Private Properties
    private let preferenceAnalyzer: PreferenceAnalyzer
    private let constraintValidator: ConstraintValidator
    private let learningEngine: MachineLearningEngine
    private let persistenceManager: PreferencesPersistenceManager
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        self.currentPreferences = UserPreferences.default
        self.activeConstraints = UserConstraints.default
        self.preferenceLearning = PreferenceLearningData()
        self.preferenceAnalyzer = PreferenceAnalyzer()
        self.constraintValidator = ConstraintValidator()
        self.learningEngine = MachineLearningEngine()
        self.persistenceManager = PreferencesPersistenceManager()
        
        setupObservers()
        loadPersistedPreferences()
        
        logDebug("User preferences system initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Auto-save preferences when they change
        $currentPreferences
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] preferences in
                self?.savePreferences(preferences)
            }
            .store(in: &cancellables)
        
        // Validate constraints when they change
        $activeConstraints
            .sink { [weak self] constraints in
                self?.validateConstraints(constraints)
            }
            .store(in: &cancellables)
    }
    
    private func loadPersistedPreferences() {
        if let savedPreferences = persistenceManager.loadPreferences() {
            currentPreferences = savedPreferences
        }
        
        if let savedConstraints = persistenceManager.loadConstraints() {
            activeConstraints = savedConstraints
        }
        
        if let savedLearning = persistenceManager.loadLearningData() {
            preferenceLearning = savedLearning
        }
    }
    
    // MARK: - Preference Management
    
    public func updatePreferences(_ newPreferences: UserPreferences) {
        let previousPreferences = currentPreferences
        currentPreferences = newPreferences
        
        // Learn from preference changes
        if isLearningEnabled {
            learningEngine.analyzePreferenceChange(
                from: previousPreferences,
                to: newPreferences,
                context: getCurrentContext()
            )
        }
        
        logInfo("User preferences updated", category: .general, context: LogContext(customData: [
            "style_preference": newPreferences.designStyle.rawValue,
            "functional_priorities_count": newPreferences.functionalPriorities.count
        ]))
    }
    
    public func updateConstraints(_ newConstraints: UserConstraints) {
        let validationResult = constraintValidator.validate(constraints: newConstraints)
        
        if validationResult.isValid {
            activeConstraints = newConstraints
            logInfo("User constraints updated", category: .general)
        } else {
            logWarning("Invalid constraints provided", category: .general, context: LogContext(customData: [
                "validation_errors": validationResult.errors.joined(separator: ", ")
            ]))
            
            // Apply only valid parts of constraints
            activeConstraints = validationResult.validatedConstraints
        }
    }
    
    // MARK: - Preference Analysis
    
    public func analyzeUserBehavior(
        layoutInteractions: [LayoutInteraction],
        selectionHistory: [SelectionEvent],
        timeSpentViewing: [ViewingEvent]
    ) -> PreferenceInsights {
        
        let behaviorAnalysis = preferenceAnalyzer.analyzeBehavior(
            interactions: layoutInteractions,
            selections: selectionHistory,
            viewingPatterns: timeSpentViewing
        )
        
        // Update learning data
        preferenceLearning.addBehaviorData(behaviorAnalysis)
        
        // Generate insights
        let insights = PreferenceInsights(
            inferredStylePreferences: behaviorAnalysis.stylePatterns,
            functionalPreferences: behaviorAnalysis.functionalPatterns,
            spatialPreferences: behaviorAnalysis.spatialPatterns,
            confidence: behaviorAnalysis.confidence,
            recommendations: generateRecommendations(from: behaviorAnalysis)
        )
        
        return insights
    }
    
    // MARK: - Constraint Management
    
    public func addConstraint(_ constraint: LayoutConstraint) throws {
        var updatedConstraints = activeConstraints
        
        switch constraint {
        case .budgetLimit(let limit):
            updatedConstraints.budgetConstraints.maxBudget = limit
        case .accessibilityRequirement(let requirement):
            updatedConstraints.accessibilityRequirements.append(requirement)
        case .spatialConstraint(let spatialConstraint):
            updatedConstraints.spatialConstraints.append(spatialConstraint)
        case .styleConstraint(let styleConstraint):
            updatedConstraints.styleConstraints.append(styleConstraint)
        case .functionalConstraint(let functionalConstraint):
            updatedConstraints.functionalConstraints.append(functionalConstraint)
        }
        
        let validationResult = constraintValidator.validate(constraints: updatedConstraints)
        if validationResult.isValid {
            activeConstraints = updatedConstraints
        } else {
            throw ConstraintError.invalidConstraint(validationResult.errors.first ?? "Unknown validation error")
        }
    }
    
    public func removeConstraint(id: UUID) {
        activeConstraints.removeConstraint(withId: id)
    }
    
    public func getApplicableConstraints(for roomPurpose: RoomPurpose) -> [LayoutConstraint] {
        return activeConstraints.getConstraints(applicableTo: roomPurpose)
    }
    
    // MARK: - Learning and Adaptation
    
    public func recordLayoutRating(
        layout: FurnitureArrangement,
        rating: Float,
        feedback: UserFeedback?
    ) {
        let ratingEvent = LayoutRatingEvent(
            layoutId: layout.id,
            rating: rating,
            feedback: feedback,
            timestamp: Date(),
            context: getCurrentContext()
        )
        
        preferenceLearning.addRatingEvent(ratingEvent)
        
        if isLearningEnabled {
            learningEngine.processRatingFeedback(
                layout: layout,
                rating: rating,
                feedback: feedback,
                userPreferences: currentPreferences
            )
            
            // Update preferences based on learning
            if let updatedPreferences = learningEngine.getUpdatedPreferences() {
                currentPreferences = updatedPreferences
            }
        }
    }
    
    public func recordInteractionPattern(
        interaction: LayoutInteraction,
        duration: TimeInterval,
        outcome: InteractionOutcome
    ) {
        let interactionEvent = InteractionEvent(
            interaction: interaction,
            duration: duration,
            outcome: outcome,
            timestamp: Date(),
            context: getCurrentContext()
        )
        
        preferenceLearning.addInteractionEvent(interactionEvent)
        
        if isLearningEnabled {
            learningEngine.processInteractionPattern(interactionEvent)
        }
    }
    
    // MARK: - Preference Suggestions
    
    public func suggestPreferenceUpdates() -> [PreferenceSuggestion] {
        let currentBehavior = preferenceLearning.getRecentBehaviorSummary()
        let inconsistencies = preferenceAnalyzer.findInconsistencies(
            declaredPreferences: currentPreferences,
            behaviorPatterns: currentBehavior
        )
        
        return inconsistencies.map { inconsistency in
            PreferenceSuggestion(
                type: inconsistency.type,
                currentValue: inconsistency.currentValue,
                suggestedValue: inconsistency.suggestedValue,
                confidence: inconsistency.confidence,
                reasoning: inconsistency.reasoning,
                impact: inconsistency.estimatedImpact
            )
        }
    }
    
    // MARK: - Constraint Generation
    
    public func generateSmartConstraints(
        for roomPurpose: RoomPurpose,
        roomCharacteristics: RoomCharacteristics
    ) -> [LayoutConstraint] {
        
        var suggestedConstraints: [LayoutConstraint] = []
        
        // Accessibility constraints based on room size and layout
        if roomCharacteristics.size == .small {
            suggestedConstraints.append(.spatialConstraint(
                SpatialConstraint(
                    type: .minimumClearance,
                    value: 0.8, // 80cm minimum clearance
                    area: .allAreas,
                    importance: .high
                )
            ))
        }
        
        // Room-specific functional constraints
        switch roomPurpose {
        case .bedroom:
            suggestedConstraints.append(.functionalConstraint(
                FunctionalConstraint(
                    type: .bedAccess,
                    requirement: "Minimum 60cm clearance on at least one side of bed",
                    importance: .high
                )
            ))
        case .kitchen:
            suggestedConstraints.append(.functionalConstraint(
                FunctionalConstraint(
                    type: .workTriangle,
                    requirement: "Work triangle sides between 1.2m and 2.7m",
                    importance: .critical
                )
            ))
        case .livingRoom:
            suggestedConstraints.append(.functionalConstraint(
                FunctionalConstraint(
                    type: .conversationDistance,
                    requirement: "Seating arranged within 2.4m for comfortable conversation",
                    importance: .medium
                )
            ))
        default:
            break
        }
        
        // Budget constraints based on user profile
        if let budgetPreference = currentPreferences.budgetConstraints {
            suggestedConstraints.append(.budgetLimit(budgetPreference.maxBudget))
        }
        
        // Accessibility constraints based on user requirements
        for requirement in currentPreferences.accessibilityRequirements {
            suggestedConstraints.append(.accessibilityRequirement(requirement))
        }
        
        return suggestedConstraints
    }
    
    // MARK: - Preference Export/Import
    
    public func exportPreferences() -> PreferencesExport {
        return PreferencesExport(
            preferences: currentPreferences,
            constraints: activeConstraints,
            learningData: preferenceLearning.getExportableData(),
            exportDate: Date(),
            version: "1.0"
        )
    }
    
    public func importPreferences(from export: PreferencesExport) throws {
        // Validate import data
        guard export.version == "1.0" else {
            throw ImportError.unsupportedVersion(export.version)
        }
        
        // Apply imported preferences
        currentPreferences = export.preferences
        activeConstraints = export.constraints
        
        // Merge learning data
        try preferenceLearning.importData(export.learningData)
        
        logInfo("Preferences imported successfully", category: .general)
    }
    
    // MARK: - Helper Methods
    
    private func savePreferences(_ preferences: UserPreferences) {
        persistenceManager.savePreferences(preferences)
    }
    
    private func validateConstraints(_ constraints: UserConstraints) {
        let validationResult = constraintValidator.validate(constraints: constraints)
        if !validationResult.isValid {
            logWarning("Invalid constraints detected", category: .general, context: LogContext(customData: [
                "errors": validationResult.errors.joined(separator: ", ")
            ]))
        }
    }
    
    private func getCurrentContext() -> AnalysisContext {
        return AnalysisContext(
            timestamp: Date(),
            sessionId: UUID(), // Would track current session
            roomContext: nil, // Would include current room info
            deviceInfo: DeviceInfo.current
        )
    }
    
    private func generateRecommendations(from analysis: BehaviorAnalysis) -> [PreferenceRecommendation] {
        var recommendations: [PreferenceRecommendation] = []
        
        // Style recommendations
        if let strongStylePattern = analysis.stylePatterns.first(where: { $0.confidence > 0.8 }) {
            if strongStylePattern.style != currentPreferences.designStyle {
                recommendations.append(PreferenceRecommendation(
                    type: .styleUpdate,
                    title: "Consider updating your style preference",
                    description: "Your behavior suggests a strong preference for \(strongStylePattern.style.rawValue) style",
                    impact: .medium,
                    confidence: strongStylePattern.confidence
                ))
            }
        }
        
        // Functional recommendations
        let topFunctionalPriorities = analysis.functionalPatterns.prefix(3)
        if Set(topFunctionalPriorities.map { $0.function }) != Set(currentPreferences.functionalPriorities) {
            recommendations.append(PreferenceRecommendation(
                type: .functionalUpdate,
                title: "Update your functional priorities",
                description: "Your usage patterns suggest different priorities than your current settings",
                impact: .high,
                confidence: 0.7
            ))
        }
        
        return recommendations
    }
}

// MARK: - Supporting Data Structures

public struct UserPreferences: Codable, Equatable {
    public var designStyle: DesignStyle
    public var colorPreferences: ColorPreferences
    public var functionalPriorities: [RoomFunction]
    public var accessibilityRequirements: [AccessibilityRequirement]
    public var budgetConstraints: BudgetConstraints?
    public var personalityTraits: [PersonalityTrait]
    public var lifestyleFactors: [LifestyleFactor]
    public var roomUsagePatterns: [RoomUsagePattern]
    
    public static let `default` = UserPreferences(
        designStyle: .contemporary,
        colorPreferences: ColorPreferences.neutral,
        functionalPriorities: [.relaxation, .entertainment],
        accessibilityRequirements: [],
        budgetConstraints: nil,
        personalityTraits: [],
        lifestyleFactors: [],
        roomUsagePatterns: []
    )
}

public struct UserConstraints: Codable {
    public var budgetConstraints: BudgetConstraints
    public var accessibilityRequirements: [AccessibilityRequirement]
    public var spatialConstraints: [SpatialConstraint]
    public var styleConstraints: [StyleConstraint]
    public var functionalConstraints: [FunctionalConstraint]
    public var temporalConstraints: [TemporalConstraint]
    
    public static let `default` = UserConstraints(
        budgetConstraints: BudgetConstraints.unlimited,
        accessibilityRequirements: [],
        spatialConstraints: [],
        styleConstraints: [],
        functionalConstraints: [],
        temporalConstraints: []
    )
    
    public mutating func removeConstraint(withId id: UUID) {
        spatialConstraints.removeAll { $0.id == id }
        styleConstraints.removeAll { $0.id == id }
        functionalConstraints.removeAll { $0.id == id }
        temporalConstraints.removeAll { $0.id == id }
    }
    
    public func getConstraints(applicableTo roomPurpose: RoomPurpose) -> [LayoutConstraint] {
        var applicable: [LayoutConstraint] = []
        
        for constraint in spatialConstraints {
            if constraint.applicableRooms.contains(roomPurpose) {
                applicable.append(.spatialConstraint(constraint))
            }
        }
        
        for constraint in functionalConstraints {
            if constraint.applicableRooms.contains(roomPurpose) {
                applicable.append(.functionalConstraint(constraint))
            }
        }
        
        return applicable
    }
}

public struct ColorPreferences: Codable, Equatable {
    public let primaryColors: [Color]
    public let accentColors: [Color]
    public let avoidColors: [Color]
    public let colorTemperature: ColorTemperature
    public let saturationPreference: SaturationLevel
    
    public static let neutral = ColorPreferences(
        primaryColors: [.white, .gray, .black],
        accentColors: [.blue, .green],
        avoidColors: [],
        colorTemperature: .neutral,
        saturationPreference: .medium
    )
}

public enum ColorTemperature: String, Codable, CaseIterable {
    case warm = "Warm"
    case neutral = "Neutral"
    case cool = "Cool"
}

public enum SaturationLevel: String, Codable, CaseIterable {
    case low = "Muted"
    case medium = "Balanced"
    case high = "Vibrant"
}

public struct PersonalityTrait: Codable, Equatable {
    public let trait: TraitType
    public let strength: Float // 0.0 to 1.0
    
    public enum TraitType: String, Codable, CaseIterable {
        case introversion = "Introversion"
        case extraversion = "Extraversion"
        case openness = "Openness"
        case conscientiousness = "Conscientiousness"
        case agreeableness = "Agreeableness"
        case neuroticism = "Neuroticism"
    }
}

public struct LifestyleFactor: Codable, Equatable {
    public let factor: FactorType
    public let level: FactorLevel
    
    public enum FactorType: String, Codable, CaseIterable {
        case socialActivity = "Social Activity"
        case workFromHome = "Work From Home"
        case entertaining = "Entertaining"
        case petOwnership = "Pet Ownership"
        case childrenPresent = "Children Present"
        case exerciseAtHome = "Exercise At Home"
    }
    
    public enum FactorLevel: String, Codable, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }
}

public struct RoomUsagePattern: Codable, Equatable {
    public let roomType: RoomPurpose
    public let primaryActivities: [Activity]
    public let peakUsageTimes: [TimeRange]
    public let averageOccupancy: Int
    
    public struct Activity: Codable, Equatable {
        public let name: String
        public let frequency: ActivityFrequency
        public let duration: TimeInterval
        public let participants: Int
    }
    
    public enum ActivityFrequency: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case occasionally = "Occasionally"
    }
}

public struct TimeRange: Codable, Equatable {
    public let start: Date
    public let end: Date
}

public enum LayoutConstraint: Codable {
    case budgetLimit(Decimal)
    case accessibilityRequirement(AccessibilityRequirement)
    case spatialConstraint(SpatialConstraint)
    case styleConstraint(StyleConstraint)
    case functionalConstraint(FunctionalConstraint)
}

public struct SpatialConstraint: Codable, Identifiable {
    public let id: UUID
    public let type: SpatialConstraintType
    public let value: Float
    public let area: ConstraintArea
    public let importance: ConstraintImportance
    public let applicableRooms: [RoomPurpose]
    
    public init(type: SpatialConstraintType, value: Float, area: ConstraintArea, importance: ConstraintImportance) {
        self.id = UUID()
        self.type = type
        self.value = value
        self.area = area
        self.importance = importance
        self.applicableRooms = RoomPurpose.allCases
    }
}

public enum SpatialConstraintType: String, Codable, CaseIterable {
    case minimumClearance = "Minimum Clearance"
    case maximumDistance = "Maximum Distance"
    case preferredDistance = "Preferred Distance"
    case noPlacementZone = "No Placement Zone"
}

public struct StyleConstraint: Codable, Identifiable {
    public let id: UUID
    public let type: StyleConstraintType
    public let specification: String
    public let importance: ConstraintImportance
    
    public init(type: StyleConstraintType, specification: String, importance: ConstraintImportance) {
        self.id = UUID()
        self.type = type
        self.specification = specification
        self.importance = importance
    }
}

public enum StyleConstraintType: String, Codable, CaseIterable {
    case colorScheme = "Color Scheme"
    case materialPreference = "Material Preference"
    case styleCoherence = "Style Coherence"
    case symmetryRequirement = "Symmetry Requirement"
}

public struct FunctionalConstraint: Codable, Identifiable {
    public let id: UUID
    public let type: FunctionalConstraintType
    public let requirement: String
    public let importance: ConstraintImportance
    public let applicableRooms: [RoomPurpose]
    
    public init(type: FunctionalConstraintType, requirement: String, importance: ConstraintImportance) {
        self.id = UUID()
        self.type = type
        self.requirement = requirement
        self.importance = importance
        self.applicableRooms = RoomPurpose.allCases
    }
}

public enum FunctionalConstraintType: String, Codable, CaseIterable {
    case bedAccess = "Bed Access"
    case workTriangle = "Work Triangle"
    case conversationDistance = "Conversation Distance"
    case trafficFlow = "Traffic Flow"
    case storageAccess = "Storage Access"
}

public struct TemporalConstraint: Codable, Identifiable {
    public let id: UUID
    public let type: TemporalConstraintType
    public let timeFrame: TimeRange
    public let specification: String
    
    public init(type: TemporalConstraintType, timeFrame: TimeRange, specification: String) {
        self.id = UUID()
        self.type = type
        self.timeFrame = timeFrame
        self.specification = specification
    }
}

public enum TemporalConstraintType: String, Codable, CaseIterable {
    case implementationDeadline = "Implementation Deadline"
    case budgetPeriod = "Budget Period"
    case seasonalConsideration = "Seasonal Consideration"
}

public enum ConstraintArea: String, Codable, CaseIterable {
    case allAreas = "All Areas"
    case entryways = "Entryways"
    case workAreas = "Work Areas"
    case restAreas = "Rest Areas"
    case storageAreas = "Storage Areas"
}

public enum ConstraintImportance: String, Codable, CaseIterable, Comparable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
    
    public var rawValue: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }
    
    public static func < (lhs: ConstraintImportance, rhs: ConstraintImportance) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public struct BudgetConstraints: Codable {
    public var maxBudget: Decimal
    public let priorityCategories: [FurnitureCategory]
    public let flexibilityPercentage: Float // How much over budget is acceptable
    
    public static let unlimited = BudgetConstraints(
        maxBudget: Decimal.greatestFiniteMagnitude,
        priorityCategories: [],
        flexibilityPercentage: 0.1
    )
}

// Additional supporting structures for learning and analysis...

public struct PreferenceLearningData: Codable {
    private var ratingEvents: [LayoutRatingEvent] = []
    private var interactionEvents: [InteractionEvent] = []
    private var behaviorSummaries: [BehaviorSummary] = []
    
    public mutating func addRatingEvent(_ event: LayoutRatingEvent) {
        ratingEvents.append(event)
        trimOldEvents()
    }
    
    public mutating func addInteractionEvent(_ event: InteractionEvent) {
        interactionEvents.append(event)
        trimOldEvents()
    }
    
    public mutating func addBehaviorData(_ analysis: BehaviorAnalysis) {
        let summary = BehaviorSummary(
            timestamp: Date(),
            analysis: analysis
        )
        behaviorSummaries.append(summary)
    }
    
    public func getRecentBehaviorSummary() -> BehaviorAnalysis? {
        return behaviorSummaries.last?.analysis
    }
    
    public func getExportableData() -> PreferenceLearningExport {
        return PreferenceLearningExport(
            recentRatings: Array(ratingEvents.suffix(100)),
            recentInteractions: Array(interactionEvents.suffix(100)),
            behaviorSummary: behaviorSummaries.last
        )
    }
    
    public mutating func importData(_ data: PreferenceLearningExport) throws {
        // Merge imported data with existing data
        ratingEvents.append(contentsOf: data.recentRatings)
        interactionEvents.append(contentsOf: data.recentInteractions)
        if let summary = data.behaviorSummary {
            behaviorSummaries.append(summary)
        }
        trimOldEvents()
    }
    
    private mutating func trimOldEvents() {
        let maxEvents = 1000
        if ratingEvents.count > maxEvents {
            ratingEvents = Array(ratingEvents.suffix(maxEvents))
        }
        if interactionEvents.count > maxEvents {
            interactionEvents = Array(interactionEvents.suffix(maxEvents))
        }
        if behaviorSummaries.count > 50 {
            behaviorSummaries = Array(behaviorSummaries.suffix(50))
        }
    }
}

// Additional supporting types and classes would be implemented here...