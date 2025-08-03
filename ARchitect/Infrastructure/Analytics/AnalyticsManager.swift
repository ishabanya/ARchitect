import Foundation
import UIKit
import CryptoKit
import os.log

// MARK: - Event Types
enum AnalyticsEventType: String, CaseIterable {
    case userEngagement = "user_engagement"
    case featureUsage = "feature_usage"
    case performance = "performance"
    case customAction = "custom_action"
    case sessionLifecycle = "session_lifecycle"
    case error = "error"
    case abTest = "ab_test"
}

// MARK: - Event Severity
enum EventSeverity: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

// MARK: - Analytics Event
struct AnalyticsEvent {
    let id: UUID
    let timestamp: Date
    let type: AnalyticsEventType
    let name: String
    let parameters: [String: Any]
    let severity: EventSeverity
    let privacyLevel: PrivacyLevel
    let sessionId: String
    let userId: String?
    let appVersion: String
    let osVersion: String
    let deviceInfo: DeviceInfo
    
    struct DeviceInfo: Codable {
        let model: String
        let systemName: String
        let systemVersion: String
        let isSimulator: Bool
        let screenSize: String
        let orientation: String
        let batteryLevel: Float?
        let networkType: String?
        let availableStorage: Int64?
        let totalMemory: Int64?
        let availableMemory: Int64?
    }
}

// MARK: - User Engagement Metrics
enum UserEngagementMetric: String, CaseIterable {
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case sessionDuration = "session_duration"
    case screenView = "screen_view"
    case screenTime = "screen_time"
    case userInteraction = "user_interaction"
    case appForeground = "app_foreground"
    case appBackground = "app_background"
    case firstLaunch = "first_launch"
    case dailyActiveUser = "daily_active_user"
    case weeklyActiveUser = "weekly_active_user"
    case monthlyActiveUser = "monthly_active_user"
    case userRetention = "user_retention"
}

// MARK: - Feature Usage Metrics
enum FeatureUsageMetric: String, CaseIterable {
    case arSessionStart = "ar_session_start"
    case arSessionEnd = "ar_session_end"
    case roomScanStart = "room_scan_start"
    case roomScanComplete = "room_scan_complete"
    case furniturePlacement = "furniture_placement"
    case furnitureRemoval = "furniture_removal"
    case measurementTaken = "measurement_taken"
    case shareAction = "share_action"
    case exportAction = "export_action"
    case collaborationStart = "collaboration_start"
    case aiOptimizationUsed = "ai_optimization_used"
    case tutorialCompleted = "tutorial_completed"
    case settingsChanged = "settings_changed"
    case featureDiscovered = "feature_discovered"
    case featureAbandoned = "feature_abandoned"
}

// MARK: - Performance Metrics
enum PerformanceMetric: String, CaseIterable {
    case appLaunchTime = "app_launch_time"
    case arInitializationTime = "ar_initialization_time"
    case modelLoadTime = "model_load_time"
    case scanProcessingTime = "scan_processing_time"
    case renderingFPS = "rendering_fps"
    case memoryUsage = "memory_usage"
    case batteryDrain = "battery_drain"
    case networkLatency = "network_latency"
    case cacheHitRate = "cache_hit_rate"
    case errorRate = "error_rate"
    case crashRate = "crash_rate"
    case thermalState = "thermal_state"
}

// MARK: - Privacy Compliant Analytics Manager
class AnalyticsManager {
    static let shared = AnalyticsManager()
    
    private let logger = Logger(subsystem: "com.architect.ARchitect", category: "Analytics")
    private let localStorageManager = LocalAnalyticsStorageManager()
    private let privacyFilter = AnalyticsPrivacyFilter()
    
    private let sessionId: String
    private let hashedUserId: String?
    private var sessionStartTime: Date
    private var currentScreenStartTime: Date?
    private var currentScreen: String?
    
    private let maxLocalEvents = 5000
    private let eventRetentionDays = 90
    private let batchUploadSize = 50
    
    // Privacy and consent management
    private var analyticsEnabled: Bool = true
    private var personalizedAdsEnabled: Bool = false
    private var dataProcessingConsent: Bool = false
    
    // A/B Testing
    private var abTestAssignments: [String: String] = [:]
    
    private init() {
        self.sessionId = UUID().uuidString
        self.hashedUserId = Self.createHashedUserId()
        self.sessionStartTime = Date()
        
        setupAnalytics()
        trackSessionStart()
    }
    
