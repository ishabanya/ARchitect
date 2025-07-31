import Foundation
import CryptoKit

// MARK: - Privacy Level
public enum PrivacyLevel: Int, CaseIterable, Comparable {
    case public = 0        // Safe to log and share
    case internal = 1      // Safe to log locally, not share
    case sensitive = 2     // Log with redaction, don't share
    case confidential = 3  // Don't log at all
    
    public static func < (lhs: PrivacyLevel, rhs: PrivacyLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Sensitive Data Patterns
public struct SensitiveDataPattern {
    let name: String
    let pattern: NSRegularExpression
    let replacement: String
    let privacyLevel: PrivacyLevel
    let category: Category
    
    enum Category {
        case personalInfo
        case financial
        case authentication
        case technical
        case location
        case device
    }
}

// MARK: - Privacy Filter Configuration
public struct PrivacyFilterConfiguration {
    let enabledForLogLevels: Set<LogLevel>
    let enabledForCategories: Set<LogCategory>
    let maxStringLength: Int
    let hashSensitiveData: Bool
    let preserveDataStructure: Bool
    let customPatterns: [SensitiveDataPattern]
    
    static let `default` = PrivacyFilterConfiguration(
        enabledForLogLevels: Set(LogLevel.allCases),
        enabledForCategories: Set(LogCategory.allCases),
        maxStringLength: 1000,
        hashSensitiveData: true,
        preserveDataStructure: true,
        customPatterns: []
    )
    
    static func forEnvironment(_ environment: AppEnvironment) -> PrivacyFilterConfiguration {
        switch environment {
        case .development:
            return PrivacyFilterConfiguration(
                enabledForLogLevels: [.info, .warning, .error, .critical],
                enabledForCategories: [.security, .user, .analytics],
                maxStringLength: 2000,
                hashSensitiveData: false,
                preserveDataStructure: true,
                customPatterns: []
            )
        case .staging:
            return PrivacyFilterConfiguration(
                enabledForLogLevels: Set(LogLevel.allCases),
                enabledForCategories: Set(LogCategory.allCases),
                maxStringLength: 1500,
                hashSensitiveData: true,
                preserveDataStructure: true,
                customPatterns: []
            )
        case .production:
            return PrivacyFilterConfiguration(
                enabledForLogLevels: Set(LogLevel.allCases),
                enabledForCategories: Set(LogCategory.allCases),
                maxStringLength: 500,
                hashSensitiveData: true,
                preserveDataStructure: false,
                customPatterns: []
            )
        }
    }
}

// MARK: - Privacy Filter
public class PrivacyFilter {
    private let configuration: PrivacyFilterConfiguration
    private let sensitivePatterns: [SensitiveDataPattern]
    private let hasher = SHA256()
    
    init(configuration: PrivacyFilterConfiguration = .default) {
        self.configuration = configuration
        self.sensitivePatterns = Self.createDefaultPatterns() + configuration.customPatterns
    }
    
    // MARK: - Public Methods
    
    public func filter(_ message: String, level: LogLevel) -> String {
        guard shouldFilter(level: level, category: .general) else {
            return message
        }
        
        var filteredMessage = message
        
        // Apply length limit
        if filteredMessage.count > configuration.maxStringLength {
            let truncated = String(filteredMessage.prefix(configuration.maxStringLength))
            filteredMessage = truncated + "... [TRUNCATED]"
        }
        
        // Apply sensitive data patterns
        for pattern in sensitivePatterns {
            filteredMessage = applyPattern(pattern, to: filteredMessage)
        }
        
        return filteredMessage
    }
    
    public func filter(context: LogContext, level: LogLevel) -> LogContext {
        guard shouldFilter(level: level, category: .general) else {
            return context
        }
        
        let filteredUserInfo = filterUserInfo(context.userInfo)
        let filteredDeviceInfo = filterDeviceInfo(context.deviceInfo)
        let filteredCustomData = filterCustomData(context.customData)
        
        return LogContext(
            userInfo: filteredUserInfo,
            deviceInfo: filteredDeviceInfo,
            appInfo: context.appInfo, // App info is generally safe
            customData: filteredCustomData
        )
    }
    
    public func shouldLog(_ level: LogLevel, category: LogCategory) -> Bool {
        // Always allow critical and error logs
        if level >= .error {
            return true
        }
        
        // Check configuration
        return configuration.enabledForLogLevels.contains(level) &&
               configuration.enabledForCategories.contains(category)
    }
    
    public func classifyData(_ data: Any) -> PrivacyLevel {
        let stringValue = String(describing: data)
        
        // Check against sensitive patterns
        for pattern in sensitivePatterns {
            if pattern.pattern.firstMatch(in: stringValue, options: [], range: NSRange(location: 0, length: stringValue.utf16.count)) != nil {
                return pattern.privacyLevel
            }
        }
        
        // Default classification based on content analysis
        return classifyByContent(stringValue)
    }
    
    // MARK: - Private Methods
    
    private func shouldFilter(level: LogLevel, category: LogCategory) -> Bool {
        return configuration.enabledForLogLevels.contains(level) ||
               configuration.enabledForCategories.contains(category)
    }
    
    private func applyPattern(_ pattern: SensitiveDataPattern, to text: String) -> String {
        let range = NSRange(location: 0, length: text.utf16.count)
        
        if configuration.hashSensitiveData && pattern.privacyLevel >= .sensitive {
            // Replace with hashed version
            return pattern.pattern.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: pattern.replacement + "_" + hashString(text)
            )
        } else {
            // Simple replacement
            return pattern.pattern.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: pattern.replacement
            )
        }
    }
    
