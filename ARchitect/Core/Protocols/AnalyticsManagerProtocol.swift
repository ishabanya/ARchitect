import Foundation
import Combine

/// Protocol defining analytics tracking capabilities
protocol AnalyticsManagerProtocol: AnyObject {
    // MARK: - Event Tracking
    func trackUserEngagement(_ event: UserEngagementEvent, parameters: [String: Any])
    func trackScreenView(_ screenName: String)
    func trackError(_ error: Error, context: [String: Any]?)
    func trackPerformanceMetric(_ metric: PerformanceMetric, value: Double, context: [String: Any]?)
    
    // MARK: - User Properties
    func setUserProperty(_ value: String, forName property: String)
    func setUserId(_ userId: String)
    
    // MARK: - Session Management
    func startSession()
    func endSession()
    
    // MARK: - Configuration
    func configure(with configuration: AnalyticsConfiguration)
    func enableDebugMode(_ enabled: Bool)
}

// MARK: - Supporting Types
enum UserEngagementEvent {
    case sessionStart
    case sessionEnd
    case featureUsed
    case error
    case performance
    case customEvent(String)
    
    var name: String {
        switch self {
        case .sessionStart: return "session_start"
        case .sessionEnd: return "session_end"
        case .featureUsed: return "feature_used"
        case .error: return "error_occurred"
        case .performance: return "performance_metric"
        case .customEvent(let name): return name
        }
    }
}

enum PerformanceMetric {
    case appLaunchTime
    case arSessionStartTime
    case modelLoadTime
    case renderFrameTime
    case memoryUsage
    case cpuUsage
    case customMetric(String)
    
    var name: String {
        switch self {
        case .appLaunchTime: return "app_launch_time"
        case .arSessionStartTime: return "ar_session_start_time"
        case .modelLoadTime: return "model_load_time"
        case .renderFrameTime: return "render_frame_time"
        case .memoryUsage: return "memory_usage"
        case .cpuUsage: return "cpu_usage"
        case .customMetric(let name): return name
        }
    }
}

struct AnalyticsConfiguration {
    let apiKey: String
    let debugMode: Bool
    let automaticSessionTracking: Bool
    let crashReporting: Bool
    
    init(
        apiKey: String,
        debugMode: Bool = false,
        automaticSessionTracking: Bool = true,
        crashReporting: Bool = true
    ) {
        self.apiKey = apiKey
        self.debugMode = debugMode
        self.automaticSessionTracking = automaticSessionTracking
        self.crashReporting = crashReporting
    }
}