    // MARK: - Privacy and Consent
    
    func updateConsentSettings(
        analyticsEnabled: Bool,
        personalizedAdsEnabled: Bool,
        dataProcessingConsent: Bool
    ) {
        self.analyticsEnabled = analyticsEnabled
        self.personalizedAdsEnabled = personalizedAdsEnabled
        self.dataProcessingConsent = dataProcessingConsent
        
        trackEvent(
            type: .userEngagement,
            name: "consent_updated",
            parameters: [
                "analytics_enabled": analyticsEnabled,
                "personalized_ads_enabled": personalizedAdsEnabled,
                "data_processing_consent": dataProcessingConsent
            ],
            severity: .medium,
            privacyLevel: .public
        )
        
        UserDefaults.standard.set(analyticsEnabled, forKey: "analytics_enabled")
        UserDefaults.standard.set(personalizedAdsEnabled, forKey: "personalized_ads_enabled")
        UserDefaults.standard.set(dataProcessingConsent, forKey: "data_processing_consent")
    }
    
    // MARK: - User Engagement Tracking
    
    func trackUserEngagement(_ metric: UserEngagementMetric, parameters: [String: Any] = [:]) {
        guard analyticsEnabled else { return }
        
        var eventParameters = parameters
        
        switch metric {
        case .sessionStart:
            eventParameters["session_id"] = sessionId
            eventParameters["is_first_launch"] = isFirstLaunch()
        case .sessionEnd:
            eventParameters["session_duration"] = Date().timeIntervalSince(sessionStartTime)
        case .screenView:
            if let screen = parameters["screen_name"] as? String {
                trackScreenView(screen)
            }
        case .userInteraction:
            eventParameters["interaction_time"] = Date().timeIntervalSince1970
        default:
            break
        }
        
        trackEvent(
            type: .userEngagement,
            name: metric.rawValue,
            parameters: eventParameters,
            severity: .low,
            privacyLevel: .public
        )
    }
    
    func trackScreenView(_ screenName: String) {
        // Track previous screen time
        if let currentScreen = currentScreen,
           let startTime = currentScreenStartTime {
            trackUserEngagement(.screenTime, parameters: [
                "screen_name": currentScreen,
                "duration": Date().timeIntervalSince(startTime)
            ])
        }
        
        // Update current screen
        currentScreen = screenName
        currentScreenStartTime = Date()
        
        trackUserEngagement(.screenView, parameters: [
            "screen_name": screenName
        ])
    }
    
    // MARK: - Feature Usage Tracking
    
    func trackFeatureUsage(_ metric: FeatureUsageMetric, parameters: [String: Any] = [:]) {
        guard analyticsEnabled else { return }
        
        var eventParameters = parameters
        eventParameters["feature"] = metric.rawValue
        eventParameters["timestamp"] = Date().timeIntervalSince1970
        
        // Add context based on feature
        switch metric {
        case .arSessionStart, .arSessionEnd:
            eventParameters["ar_tracking_state"] = parameters["tracking_state"] ?? "unknown"
        case .roomScanStart, .roomScanComplete:
            eventParameters["scan_quality"] = parameters["quality"] ?? "unknown"
        case .furniturePlacement:
            eventParameters["furniture_category"] = parameters["category"] ?? "unknown"
            eventParameters["placement_method"] = parameters["method"] ?? "manual"
        default:
            break
        }
        
        trackEvent(
            type: .featureUsage,
            name: metric.rawValue,
            parameters: eventParameters,
            severity: .medium,
            privacyLevel: .public
        )
    }
    
    // MARK: - Performance Metrics
    
    func trackPerformanceMetric(_ metric: PerformanceMetric, value: Double, parameters: [String: Any] = [:]) {
        guard analyticsEnabled else { return }
        
        var eventParameters = parameters
        eventParameters["metric_value"] = value
        eventParameters["metric_unit"] = getMetricUnit(metric)
        eventParameters["device_model"] = UIDevice.current.model
        eventParameters["os_version"] = UIDevice.current.systemVersion
        
        // Add performance context
        eventParameters["memory_pressure"] = getMemoryPressure()
        eventParameters["thermal_state"] = getThermalState()
        eventParameters["battery_level"] = UIDevice.current.batteryLevel
        
        trackEvent(
            type: .performance,
            name: metric.rawValue,
            parameters: eventParameters,
            severity: getSeverityForPerformanceMetric(metric, value: value),
            privacyLevel: .public
        )
        
        // Alert on critical performance issues
        if getSeverityForPerformanceMetric(metric, value: value) == .critical {
            logger.critical("Critical performance issue: \(metric.rawValue) = \(value)")
        }
    }
    
