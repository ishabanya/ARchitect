import SwiftUI
import Combine

// MARK: - Analytics Integration Extensions
extension View {
    /// Track screen view when view appears
    func trackScreenView(_ screenName: String) -> some View {
        self.onAppear {
            AnalyticsManager.shared.trackScreenView(screenName)
        }
    }
    
    /// Track user interaction
    func trackInteraction(_ action: String, parameters: [String: Any] = [:]) -> some View {
        self.onTapGesture {
            AnalyticsManager.shared.trackUserEngagement(.userInteraction, parameters: [
                "action": action
            ].merging(parameters) { _, new in new })
        }
    }
    
    /// Track feature usage
    func trackFeatureUsage(_ feature: FeatureUsageMetric, parameters: [String: Any] = [:]) -> some View {
        self.onAppear {
            AnalyticsManager.shared.trackFeatureUsage(feature, parameters: parameters)
        }
    }
}

// MARK: - Analytics Wrapper for SwiftUI
struct AnalyticsView<Content: View>: View {
    let screenName: String
    let content: Content
    
    init(screenName: String, @ViewBuilder content: () -> Content) {
        self.screenName = screenName
        self.content = content()
    }
    
    var body: some View {
        content
            .trackScreenView(screenName)
    }
}

// MARK: - Performance Monitoring View Modifier
struct PerformanceMonitoringModifier: ViewModifier {
    let metricName: String
    @State private var startTime = Date()
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                startTime = Date()
            }
            .onDisappear {
                let loadTime = Date().timeIntervalSince(startTime)
                
                // Only track if view was visible for meaningful time
                if loadTime > 0.1 {
                    let metric: PerformanceMetric
                    switch metricName.lowercased() {
                    case "ar": metric = .arInitializationTime
                    case "model": metric = .modelLoadTime
                    case "scan": metric = .scanProcessingTime
                    default: return
                    }
                    
                    AnalyticsManager.shared.trackPerformanceMetric(metric, value: loadTime, parameters: [
                        "view_name": metricName
                    ])
                }
            }
    }
}

extension View {
    func monitorPerformance(_ metricName: String) -> some View {
        self.modifier(PerformanceMonitoringModifier(metricName: metricName))
    }
}

// MARK: - Analytics Buttons
struct AnalyticsButton<Label: View>: View {
    let action: () -> Void
    let label: Label
    let eventName: String
    let parameters: [String: Any]
    
    init(
        eventName: String,
        parameters: [String: Any] = [:],
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.eventName = eventName
        self.parameters = parameters
        self.action = action
        self.label = label()
    }
    
    var body: some View {
        Button(action: {
            // Track button tap
            AnalyticsManager.shared.trackCustomEvent(
                name: "button_tap",
                parameters: [
                    "button_name": eventName
                ].merging(parameters) { _, new in new }
            )
            
            action()
        }) {
            label
        }
    }
}

// MARK: - A/B Testing View Modifier
struct ABTestViewModifier: ViewModifier {
    let testName: String
    let variants: [String]
    let defaultVariant: String
    @State private var selectedVariant: String
    
    init(testName: String, variants: [String], defaultVariant: String) {
        self.testName = testName
        self.variants = variants
        self.defaultVariant = defaultVariant
        self._selectedVariant = State(initialValue: AnalyticsManager.shared.getABTestVariant(
            testName: testName,
            variants: variants,
            defaultVariant: defaultVariant
        ))
    }
    
    func body(content: Content) -> some View {
        Group {
            if selectedVariant == "A" || selectedVariant == defaultVariant {
                content
            } else {
                content
                    .opacity(0.8) // Example variant modification
            }
        }
        .onAppear {
            selectedVariant = AnalyticsManager.shared.getABTestVariant(
                testName: testName,
                variants: variants,
                defaultVariant: defaultVariant
            )
        }
    }
}

extension View {
    func abTest(testName: String, variants: [String] = ["A", "B"], defaultVariant: String = "A") -> some View {
        self.modifier(ABTestViewModifier(
            testName: testName,
            variants: variants,
            defaultVariant: defaultVariant
        ))
    }
}

// MARK: - Furniture Placement Analytics
struct FurniturePlacementAnalytics {
    static func trackPlacement(
        furnitureType: String,
        placementMethod: String = "tap",
        position: SIMD3<Float>? = nil,
        roomType: String? = nil
    ) {
        var parameters: [String: Any] = [
            "furniture_type": furnitureType,
            "placement_method": placementMethod
        ]
        
        if let position = position {
            parameters["position_x"] = position.x
            parameters["position_y"] = position.y
            parameters["position_z"] = position.z
        }
        
        if let roomType = roomType {
            parameters["room_type"] = roomType
        }
        
        AnalyticsManager.shared.trackFeatureUsage(.furniturePlacement, parameters: parameters)
    }
    
