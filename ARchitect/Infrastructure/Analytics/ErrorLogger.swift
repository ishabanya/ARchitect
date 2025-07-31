import Foundation
import os.log
import CryptoKit

// MARK: - Privacy Level
enum PrivacyLevel {
    case public          // Safe to log and send to analytics
    case sensitive       // Can log locally but not send to analytics
    case private         // Only log error codes, no details
    case confidential    // Do not log at all
}

// MARK: - Error Log Entry
struct ErrorLogEntry {
    let id: UUID
    let timestamp: Date
    let errorCode: String
    let category: ErrorCategory
    let severity: ErrorSeverity
    let privacyLevel: PrivacyLevel
    let sanitizedMessage: String
    let contextHash: String // Hashed context for correlation without exposing data
    let sessionId: String
    let userId: String? // Hashed user identifier
    let deviceInfo: DeviceInfo
    let appVersion: String
    let osVersion: String
    
    struct DeviceInfo {
        let model: String
        let systemName: String
        let systemVersion: String
        let isSimulator: Bool
        let memoryPressure: String?
        let batteryLevel: Float?
        let networkType: String?
    }
}

// MARK: - Data Sanitizer
class DataSanitizer {
    private static let sensitivePatterns = [
        // Email patterns
        try! NSRegularExpression(pattern: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}", options: []),
        // Phone numbers
        try! NSRegularExpression(pattern: "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b", options: []),
        // Credit card numbers
        try! NSRegularExpression(pattern: "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b", options: []),
        // SSN patterns
        try! NSRegularExpression(pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b", options: []),
        // API keys (common patterns)
        try! NSRegularExpression(pattern: "(?i)(api[_-]?key|token|secret)[\"'\\s]*[:=][\"'\\s]*[a-zA-Z0-9_-]+", options: []),
        // File paths
        try! NSRegularExpression(pattern: "/(?:Users|home)/[^\\s/]+", options: []),
    ]
    
    static func sanitize(_ text: String, privacyLevel: PrivacyLevel) -> String {
        switch privacyLevel {
        case .public:
            return text
        case .sensitive:
            return sanitizeForSensitive(text)
        case .private:
            return "[PRIVATE_DATA_REDACTED]"
        case .confidential:
            return "[CONFIDENTIAL_DATA_REDACTED]"
        }
    }
    
    private static func sanitizeForSensitive(_ text: String) -> String {
        var sanitized = text
        
        for pattern in sensitivePatterns {
            sanitized = pattern.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: NSRange(location: 0, length: sanitized.utf16.count),
                withTemplate: "[REDACTED]"
            )
        }
        
        return sanitized
    }
    
    static func hashContext(_ context: [String: Any]) -> String {
        // Create a deterministic hash of the context for correlation
        let sortedKeys = context.keys.sorted()
        let contextString = sortedKeys.map { key in
            "\(key):\(String(describing: context[key]))"
        }.joined(separator: "|")
        
        return SHA256.hash(data: contextString.data(using: .utf8) ?? Data())
            .compactMap { String(format: "%02x", $0) }
            .joined()
            .prefix(16) // First 16 characters for brevity
            .description
    }
}

// MARK: - Error Logger
class ErrorLogger {
    static let shared = ErrorLogger()
    
    private let logger = Logger(subsystem: "com.architect.ARchitect", category: "ErrorLogger")
    private let localStorageManager = LocalLogStorageManager()
    private let analyticsManager = AnalyticsManager()
    private let sessionId: String
    private let hashedUserId: String?
    
    private let maxLocalLogEntries = 1000
    private let logRetentionDays = 30
    
    private init() {
        self.sessionId = UUID().uuidString
        self.hashedUserId = Self.createHashedUserId()
        
        // Schedule periodic cleanup
        scheduleLogCleanup()
    }
    
    // MARK: - Public Methods
    
    func logError(_ error: AppErrorProtocol, context: [String: Any] = [:]) {
        let privacyLevel = determinePrivacyLevel(for: error)
        let logEntry = createLogEntry(error: error, context: context, privacyLevel: privacyLevel)
        
        // Always log locally (respecting privacy level)
        logLocally(logEntry)
        
        // Send to analytics only if privacy level allows
        if shouldSendToAnalytics(privacyLevel: privacyLevel) {
            sendToAnalytics(logEntry)
        }
        
        // Log to system logger
        logToSystem(logEntry)
    }
    