    // MARK: - Custom Events
    
    func trackCustomEvent(name: String, parameters: [String: Any] = [:], severity: EventSeverity = .medium) {
        guard analyticsEnabled else { return }
        
        trackEvent(
            type: .customAction,
            name: name,
            parameters: parameters,
            severity: severity,
            privacyLevel: .public
        )
    }
    
    // MARK: - A/B Testing
    
    func getABTestVariant(testName: String, variants: [String], defaultVariant: String) -> String {
        // Check if user already has an assignment
        if let existingVariant = abTestAssignments[testName] {
            return existingVariant
        }
        
        // Create deterministic assignment based on hashed user ID
        guard let userId = hashedUserId else { return defaultVariant }
        
        let testKey = "\(testName)_\(userId)"
        let hash = SHA256.hash(data: testKey.data(using: .utf8) ?? Data())
        let hashInt = hash.withUnsafeBytes { bytes in
            bytes.bindMemory(to: UInt32.self).first ?? 0
        }
        
        let variantIndex = Int(hashInt) % variants.count
        let assignedVariant = variants[variantIndex]
        
        // Store assignment
        abTestAssignments[testName] = assignedVariant
        
        // Track assignment
        trackEvent(
            type: .abTest,
            name: "ab_test_assignment",
            parameters: [
                "test_name": testName,
                "variant": assignedVariant,
                "available_variants": variants
            ],
            severity: .low,
            privacyLevel: .public
        )
        
        return assignedVariant
    }
    
    func trackABTestConversion(testName: String, conversionEvent: String, parameters: [String: Any] = [:]) {
        guard let variant = abTestAssignments[testName] else { return }
        
        var eventParameters = parameters
        eventParameters["test_name"] = testName
        eventParameters["variant"] = variant
        eventParameters["conversion_event"] = conversionEvent
        
        trackEvent(
            type: .abTest,
            name: "ab_test_conversion",
            parameters: eventParameters,
            severity: .medium,
            privacyLevel: .public
        )
    }
    
    // MARK: - Error and Crash Tracking
    
    func trackError(error: Error, context: [String: Any] = [:]) {
        var eventParameters = context
        eventParameters["error_description"] = privacyFilter.sanitizeError(error)
        eventParameters["error_domain"] = (error as NSError).domain
        eventParameters["error_code"] = (error as NSError).code
        
        trackEvent(
            type: .error,
            name: "error_occurred",
            parameters: eventParameters,
            severity: .high,
            privacyLevel: .sensitive
        )
    }
    
    // MARK: - Core Event Tracking
    
    private func trackEvent(
        type: AnalyticsEventType,
        name: String,
        parameters: [String: Any],
        severity: EventSeverity,
        privacyLevel: PrivacyLevel
    ) {
        let event = AnalyticsEvent(
            id: UUID(),
            timestamp: Date(),
            type: type,
            name: name,
            parameters: privacyFilter.sanitizeParameters(parameters, privacyLevel: privacyLevel),
            severity: severity,
            privacyLevel: privacyLevel,
            sessionId: sessionId,
            userId: hashedUserId,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            osVersion: UIDevice.current.systemVersion,
            deviceInfo: getCurrentDeviceInfo()
        )
        
        // Store locally
        localStorageManager.storeEvent(event)
        
        // Log to system
        logEventToSystem(event)
        
        // Send to analytics service (respecting privacy)
        if shouldSendToAnalytics(privacyLevel: privacyLevel) {
            sendToAnalyticsService(event)
        }
        
        // Maintain storage limits
        maintainStorageLimits()
    }
    
    // MARK: - Real-time Dashboard Support
    
    func getRealtimeMetrics() -> [String: Any] {
        let currentSession = Date().timeIntervalSince(sessionStartTime)
        
        return [
            "session_id": sessionId,
            "session_duration": currentSession,
            "current_screen": currentScreen ?? "unknown",
            "screen_time": currentScreenStartTime.map { Date().timeIntervalSince($0) } ?? 0,
            "device_info": getCurrentDeviceInfo(),
            "memory_usage": getMemoryUsage(),
            "battery_level": UIDevice.current.batteryLevel,
            "thermal_state": getThermalState(),
            "network_type": getNetworkType(),
            "recent_events": getRecentEvents(limit: 10)
        ]
    }
    