    static func trackRemoval(
        furnitureType: String,
        removalMethod: String = "tap",
        timeOnScreen: TimeInterval? = nil
    ) {
        var parameters: [String: Any] = [
            "furniture_type": furnitureType,
            "removal_method": removalMethod
        ]
        
        if let timeOnScreen = timeOnScreen {
            parameters["time_on_screen"] = timeOnScreen
        }
        
        AnalyticsManager.shared.trackFeatureUsage(.furnitureRemoval, parameters: parameters)
    }
    
    static func trackInteraction(
        furnitureType: String,
        interactionType: String,
        duration: TimeInterval? = nil
    ) {
        var parameters: [String: Any] = [
            "furniture_type": furnitureType,
            "interaction_type": interactionType
        ]
        
        if let duration = duration {
            parameters["interaction_duration"] = duration
        }
        
        AnalyticsManager.shared.trackUserEngagement(.userInteraction, parameters: parameters)
    }
}

// MARK: - Measurement Analytics
struct MeasurementAnalytics {
    static func trackMeasurement(
        measurementType: String,
        value: Double,
        unit: String,
        accuracy: Float? = nil
    ) {
        var parameters: [String: Any] = [
            "measurement_type": measurementType,
            "value": value,
            "unit": unit
        ]
        
        if let accuracy = accuracy {
            parameters["accuracy"] = accuracy
        }
        
        AnalyticsManager.shared.trackFeatureUsage(.measurementTaken, parameters: parameters)
    }
    
    static func trackMeasurementTool(
        toolType: String,
        usageDuration: TimeInterval
    ) {
        AnalyticsManager.shared.trackUserEngagement(.userInteraction, parameters: [
            "tool_type": toolType,
            "usage_duration": usageDuration,
            "action": "measurement_tool_used"
        ])
    }
}

// MARK: - Collaboration Analytics
struct CollaborationAnalytics {
    static func trackSessionStart(
        participantCount: Int,
        sessionType: String = "realtime"
    ) {
        AnalyticsManager.shared.trackFeatureUsage(.collaborationStart, parameters: [
            "participant_count": participantCount,
            "session_type": sessionType
        ])
    }
    
    static func trackVoiceChat(
        duration: TimeInterval,
        participantCount: Int
    ) {
        AnalyticsManager.shared.trackCustomEvent(name: "voice_chat_used", parameters: [
            "duration": duration,
            "participant_count": participantCount
        ])
    }
    
    static func trackSharedAction(
        actionType: String,
        fromUser: String,
        toUsers: [String]
    ) {
        AnalyticsManager.shared.trackCustomEvent(name: "shared_action", parameters: [
            "action_type": actionType,
            "recipient_count": toUsers.count
        ])
    }
}

// MARK: - AI Optimization Analytics
struct AIOptimizationAnalytics {
    static func trackOptimizationUsed(
        optimizationType: String,
        inputData: [String: Any] = [:],
        processingTime: TimeInterval? = nil,
        resultQuality: String? = nil
    ) {
        var parameters: [String: Any] = [
            "optimization_type": optimizationType
        ]
        
        // Add sanitized input data
        for (key, value) in inputData {
            if let stringValue = value as? String, stringValue.count < 100 {
                parameters["input_\(key)"] = stringValue
            } else if let numericValue = value as? NSNumber {
                parameters["input_\(key)"] = numericValue
            }
        }
        
        if let processingTime = processingTime {
            parameters["processing_time"] = processingTime
        }
        
        if let resultQuality = resultQuality {
            parameters["result_quality"] = resultQuality
        }
        
        AnalyticsManager.shared.trackFeatureUsage(.aiOptimizationUsed, parameters: parameters)
    }
    
    static func trackSuggestionAccepted(
        suggestionType: String,
        confidence: Float? = nil
    ) {
        var parameters: [String: Any] = [
            "suggestion_type": suggestionType,
            "action": "accepted"
        ]
        
        if let confidence = confidence {
            parameters["confidence"] = confidence
        }
        
        AnalyticsManager.shared.trackCustomEvent(name: "ai_suggestion_feedback", parameters: parameters)
    }
    
    static func trackSuggestionRejected(
        suggestionType: String,
        reason: String? = nil
    ) {
        var parameters: [String: Any] = [
            "suggestion_type": suggestionType,
            "action": "rejected"
        ]
        
        if let reason = reason {
            parameters["rejection_reason"] = reason
        }
        
        AnalyticsManager.shared.trackCustomEvent(name: "ai_suggestion_feedback", parameters: parameters)
    }
}

// MARK: - Settings Analytics
struct SettingsAnalytics {
    static func trackSettingChanged(
        settingName: String,
        oldValue: Any?,
        newValue: Any,
        category: String? = nil
    ) {
        var parameters: [String: Any] = [
            "setting_name": settingName,
            "new_value": String(describing: newValue)
        ]
        
        if let oldValue = oldValue {
            parameters["old_value"] = String(describing: oldValue)
        }
        
        if let category = category {
            parameters["category"] = category
        }
        
        AnalyticsManager.shared.trackFeatureUsage(.settingsChanged, parameters: parameters)
    }
    