    func getLocalLogs(category: ErrorCategory? = nil, 
                     severity: ErrorSeverity? = nil,
                     since: Date? = nil) -> [ErrorLogEntry] {
        return localStorageManager.retrieveLogs(
            category: category,
            severity: severity,
            since: since
        )
    }
    
    func exportLogsForSupport() -> Data? {
        let logs = getLocalLogs(since: Date().addingTimeInterval(-7 * 24 * 3600)) // Last 7 days
        
        let exportData: [String: Any] = [
            "sessionId": sessionId,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "deviceInfo": getCurrentDeviceInfo(),
            "logs": logs.map { logEntry in
                [
                    "timestamp": ISO8601DateFormatter().string(from: logEntry.timestamp),
                    "errorCode": logEntry.errorCode,
                    "category": logEntry.category.rawValue,
                    "severity": logEntry.severity.rawValue,
                    "message": logEntry.sanitizedMessage,
                    "contextHash": logEntry.contextHash
                ]
            }
        ]
        
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    func clearOldLogs() {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(logRetentionDays * 24 * 3600))
        localStorageManager.clearLogs(before: cutoffDate)
    }
    
    // MARK: - Private Methods
    
    private func createLogEntry(error: AppErrorProtocol, context: [String: Any], privacyLevel: PrivacyLevel) -> ErrorLogEntry {
        return ErrorLogEntry(
            id: UUID(),
            timestamp: Date(),
            errorCode: error.errorCode,
            category: error.errorCategory,
            severity: error.severity,
            privacyLevel: privacyLevel,
            sanitizedMessage: DataSanitizer.sanitize(error.userMessage, privacyLevel: privacyLevel),
            contextHash: DataSanitizer.hashContext(context),
            sessionId: sessionId,
            userId: hashedUserId,
            deviceInfo: getCurrentDeviceInfo(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            osVersion: UIDevice.current.systemVersion
        )
    }
    
    private func determinePrivacyLevel(for error: AppErrorProtocol) -> PrivacyLevel {
        // Determine privacy level based on error type and category
        switch error.errorCategory {
        case .authentication:
            return .confidential
        case .network:
            // Network errors might contain URLs, so treat as sensitive
            return .sensitive
        case .storage:
            // Storage errors might contain file paths
            return .sensitive
        case .ar, .modelLoading, .ai, .collaboration:
            return .public
        case .ui, .system:
            return .public
        }
    }
    
    private func shouldSendToAnalytics(privacyLevel: PrivacyLevel) -> Bool {
        // Only send public and sensitive data to analytics
        // Sensitive data will be sanitized before sending
        return privacyLevel == .public || privacyLevel == .sensitive
    }
    
    private func logLocally(_ logEntry: ErrorLogEntry) {
        localStorageManager.storeLogs([logEntry])
        
        // Maintain log size limit
        if localStorageManager.getLogCount() > maxLocalLogEntries {
            let excessCount = localStorageManager.getLogCount() - maxLocalLogEntries
            localStorageManager.removeOldestLogs(count: excessCount)
        }
    }
    
    private func sendToAnalytics(_ logEntry: ErrorLogEntry) {
        // Prepare analytics data
        let analyticsData: [String: Any] = [
            "error_code": logEntry.errorCode,
            "category": logEntry.category.rawValue,
            "severity": logEntry.severity.rawValue,
            "session_id": logEntry.sessionId,
            "user_id": logEntry.userId ?? "anonymous",
            "app_version": logEntry.appVersion,
            "os_version": logEntry.osVersion,
            "device_model": logEntry.deviceInfo.model,
            "context_hash": logEntry.contextHash,
            "timestamp": logEntry.timestamp.timeIntervalSince1970
        ]
        
        analyticsManager.trackError(data: analyticsData)
    }
    
    private func logToSystem(_ logEntry: ErrorLogEntry) {
        let logMessage = "[\(logEntry.errorCode)] \(logEntry.sanitizedMessage)"
        
        switch logEntry.severity {
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
    
    private func getCurrentDeviceInfo() -> ErrorLogEntry.DeviceInfo {
        let device = UIDevice.current
        
        return ErrorLogEntry.DeviceInfo(
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            isSimulator: TARGET_OS_SIMULATOR != 0,
            memoryPressure: getMemoryPressure(),
            batteryLevel: device.batteryLevel >= 0 ? device.batteryLevel : nil,
            networkType: getNetworkType()
        )
    }
    
    private func getMemoryPressure() -> String? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return nil }
        
        let memoryMB = Float(info.resident_size) / 1024 / 1024
        
        if memoryMB > 500 {
            return "high"
        } else if memoryMB > 200 {
            return "medium"
        } else {
            return "low"
        }
    }
    
    private func getNetworkType() -> String? {
        // This would typically use Network framework to determine connection type
        // For now, return a placeholder
        return "wifi" // Could be "cellular", "wifi", "none", etc.
    }
    
    private static func createHashedUserId() -> String? {
        // Create a stable, anonymous user identifier
        // This could be based on device identifiers, but respecting privacy
        let identifierForVendor = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        return SHA256.hash(data: identifierForVendor.data(using: .utf8) ?? Data())
            .compactMap { String(format: "%02x", $0) }
            .joined()
            .prefix(32)
            .description
    }
    
    private func scheduleLogCleanup() {
        // Schedule periodic cleanup of old logs
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.clearOldLogs()
        }
    }
}