    func exportAnalyticsData(since: Date) -> Data? {
        let events = localStorageManager.getEvents(since: since)
        
        let exportData: [String: Any] = [
            "export_date": ISO8601DateFormatter().string(from: Date()),
            "session_id": sessionId,
            "user_id": hashedUserId ?? "anonymous",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
            "device_info": getCurrentDeviceInfo(),
            "events": events.map { event in
                [
                    "id": event.id.uuidString,
                    "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                    "type": event.type.rawValue,
                    "name": event.name,
                    "parameters": event.parameters,
                    "severity": event.severity.rawValue
                ]
            }
        ]
        
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    // MARK: - Private Helper Methods
    
    private func setupAnalytics() {
        // Load saved consent settings
        analyticsEnabled = UserDefaults.standard.bool(forKey: "analytics_enabled")
        personalizedAdsEnabled = UserDefaults.standard.bool(forKey: "personalized_ads_enabled")
        dataProcessingConsent = UserDefaults.standard.bool(forKey: "data_processing_consent")
        
        // Schedule periodic cleanup
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.cleanupOldEvents()
        }
        
        // Setup app lifecycle observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    private func trackSessionStart() {
        trackUserEngagement(.sessionStart, parameters: [
            "session_id": sessionId,
            "launch_time": sessionStartTime.timeIntervalSince1970
        ])
    }
    
    @objc private func appDidEnterBackground() {
        trackUserEngagement(.appBackground)
        
        // Track session end
        if let currentScreen = currentScreen,
           let startTime = currentScreenStartTime {
            trackUserEngagement(.screenTime, parameters: [
                "screen_name": currentScreen,
                "duration": Date().timeIntervalSince(startTime)
            ])
        }
        
        trackUserEngagement(.sessionEnd)
    }
    
    @objc private func appWillEnterForeground() {
        trackUserEngagement(.appForeground)
        
        // Start new session
        sessionStartTime = Date()
        trackSessionStart()
    }
    
    private func isFirstLaunch() -> Bool {
        let key = "has_launched_before"
        let hasLaunched = UserDefaults.standard.bool(forKey: key)
        if !hasLaunched {
            UserDefaults.standard.set(true, forKey: key)
            return true
        }
        return false
    }
    
    private func getCurrentDeviceInfo() -> AnalyticsEvent.DeviceInfo {
        let device = UIDevice.current
        let screen = UIScreen.main
        
        return AnalyticsEvent.DeviceInfo(
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            isSimulator: TARGET_OS_SIMULATOR != 0,
            screenSize: "\(Int(screen.bounds.width))x\(Int(screen.bounds.height))",
            orientation: getDeviceOrientation(),
            batteryLevel: device.batteryLevel >= 0 ? device.batteryLevel : nil,
            networkType: getNetworkType(),
            availableStorage: getAvailableStorage(),
            totalMemory: getTotalMemory(),
            availableMemory: getAvailableMemory()
        )
    }
    
    private func getDeviceOrientation() -> String {
        switch UIDevice.current.orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portrait_upside_down"
        case .landscapeLeft: return "landscape_left"
        case .landscapeRight: return "landscape_right"
        case .faceUp: return "face_up"
        case .faceDown: return "face_down"
        default: return "unknown"
        }
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    private func getMemoryPressure() -> String {
        let memoryMB = Float(getMemoryUsage()) / 1024 / 1024
        
        if memoryMB > 500 {
            return "high"
        } else if memoryMB > 200 {
            return "medium"
        } else {
            return "low"
        }
    }
    
    private func getThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
    
    private func getNetworkType() -> String {
        // Simplified network detection
        return "wifi" // Would use Network framework for real implementation
    }
    