    private func filterUserInfo(_ userInfo: LogContext.UserInfo?) -> LogContext.UserInfo? {
        guard let userInfo = userInfo else { return nil }
        
        return LogContext.UserInfo(
            userId: filterUserId(userInfo.userId),
            userAction: filterUserAction(userInfo.userAction),
            screenName: userInfo.screenName, // Screen names are generally safe
            userAgent: filterUserAgent(userInfo.userAgent)
        )
    }
    
    private func filterDeviceInfo(_ deviceInfo: LogContext.DeviceInfo) -> LogContext.DeviceInfo {
        return LogContext.DeviceInfo(
            deviceModel: deviceInfo.deviceModel, // Generally safe
            systemName: deviceInfo.systemName,   // Generally safe
            systemVersion: deviceInfo.systemVersion, // Generally safe
            appVersion: deviceInfo.appVersion,   // Generally safe
            buildNumber: deviceInfo.buildNumber, // Generally safe
            isSimulator: deviceInfo.isSimulator, // Generally safe
            locale: filterLocale(deviceInfo.locale),
            timezone: filterTimezone(deviceInfo.timezone),
            batteryLevel: deviceInfo.batteryLevel, // Generally safe
            batteryState: deviceInfo.batteryState, // Generally safe
            memoryUsage: deviceInfo.memoryUsage,   // Generally safe
            diskSpace: deviceInfo.diskSpace,       // Generally safe
            networkType: deviceInfo.networkType    // Generally safe
        )
    }
    
    private func filterCustomData(_ customData: [String: Any]) -> [String: Any] {
        var filtered: [String: Any] = [:]
        
        for (key, value) in customData {
            let filteredKey = filterString(key)
            let filteredValue = filterValue(value)
            filtered[filteredKey] = filteredValue
        }
        
        return filtered
    }
    