// MARK: - Local Log Storage Manager
class LocalLogStorageManager {
    private let fileManager = FileManager.default
    private let logsDirectory: URL
    
    init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        logsDirectory = documentsDirectory.appendingPathComponent("ErrorLogs")
        
        // Create logs directory if it doesn't exist
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    func storeLogs(_ logs: [ErrorLogEntry]) {
        for log in logs {
            let fileName = "\(log.timestamp.timeIntervalSince1970)_\(log.id.uuidString).json"
            let fileURL = logsDirectory.appendingPathComponent(fileName)
            
            do {
                let data = try JSONEncoder().encode(log)
                try data.write(to: fileURL)
            } catch {
                print("Failed to store log entry: \(error)")
            }
        }
    }
    
    func retrieveLogs(category: ErrorCategory? = nil,
                     severity: ErrorSeverity? = nil,
                     since: Date? = nil) -> [ErrorLogEntry] {
        var logs: [ErrorLogEntry] = []
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: logsDirectory, 
                                                              includingPropertiesForKeys: nil,
                                                              options: [])
            
            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                if let data = try? Data(contentsOf: fileURL),
                   let log = try? JSONDecoder().decode(ErrorLogEntry.self, from: data) {
                    
                    // Apply filters
                    if let category = category, log.category != category { continue }
                    if let severity = severity, log.severity != severity { continue }
                    if let since = since, log.timestamp < since { continue }
                    
                    logs.append(log)
                }
            }
        } catch {
            print("Failed to retrieve logs: \(error)")
        }
        
        return logs.sorted { $0.timestamp > $1.timestamp }
    }
    
    func getLogCount() -> Int {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: logsDirectory,
                                                              includingPropertiesForKeys: nil,
                                                              options: [])
            return fileURLs.filter { $0.pathExtension == "json" }.count
        } catch {
            return 0
        }
    }
    
    func removeOldestLogs(count: Int) {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: logsDirectory,
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
            print("Failed to remove old logs: \(error)")
        }
    }
    
    func clearLogs(before date: Date) {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: logsDirectory,
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
            print("Failed to clear old logs: \(error)")
        }
    }
}

// MARK: - Analytics Manager
class AnalyticsManager {
    func trackError(data: [String: Any]) {
        // This would integrate with your analytics service (Firebase, Mixpanel, etc.)
        // For now, just log the event locally
        print("Analytics: Error tracked - \(data)")
    }
}

// MARK: - Codable Extensions
extension ErrorLogEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, errorCode, category, severity, privacyLevel
        case sanitizedMessage, contextHash, sessionId, userId
        case deviceInfo, appVersion, osVersion
    }
}

extension ErrorLogEntry.DeviceInfo: Codable {}

extension PrivacyLevel: Codable {}
extension ErrorCategory: Codable {}
extension ErrorSeverity: Codable {}