    private func getAvailableStorage() -> Int64? {
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return values.volumeAvailableCapacity
        } catch {
            return nil
        }
    }
    
    private func getTotalMemory() -> Int64 {
        return Int64(ProcessInfo.processInfo.physicalMemory)
    }
    
    private func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }
    
    private func getMetricUnit(_ metric: PerformanceMetric) -> String {
        switch metric {
        case .appLaunchTime, .arInitializationTime, .modelLoadTime, .scanProcessingTime, .networkLatency:
            return "seconds"
        case .renderingFPS:
            return "fps"
        case .memoryUsage:
            return "bytes"
        case .batteryDrain:
            return "percentage"
        case .cacheHitRate, .errorRate, .crashRate:
            return "percentage"
        case .thermalState:
            return "state"
        }
    }
    
    private func getSeverityForPerformanceMetric(_ metric: PerformanceMetric, value: Double) -> EventSeverity {
        switch metric {
        case .appLaunchTime:
            return value > 5.0 ? .critical : value > 3.0 ? .high : .medium
        case .renderingFPS:
            return value < 30 ? .critical : value < 45 ? .high : .medium
        case .memoryUsage:
            let memoryMB = value / (1024 * 1024)
            return memoryMB > 500 ? .critical : memoryMB > 300 ? .high : .medium
        case .errorRate, .crashRate:
            return value > 5.0 ? .critical : value > 1.0 ? .high : .medium
        default:
            return .medium
        }
    }
    
    private func shouldSendToAnalytics(privacyLevel: PrivacyLevel) -> Bool {
        return analyticsEnabled && dataProcessingConsent && (privacyLevel == .public || privacyLevel == .sensitive)
    }
    
    private func sendToAnalyticsService(_ event: AnalyticsEvent) {
        // This would integrate with actual analytics services
        // For now, just log the event
        logger.info("Analytics event: \(event.name) - \(event.type.rawValue)")
    }
    
    private func logEventToSystem(_ event: AnalyticsEvent) {
        let logMessage = "[\(event.type.rawValue)] \(event.name)"
        
        switch event.severity {
        case .critical:
            logger.critical("\(logMessage)")
        case .high:
            logger.error("\(logMessage)")
        case .medium:
            logger.info("\(logMessage)")
        case .low:
            logger.debug("\(logMessage)")
        }
    }
    
    private func maintainStorageLimits() {
        if localStorageManager.getEventCount() > maxLocalEvents {
            let excessCount = localStorageManager.getEventCount() - maxLocalEvents
            localStorageManager.removeOldestEvents(count: excessCount)
        }
    }
    
    private func cleanupOldEvents() {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(eventRetentionDays * 24 * 3600))
        localStorageManager.clearEvents(before: cutoffDate)
    }
    
    private func getRecentEvents(limit: Int) -> [[String: Any]] {
        return localStorageManager.getRecentEvents(limit: limit).map { event in
            [
                "name": event.name,
                "type": event.type.rawValue,
                "timestamp": event.timestamp.timeIntervalSince1970,
                "severity": event.severity.rawValue
            ]
        }
    }
    
    private static func createHashedUserId() -> String? {
        let identifierForVendor = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        return SHA256.hash(data: identifierForVendor.data(using: .utf8) ?? Data())
            .compactMap { String(format: "%02x", $0) }
            .joined()
            .prefix(32)
            .description
    }
}

// MARK: - Analytics Privacy Filter
class AnalyticsPrivacyFilter {
    private static let sensitiveKeys = [
        "email", "phone", "address", "name", "password", "token", "key", "secret",
        "credit_card", "ssn", "license", "passport", "api_key", "auth_token"
    ]
    
    func sanitizeParameters(_ parameters: [String: Any], privacyLevel: PrivacyLevel) -> [String: Any] {
        switch privacyLevel {
        case .public:
            return parameters
        case .sensitive:
            return sanitizeForSensitive(parameters)
        case .private:
            return ["privacy_level": "private"]
        case .confidential:
            return ["privacy_level": "confidential"]
        }
    }
    
    func sanitizeError(_ error: Error) -> String {
        let errorDescription = error.localizedDescription
        
        // Remove potential sensitive information from error messages
        var sanitized = errorDescription
        
        // Remove file paths
        sanitized = sanitized.replacingOccurrences(
            of: "/Users/[^\\s/]+",
            with: "[USER_PATH]",
            options: .regularExpression
        )
        
        // Remove potential API keys or tokens
        sanitized = sanitized.replacingOccurrences(
            of: "(?i)(key|token|secret)[\"'\\s]*[:=][\"'\\s]*[a-zA-Z0-9_-]+",
            with: "[REDACTED_CREDENTIAL]",
            options: .regularExpression
        )
        
        return sanitized
    }
    
    private func sanitizeForSensitive(_ parameters: [String: Any]) -> [String: Any] {
        var sanitized: [String: Any] = [:]
        
        for (key, value) in parameters {
            let lowercaseKey = key.lowercased()
            
            if Self.sensitiveKeys.contains(where: { lowercaseKey.contains($0) }) {
                sanitized[key] = "[REDACTED]"
            } else if let stringValue = value as? String {
                sanitized[key] = sanitizeStringValue(stringValue)
            } else {
                sanitized[key] = value
            }
        }
        
        return sanitized
    }
    