    private func filterValue(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return filterString(string)
        case let array as [Any]:
            return array.map { filterValue($0) }
        case let dict as [String: Any]:
            return filterCustomData(dict)
        case let number as NSNumber:
            return number // Numbers are generally safe
        case let bool as Bool:
            return bool // Booleans are generally safe
        default:
            return filterString(String(describing: value))
        }
    }
    
    private func filterString(_ string: String) -> String {
        return filter(string, level: .info)
    }
    
    private func filterUserId(_ userId: String?) -> String? {
        guard let userId = userId else { return nil }
        
        // User IDs should always be hashed for privacy
        if configuration.hashSensitiveData {
            return "user_" + hashString(userId)
        } else {
            return "[USER_ID_REDACTED]"
        }
    }
    
    private func filterUserAction(_ userAction: String?) -> String? {
        guard let userAction = userAction else { return nil }
        
        // User actions are generally safe but may contain sensitive data
        return filterString(userAction)
    }
    
    private func filterUserAgent(_ userAgent: String?) -> String? {
        guard let userAgent = userAgent else { return nil }
        
        // User agents may contain device-specific information
        return filterString(userAgent)
    }
    
    private func filterLocale(_ locale: String) -> String {
        // Locale is generally safe but might be considered sensitive in some contexts
        if AppEnvironment.current == .production {
            return locale.components(separatedBy: "_").first ?? "unknown"
        }
        return locale
    }
    
    private func filterTimezone(_ timezone: String) -> String {
        // Timezone can be location-sensitive
        if AppEnvironment.current == .production {
            return "GMT" // Generalize timezone in production
        }
        return timezone
    }
    
    private func classifyByContent(_ content: String) -> PrivacyLevel {
        let lowercased = content.lowercased()
        
        // High-risk keywords
        let confidentialKeywords = ["password", "secret", "key", "token", "auth", "credential"]
        if confidentialKeywords.contains(where: lowercased.contains) {
            return .confidential
        }
        
        // Medium-risk keywords
        let sensitiveKeywords = ["user", "email", "phone", "address", "location", "personal"]
        if sensitiveKeywords.contains(where: lowercased.contains) {
            return .sensitive
        }
        
        // Low-risk keywords
        let internalKeywords = ["debug", "trace", "internal", "temp"]
        if internalKeywords.contains(where: lowercased.contains) {
            return .internal
        }
        
        return .public
    }
    
    private func hashString(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "hash_error" }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }
    
    // MARK: - Default Patterns
    
    private static func createDefaultPatterns() -> [SensitiveDataPattern] {
        var patterns: [SensitiveDataPattern] = []
        
        // Email addresses
        if let emailPattern = try? NSRegularExpression(pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "Email",
                pattern: emailPattern,
                replacement: "[EMAIL_REDACTED]",
                privacyLevel: .sensitive,
                category: .personalInfo
            ))
        }
        
        // Phone numbers (US format)
        if let phonePattern = try? NSRegularExpression(pattern: "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "Phone",
                pattern: phonePattern,
                replacement: "[PHONE_REDACTED]",
                privacyLevel: .sensitive,
                category: .personalInfo
            ))
        }
        
        // Credit card numbers
        if let ccPattern = try? NSRegularExpression(pattern: "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "CreditCard",
                pattern: ccPattern,
                replacement: "[CC_REDACTED]",
                privacyLevel: .confidential,
                category: .financial
            ))
        }
        
        // SSN (US format)
        if let ssnPattern = try? NSRegularExpression(pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "SSN",
                pattern: ssnPattern,
                replacement: "[SSN_REDACTED]",
                privacyLevel: .confidential,
                category: .personalInfo
            ))
        }
        
        // API Keys (common patterns)
        if let apiKeyPattern = try? NSRegularExpression(pattern: "(?i)(api[_-]?key|token|secret)[\"'\\s]*[:=][\"'\\s]*[a-zA-Z0-9_-]+", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "APIKey",
                pattern: apiKeyPattern,
                replacement: "[API_KEY_REDACTED]",
                privacyLevel: .confidential,
                category: .authentication
            ))
        }
        
        // Passwords
        if let passwordPattern = try? NSRegularExpression(pattern: "(?i)(password|pwd|pass)[\"'\\s]*[:=][\"'\\s]*\\S+", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "Password",
                pattern: passwordPattern,
                replacement: "[PASSWORD_REDACTED]",
                privacyLevel: .confidential,
                category: .authentication
            ))
        }
        
        // IP Addresses
        if let ipPattern = try? NSRegularExpression(pattern: "\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "IPAddress",
                pattern: ipPattern,
                replacement: "[IP_REDACTED]",
                privacyLevel: .sensitive,
                category: .technical
            ))
        }
        
        // File paths (home directory)
        if let pathPattern = try? NSRegularExpression(pattern: "/(?:Users|home)/[^\\s/]+", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "FilePath",
                pattern: pathPattern,
                replacement: "[PATH_REDACTED]",
                privacyLevel: .internal,
                category: .technical
            ))
        }
        
        // UUIDs (might be sensitive user identifiers)
        if let uuidPattern = try? NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "UUID",
                pattern: uuidPattern,
                replacement: "[UUID_REDACTED]",
                privacyLevel: .internal,
                category: .technical
            ))
        }
        
        // URLs with query parameters (might contain sensitive data)
        if let urlPattern = try? NSRegularExpression(pattern: "https?://[^\\s]+\\?[^\\s]+", options: []) {
            patterns.append(SensitiveDataPattern(
                name: "URLWithParams",
                pattern: urlPattern,
                replacement: "[URL_WITH_PARAMS_REDACTED]",
                privacyLevel: .sensitive,
                category: .technical
            ))
        }
        
        return patterns
    }
}

