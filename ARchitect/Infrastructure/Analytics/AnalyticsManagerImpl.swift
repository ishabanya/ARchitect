import Foundation
import Combine

/// Implementation of AnalyticsManagerProtocol
final class AnalyticsManagerImpl: AnalyticsManagerProtocol {
    private var configuration: AnalyticsConfiguration?
    private var isInitialized = false
    private var eventQueue: [AnalyticsEvent] = []
    private let maxQueueSize = 100
    
    // MARK: - Event Tracking
    func trackUserEngagement(_ event: UserEngagementEvent, parameters: [String: Any]) {
        let analyticsEvent = AnalyticsEvent(
            name: event.name,
            parameters: parameters,
            timestamp: Date()
        )
        
        queueEvent(analyticsEvent)
        
        if isInitialized {
            sendEvent(analyticsEvent)
        }
    }
    
    func trackScreenView(_ screenName: String) {
        trackUserEngagement(.customEvent("screen_view"), parameters: [
            "screen_name": screenName,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackError(_ error: Error, context: [String: Any]? = nil) {
        var parameters = context ?? [:]
        parameters["error_description"] = error.localizedDescription
        parameters["error_domain"] = (error as NSError).domain
        parameters["error_code"] = (error as NSError).code
        
        trackUserEngagement(.error, parameters: parameters)
    }
    
    func trackPerformanceMetric(_ metric: PerformanceMetric, value: Double, context: [String: Any]? = nil) {
        var parameters = context ?? [:]
        parameters["metric_name"] = metric.name
        parameters["metric_value"] = value
        parameters["unit"] = getUnitForMetric(metric)
        
        trackUserEngagement(.performance, parameters: parameters)
    }
    
    // MARK: - User Properties
    func setUserProperty(_ value: String, forName property: String) {
        // Implementation would depend on analytics provider
        logDebug("Setting user property: \(property) = \(value)", category: .analytics)
    }
    
    func setUserId(_ userId: String) {
        // Implementation would depend on analytics provider
        logDebug("Setting user ID: \(userId)", category: .analytics)
    }
    
    // MARK: - Session Management
    func startSession() {
        trackUserEngagement(.sessionStart, parameters: [
            "session_start_time": Date().timeIntervalSince1970,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown"
        ])
    }
    
    func endSession() {
        trackUserEngagement(.sessionEnd, parameters: [
            "session_end_time": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Configuration
    func configure(with configuration: AnalyticsConfiguration) {
        self.configuration = configuration
        self.isInitialized = true
        
        // Send queued events
        sendQueuedEvents()
        
        logInfo("Analytics manager configured", category: .analytics, context: LogContext(customData: [
            "debug_mode": configuration.debugMode,
            "automatic_session_tracking": configuration.automaticSessionTracking
        ]))
    }
    
    func enableDebugMode(_ enabled: Bool) {
        configuration = AnalyticsConfiguration(
            apiKey: configuration?.apiKey ?? "",
            debugMode: enabled,
            automaticSessionTracking: configuration?.automaticSessionTracking ?? true,
            crashReporting: configuration?.crashReporting ?? true
        )
    }
    
    // MARK: - Private Methods
    private func queueEvent(_ event: AnalyticsEvent) {
        eventQueue.append(event)
        
        // Keep queue size manageable
        if eventQueue.count > maxQueueSize {
            eventQueue.removeFirst()
        }
    }
    
    private func sendEvent(_ event: AnalyticsEvent) {
        // In a real implementation, this would send to your analytics provider
        if configuration?.debugMode == true {
            print("📊 Analytics Event: \(event.name) - \(event.parameters)")
        }
        
        logDebug("Analytics event sent: \(event.name)", category: .analytics, context: LogContext(customData: event.parameters))
    }
    
    private func sendQueuedEvents() {
        for event in eventQueue {
            sendEvent(event)
        }
        eventQueue.removeAll()
    }
    
    private func getUnitForMetric(_ metric: PerformanceMetric) -> String {
        switch metric {
        case .appLaunchTime, .arSessionStartTime, .modelLoadTime, .renderFrameTime:
            return "seconds"
        case .memoryUsage:
            return "bytes"
        case .cpuUsage:
            return "percentage"
        case .customMetric:
            return "value"
        }
    }
}

// MARK: - Supporting Types
private struct AnalyticsEvent {
    let name: String
    let parameters: [String: Any]
    let timestamp: Date
}