    private func sanitizeStringValue(_ value: String) -> String {
        var sanitized = value
        
        // Email pattern
        sanitized = sanitized.replacingOccurrences(
            of: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
            with: "[EMAIL_REDACTED]",
            options: .regularExpression
        )
        
        // Phone number pattern
        sanitized = sanitized.replacingOccurrences(
            of: "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b",
            with: "[PHONE_REDACTED]",
            options: .regularExpression
        )
        
        return sanitized
    }
}

// MARK: - Local Analytics Storage Manager
class LocalAnalyticsStorageManager {
    private let fileManager = FileManager.default
    private let analyticsDirectory: URL
    
    init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        analyticsDirectory = documentsDirectory.appendingPathComponent("Analytics")
        
        try? fileManager.createDirectory(at: analyticsDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    func storeEvent(_ event: AnalyticsEvent) {
        let fileName = "\(event.timestamp.timeIntervalSince1970)_\(event.id.uuidString).json"
        let fileURL = analyticsDirectory.appendingPathComponent(fileName)
        
        do {
            let data = try JSONEncoder().encode(event)
            try data.write(to: fileURL)
        } catch {
            print("Failed to store analytics event: \(error)")
        }
    }
    
    func getEvents(since: Date? = nil, type: AnalyticsEventType? = nil) -> [AnalyticsEvent] {
        var events: [AnalyticsEvent] = []
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: analyticsDirectory,
                                                              includingPropertiesForKeys: nil,
                                                              options: [])
            
            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                if let data = try? Data(contentsOf: fileURL),
                   let event = try? JSONDecoder().decode(AnalyticsEvent.self, from: data) {
                    
                    // Apply filters
                    if let since = since, event.timestamp < since { continue }
                    if let type = type, event.type != type { continue }
                    
                    events.append(event)
                }
            }
        } catch {
            print("Failed to retrieve analytics events: \(error)")
        }
        
        return events.sorted { $0.timestamp > $1.timestamp }
    }
    
    func getRecentEvents(limit: Int) -> [AnalyticsEvent] {
        let allEvents = getEvents()
        return Array(allEvents.prefix(limit))
    }
    
    func getEventCount() -> Int {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: analyticsDirectory,
                                                              includingPropertiesForKeys: nil,
                                                              options: [])
            return fileURLs.filter { $0.pathExtension == "json" }.count
        } catch {
            return 0
        }
    }
    
    func removeOldestEvents(count: Int) {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: analyticsDirectory,
                                                              includingPropertiesForKeys: [.creationDateKey],
                                                              options: [])
            
            let sortedURLs = fileURLs
                .filter { $0.pathExtension == "json" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 < date2
                }
            
            for i in 0..<min(count, sortedURLs.count) {
                try? fileManager.removeItem(at: sortedURLs[i])
            }
        } catch {
            print("Failed to remove old analytics events: \(error)")
        }
    }
    
    func clearEvents(before date: Date) {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: analyticsDirectory,
                                                              includingPropertiesForKeys: [.creationDateKey],
                                                              options: [])
            
            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = resourceValues.creationDate,
                   creationDate < date {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Failed to clear old analytics events: \(error)")
        }
    }
}

// MARK: - Codable Extensions
extension AnalyticsEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, type, name, parameters, severity, privacyLevel
        case sessionId, userId, appVersion, osVersion, deviceInfo
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        type = try container.decode(AnalyticsEventType.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        severity = try container.decode(EventSeverity.self, forKey: .severity)
        privacyLevel = try container.decode(PrivacyLevel.self, forKey: .privacyLevel)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        deviceInfo = try container.decode(DeviceInfo.self, forKey: .deviceInfo)
        
        // Handle parameters as JSON
        let parametersData = try container.decode(Data.self, forKey: .parameters)
        parameters = (try? JSONSerialization.jsonObject(with: parametersData) as? [String: Any]) ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(severity, forKey: .severity)
        try container.encode(privacyLevel, forKey: .privacyLevel)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encode(deviceInfo, forKey: .deviceInfo)
        
        // Encode parameters as JSON data
        let parametersData = try JSONSerialization.data(withJSONObject: parameters)
        try container.encode(parametersData, forKey: .parameters)
    }
}

extension AnalyticsEventType: Codable {}
extension EventSeverity: Codable {}