// MARK: - Privacy Extensions
extension LogContext.DeviceInfo {
    init(deviceModel: String, systemName: String, systemVersion: String, appVersion: String, buildNumber: String, isSimulator: Bool, locale: String, timezone: String, batteryLevel: Float?, batteryState: String?, memoryUsage: Int64?, diskSpace: Int64?, networkType: String?) {
        self.deviceModel = deviceModel
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.isSimulator = isSimulator
        self.locale = locale
        self.timezone = timezone
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
        self.memoryUsage = memoryUsage
        self.diskSpace = diskSpace
        self.networkType = networkType
    }
}

// MARK: - Privacy-Aware Logging Extensions
extension Logger {
    public func logWithPrivacyLevel(_ level: LogLevel,
                                   category: LogCategory = .general,
                                   message: String,
                                   privacyLevel: PrivacyLevel,
                                   file: String = #file,
                                   function: String = #function,
                                   line: Int = #line,
                                   context: LogContext = LogContext()) {
        
        // Don't log confidential data at all
        guard privacyLevel < .confidential else { return }
        
        // Adjust log level based on privacy level
        let adjustedLevel: LogLevel
        switch privacyLevel {
        case .public:
            adjustedLevel = level
        case .internal:
            adjustedLevel = max(level, .debug)
        case .sensitive:
            adjustedLevel = max(level, .warning)
        case .confidential:
            return // Already handled above
        }
        
        log(adjustedLevel, category: category, message: message, file: file, function: function, line: line, context: context)
    }
    
    public func logPersonalInfo(_ message: String,
                               category: LogCategory = .user,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line,
                               context: LogContext = LogContext()) {
        logWithPrivacyLevel(.info, category: category, message: message, privacyLevel: .sensitive, file: file, function: function, line: line, context: context)
    }
    
    public func logSecurityEvent(_ message: String,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line,
                                context: LogContext = LogContext()) {
        logWithPrivacyLevel(.warning, category: .security, message: message, privacyLevel: .internal, file: file, function: function, line: line, context: context)
    }
    
    public func logSensitiveOperation(_ message: String,
                                     category: LogCategory = .general,
                                     file: String = #file,
                                     function: String = #function,
                                     line: Int = #line,
                                     context: LogContext = LogContext()) {
        logWithPrivacyLevel(.info, category: category, message: message, privacyLevel: .sensitive, file: file, function: function, line: line, context: context)
    }
}

// MARK: - Data Classification Helper
public class DataClassifier {
    private let privacyFilter = PrivacyFilter()
    
    public func classify(_ data: Any) -> (level: PrivacyLevel, recommendation: String) {
        let level = privacyFilter.classifyData(data)
        let recommendation = getRecommendation(for: level)
        return (level, recommendation)
    }
    
    private func getRecommendation(for level: PrivacyLevel) -> String {
        switch level {
        case .public:
            return "Safe to log and share"
        case .internal:
            return "Safe to log locally, avoid sharing"
        case .sensitive:
            return "Log with redaction, don't share externally"
        case .confidential:
            return "Do not log this data"
        }
    }
}

// MARK: - Privacy Audit
public struct PrivacyAudit {
    let timestamp: Date
    let totalLogs: Int
    let logsByPrivacyLevel: [PrivacyLevel: Int]
    let sensitiveDataDetected: [String]
    let recommendations: [String]
    
    static func performAudit(on logs: [LogEntry]) -> PrivacyAudit {
        let classifier = DataClassifier()
        var logsByPrivacyLevel: [PrivacyLevel: Int] = [:]
        var sensitiveDataDetected: Set<String> = []
        var recommendations: [String] = []
        
        for log in logs {
            let (level, _) = classifier.classify(log.message)
            logsByPrivacyLevel[level, default: 0] += 1
            
            if level >= .sensitive {
                sensitiveDataDetected.insert(log.category.rawValue)
            }
        }
        
        // Generate recommendations
        if logsByPrivacyLevel[.confidential, default: 0] > 0 {
            recommendations.append("Confidential data detected in logs - review filtering rules")
        }
        
        if logsByPrivacyLevel[.sensitive, default: 0] > 10 {
            recommendations.append("High volume of sensitive data in logs - consider stricter filtering")
        }
        
        return PrivacyAudit(
            timestamp: Date(),
            totalLogs: logs.count,
            logsByPrivacyLevel: logsByPrivacyLevel,
            sensitiveDataDetected: Array(sensitiveDataDetected),
            recommendations: recommendations
        )
    }
}