    static func trackFeatureToggle(
        featureName: String,
        enabled: Bool,
        source: String = "settings"
    ) {
        AnalyticsManager.shared.trackCustomEvent(name: "feature_toggle", parameters: [
            "feature_name": featureName,
            "enabled": enabled,
            "source": source
        ])
    }
}

// MARK: - Tutorial Analytics
struct TutorialAnalytics {
    static func trackTutorialStarted(
        tutorialName: String,
        userType: String = "new"
    ) {
        AnalyticsManager.shared.trackCustomEvent(name: "tutorial_started", parameters: [
            "tutorial_name": tutorialName,
            "user_type": userType
        ])
    }
    
    static func trackTutorialCompleted(
        tutorialName: String,
        completionTime: TimeInterval,
        stepsCompleted: Int,
        totalSteps: Int
    ) {
        AnalyticsManager.shared.trackFeatureUsage(.tutorialCompleted, parameters: [
            "tutorial_name": tutorialName,
            "completion_time": completionTime,
            "steps_completed": stepsCompleted,
            "total_steps": totalSteps,
            "completion_rate": Double(stepsCompleted) / Double(totalSteps)
        ])
    }
    
    static func trackTutorialSkipped(
        tutorialName: String,
        stepWhenSkipped: Int,
        totalSteps: Int
    ) {
        AnalyticsManager.shared.trackCustomEvent(name: "tutorial_skipped", parameters: [
            "tutorial_name": tutorialName,
            "step_when_skipped": stepWhenSkipped,
            "total_steps": totalSteps,
            "progress_when_skipped": Double(stepWhenSkipped) / Double(totalSteps)
        ])
    }
}

// MARK: - Export/Share Analytics
struct ExportShareAnalytics {
    static func trackExport(
        exportType: String,
        fileFormat: String,
        fileSize: Int64? = nil,
        exportDuration: TimeInterval? = nil
    ) {
        var parameters: [String: Any] = [
            "export_type": exportType,
            "file_format": fileFormat
        ]
        
        if let fileSize = fileSize {
            parameters["file_size"] = fileSize
        }
        
        if let exportDuration = exportDuration {
            parameters["export_duration"] = exportDuration
        }
        
        AnalyticsManager.shared.trackFeatureUsage(.exportAction, parameters: parameters)
    }
    
    static func trackShare(
        shareMethod: String,
        contentType: String,
        recipientCount: Int? = nil
    ) {
        var parameters: [String: Any] = [
            "share_method": shareMethod,
            "content_type": contentType
        ]
        
        if let recipientCount = recipientCount {
            parameters["recipient_count"] = recipientCount
        }
        
        AnalyticsManager.shared.trackFeatureUsage(.shareAction, parameters: parameters)
    }
}

// MARK: - Error Analytics Helper
struct ErrorAnalytics {
    static func trackUserError(
        errorType: String,
        errorMessage: String,
        context: [String: Any] = [:],
        severity: EventSeverity = .medium
    ) {
        var parameters = context
        parameters["error_type"] = errorType
        parameters["user_facing"] = true
        
        AnalyticsManager.shared.trackCustomEvent(
            name: "user_error",
            parameters: parameters,
            severity: severity
        )
    }
    
    static func trackRecoveryAction(
        errorType: String,
        recoveryAction: String,
        successful: Bool
    ) {
        AnalyticsManager.shared.trackCustomEvent(name: "error_recovery", parameters: [
            "error_type": errorType,
            "recovery_action": recoveryAction,
            "successful": successful
        ])
    }
}

// MARK: - Onboarding Analytics
struct OnboardingAnalytics {
    static func trackOnboardingStep(
        stepName: String,
        stepNumber: Int,
        totalSteps: Int,
        timeSpent: TimeInterval? = nil
    ) {
        var parameters: [String: Any] = [
            "step_name": stepName,
            "step_number": stepNumber,
            "total_steps": totalSteps,
            "progress": Double(stepNumber) / Double(totalSteps)
        ]
        
        if let timeSpent = timeSpent {
            parameters["time_spent"] = timeSpent
        }
        
        AnalyticsManager.shared.trackUserEngagement(.screenView, parameters: parameters)
    }
    
    static func trackOnboardingCompleted(
        totalTime: TimeInterval,
        stepsCompleted: Int,
        totalSteps: Int
    ) {
        AnalyticsManager.shared.trackCustomEvent(name: "onboarding_completed", parameters: [
            "total_time": totalTime,
            "steps_completed": stepsCompleted,
            "total_steps": totalSteps,
            "completion_rate": Double(stepsCompleted) / Double(totalSteps)
        ])
    }
}