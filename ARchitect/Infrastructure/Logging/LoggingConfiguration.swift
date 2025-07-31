import Foundation

// MARK: - Logging Configuration
public struct LoggingConfiguration {
    let minimumLogLevel: LogLevel
    let enabledCategories: Set<LogCategory>
    let useOSLog: Bool
    let printToConsole: Bool
    let sendToCrashReporting: Bool
    let sendToAnalytics: Bool
    let storage: LogStorageConfiguration
    let privacy: PrivacyFilterConfiguration
    let crash: CrashReporterConfiguration
    let performance: LoggingPerformanceConfiguration
    
    static let `default` = LoggingConfiguration(
        minimumLogLevel: .info,
        enabledCategories: Set(LogCategory.allCases),
        useOSLog: true,
        printToConsole: false,
        sendToCrashReporting: true,
        sendToAnalytics: false,
        storage: .default,
        privacy: .default,
        crash: .default,
        performance: .default
    )
    
    static var current: LoggingConfiguration {
        return forEnvironment(AppEnvironment.current)
    }
    
    static func forEnvironment(_ environment: AppEnvironment) -> LoggingConfiguration {
        switch environment {
        case .development:
            return LoggingConfiguration(
                minimumLogLevel: .verbose,
                enabledCategories: Set(LogCategory.allCases),
                useOSLog: true,
                printToConsole: true,
                sendToCrashReporting: true,
                sendToAnalytics: false,
                storage: LogStorageConfiguration.forEnvironment(environment),
                privacy: PrivacyFilterConfiguration.forEnvironment(environment),
                crash: CrashReporterConfiguration.forEnvironment(environment),
                performance: LoggingPerformanceConfiguration.forEnvironment(environment)
            )
        case .staging:
            return LoggingConfiguration(
                minimumLogLevel: .debug,
                enabledCategories: Set(LogCategory.allCases),
                useOSLog: true,
                printToConsole: false,
                sendToCrashReporting: true,
                sendToAnalytics: true,
                storage: LogStorageConfiguration.forEnvironment(environment),
                privacy: PrivacyFilterConfiguration.forEnvironment(environment),
                crash: CrashReporterConfiguration.forEnvironment(environment),
                performance: LoggingPerformanceConfiguration.forEnvironment(environment)
            )
        case .production:
            return LoggingConfiguration(
                minimumLogLevel: .warning,
                enabledCategories: [.general, .network, .ar, .crash, .performance],
                useOSLog: true,
                printToConsole: false,
                sendToCrashReporting: true,
                sendToAnalytics: true,
                storage: LogStorageConfiguration.forEnvironment(environment),
                privacy: PrivacyFilterConfiguration.forEnvironment(environment),
                crash: CrashReporterConfiguration.forEnvironment(environment),
                performance: LoggingPerformanceConfiguration.forEnvironment(environment)
            )
        }
    }
}

// MARK: - Logging Performance Configuration
public struct LoggingPerformanceConfiguration {
    let asyncLogging: Bool
    let batchProcessing: Bool
    let compressionThreshold: Int
    let maxQueueSize: Int
    let flushOnBackground: Bool
    let enableSampling: Bool
    let samplingRate: Double
    let maxMemoryUsage: Int
    
    static let `default` = LoggingPerformanceConfiguration(
        asyncLogging: true,
        batchProcessing: true,
        compressionThreshold: 1024 * 1024, // 1MB
        maxQueueSize: 1000,
        flushOnBackground: true,
        enableSampling: false,
        samplingRate: 1.0,
        maxMemoryUsage: 10 * 1024 * 1024 // 10MB
    )
    
    static func forEnvironment(_ environment: AppEnvironment) -> LoggingPerformanceConfiguration {
        switch environment {
        case .development:
            return LoggingPerformanceConfiguration(
                asyncLogging: false, // Synchronous for debugging
                batchProcessing: false,
                compressionThreshold: 5 * 1024 * 1024, // 5MB
                maxQueueSize: 2000,
                flushOnBackground: true,
                enableSampling: false,
                samplingRate: 1.0,
                maxMemoryUsage: 50 * 1024 * 1024 // 50MB
            )
        case .staging:
            return LoggingPerformanceConfiguration(
                asyncLogging: true,
                batchProcessing: true,
                compressionThreshold: 2 * 1024 * 1024, // 2MB
                maxQueueSize: 1500,
                flushOnBackground: true,
                enableSampling: false,
                samplingRate: 1.0,
                maxMemoryUsage: 20 * 1024 * 1024 // 20MB
            )
        case .production:
            return LoggingPerformanceConfiguration(
                asyncLogging: true,
                batchProcessing: true,
                compressionThreshold: 512 * 1024, // 512KB
                maxQueueSize: 500,
                flushOnBackground: true,
                enableSampling: true,
                samplingRate: 0.1, // Log only 10% in production
                maxMemoryUsage: 5 * 1024 * 1024 // 5MB
            )
        }
    }
}

// MARK: - Log Manager
public class LogManager {
    public static let shared = LogManager()
    
    private let configuration: LoggingConfiguration
    private let logger = Logger.shared
    private let crashReporter = CrashReporter.shared
    private var logObservers: [LogObserver] = []
    
    public var isEnabled: Bool {
        get { logger.isEnabled }
        set { logger.setEnabled(newValue) }
    }
    
    public var minimumLogLevel: LogLevel {
        get { configuration.minimumLogLevel }
    }
    
    private init() {
        self.configuration = LoggingConfiguration.current
        setupLogManager()
    }
    
    // MARK: - Public Methods
    
    public func addObserver(_ observer: LogObserver) {
        logObservers.append(observer)
    }
    
    public func removeObserver(_ observer: LogObserver) {
        logObservers.removeAll { $0 === observer }
    }
    
    public func getLogs(filter: LogFilter = LogFilter()) -> [LogEntry] {
        return logger.getLogs(
            category: filter.category,
            level: filter.level,
            since: filter.since,
            limit: filter.limit
        )
    }
    
    public func searchLogs(query: String, filter: LogFilter = LogFilter()) -> [LogEntry] {
        let logs = getLogs(filter: filter)
        
        return logs.filter { log in
            log.message.localizedCaseInsensitiveContains(query) ||
            log.category.rawValue.localizedCaseInsensitiveContains(query) ||
            log.file.localizedCaseInsensitiveContains(query) ||
            log.function.localizedCaseInsensitiveContains(query)
        }
    }
    
    public func getLogsBySession(_ sessionId: String) -> [LogEntry] {
        let allLogs = getLogs(filter: LogFilter(limit: Int.max))
        return allLogs.filter { $0.sessionId == sessionId }
    }
    
    public func getLogStatistics(since: Date? = nil) -> LogStatistics {
        let logs = getLogs(filter: LogFilter(since: since, limit: Int.max))
        
        var categoryStats: [LogCategory: Int] = [:]
        var levelStats: [LogLevel: Int] = [:]
        var errorCount = 0
        var warningCount = 0
        
        for log in logs {
            categoryStats[log.category, default: 0] += 1
            levelStats[log.level, default: 0] += 1
            
            if log.level >= .error {
                errorCount += 1
            } else if log.level == .warning {
                warningCount += 1
            }
        }
        
        return LogStatistics(
            totalLogs: logs.count,
            categoryBreakdown: categoryStats,
            levelBreakdown: levelStats,
            errorCount: errorCount,
            warningCount: warningCount,
            timeRange: (logs.first?.timestamp, logs.last?.timestamp)
        )
    }
    
    public func exportLogs(filter: LogFilter = LogFilter(), format: LogExportFormat = .json) -> Data? {
        let logs = getLogs(filter: filter)
        
        switch format {
        case .json:
            return exportAsJSON(logs)
        case .csv:
            return exportAsCSV(logs)
        case .txt:
            return exportAsText(logs)
        }
    }
    
    public func clearLogs() {
        logger.clearLogs()
        notifyObservers(.logsCleared)
    }
    
    public func flushLogs() {
        logger.flush()
        notifyObservers(.logsFlushed)
    }
    
    public func getStorageInfo() -> LogStorageInfo {
        return logger.logStorage.getStorageInfo()
    }
    
    // MARK: - Log Analysis
    
    public func analyzeLogPatterns(since: Date = Date().addingTimeInterval(-24 * 3600)) -> LogAnalysis {
        let logs = getLogs(filter: LogFilter(since: since, limit: Int.max))
        
        var errorPatterns: [String: Int] = [:]
        var performanceIssues: [String] = []
        var securityEvents: [String] = []
        var frequentMessages: [String: Int] = [:]
        
        for log in logs {
            // Analyze error patterns
            if log.level >= .error {
                let pattern = extractErrorPattern(log.message)
                errorPatterns[pattern, default: 0] += 1
            }
            
            // Detect performance issues
            if log.category == .performance || log.message.contains("memory") || log.message.contains("timeout") {
                performanceIssues.append(log.message)
            }
            
            // Detect security events
            if log.category == .security || log.message.contains("authentication") || log.message.contains("unauthorized") {
                securityEvents.append(log.message)
            }
            
            // Track message frequency
            let messageSignature = extractMessageSignature(log.message)
            frequentMessages[messageSignature, default: 0] += 1
        }
        
        return LogAnalysis(
            analyzedPeriod: (since, Date()),
            totalLogsAnalyzed: logs.count,
            errorPatterns: errorPatterns,
            performanceIssues: performanceIssues,
            securityEvents: securityEvents,
            frequentMessages: frequentMessages.filter { $0.value > 5 }, // Only messages that occur more than 5 times
            recommendations: generateRecommendations(logs)
        )
    }
    
    // MARK: - Private Methods
    
    private func setupLogManager() {
        // Setup application lifecycle monitoring
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if self?.configuration.performance.flushOnBackground == true {
                self?.flushLogs()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushLogs()
        }
    }
    
    private func notifyObservers(_ event: LogEvent) {
        for observer in logObservers {
            observer.logEvent(event)
        }
    }
    
    private func exportAsJSON(_ logs: [LogEntry]) -> Data? {
        let exportData: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
            "logCount": logs.count,
            "logs": logs.map(logEntryToDictionary)
        ]
        
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    private func exportAsCSV(_ logs: [LogEntry]) -> Data? {
        var csvContent = "Timestamp,Level,Category,Message,File,Function,Line,SessionId\n"
        
        for log in logs {
            let timestamp = ISO8601DateFormatter().string(from: log.timestamp)
            let escapedMessage = log.message.replacingOccurrences(of: "\"", with: "\"\"")
            
            csvContent += "\"\(timestamp)\",\"\(log.level.displayName)\",\"\(log.category.rawValue)\",\"\(escapedMessage)\",\"\(log.file)\",\"\(log.function)\",\(log.line),\"\(log.sessionId)\"\n"
        }
        
        return csvContent.data(using: .utf8)
    }
    
    private func exportAsText(_ logs: [LogEntry]) -> Data? {
        var textContent = "Log Export - \(DateFormatter.logTimestamp.string(from: Date()))\n"
        textContent += "=" + String(repeating: "=", count: 50) + "\n\n"
        
        for log in logs {
            let timestamp = DateFormatter.logTimestamp.string(from: log.timestamp)
            textContent += "[\(timestamp)] \(log.level.icon) \(log.level.displayName) [\(log.category.rawValue)]\n"
            textContent += "Message: \(log.message)\n"
            textContent += "Location: \(log.file):\(log.line) in \(log.function)\n"
            textContent += "Session: \(log.sessionId)\n"
            textContent += "-" + String(repeating: "-", count: 50) + "\n\n"
        }
        
        return textContent.data(using: .utf8)
    }
    
    private func logEntryToDictionary(_ log: LogEntry) -> [String: Any] {
        return [
            "id": log.id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: log.timestamp),
            "level": log.level.displayName,
            "category": log.category.rawValue,
            "message": log.message,
            "file": log.file,
            "function": log.function,
            "line": log.line,
            "sessionId": log.sessionId,
            "threadInfo": [
                "isMainThread": log.threadInfo.isMainThread,
                "name": log.threadInfo.name ?? "",
                "queueLabel": log.threadInfo.queueLabel ?? ""
            ],
            "deviceInfo": [
                "deviceModel": log.context.deviceInfo.deviceModel,
                "systemVersion": log.context.deviceInfo.systemVersion,
                "appVersion": log.context.deviceInfo.appVersion
            ]
        ]
    }
    
    private func extractErrorPattern(_ message: String) -> String {
        // Extract error patterns by removing specific values and keeping the structure
        let pattern = message
            .replacingOccurrences(of: "\\d+", with: "{NUMBER}", options: .regularExpression)
            .replacingOccurrences(of: "[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}", with: "{UUID}", options: .regularExpression)
            .replacingOccurrences(of: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b", with: "{EMAIL}", options: .regularExpression)
        
        return String(pattern.prefix(100)) // Limit pattern length
    }
    
    private func extractMessageSignature(_ message: String) -> String {
        // Create a signature by removing variable parts
        return extractErrorPattern(message)
    }
    
    private func generateRecommendations(_ logs: [LogEntry]) -> [String] {
        var recommendations: [String] = []
        
        let errorLogs = logs.filter { $0.level >= .error }
        let warningLogs = logs.filter { $0.level == .warning }
        
        // High error rate
        if errorLogs.count > logs.count / 10 {
            recommendations.append("High error rate detected (\(errorLogs.count)/\(logs.count)). Review error handling.")
        }
        
        // High warning rate
        if warningLogs.count > logs.count / 5 {
            recommendations.append("High warning rate detected. Consider addressing warning conditions.")
        }
        
        // Frequent network errors
        let networkErrors = logs.filter { $0.category == .network && $0.level >= .error }
        if networkErrors.count > 10 {
            recommendations.append("Frequent network errors detected. Check network error handling and retry logic.")
        }
        
        // Memory warnings
        let memoryLogs = logs.filter { $0.message.contains("memory") || $0.category == .performance }
        if memoryLogs.count > 5 {
            recommendations.append("Memory-related issues detected. Consider optimizing memory usage.")
        }
        
        return recommendations
    }
}

// MARK: - Supporting Types

public struct LogFilter {
    let category: LogCategory?
    let level: LogLevel?
    let since: Date?
    let until: Date?
    let limit: Int
    let sessionId: String?
    
    init(category: LogCategory? = nil,
         level: LogLevel? = nil,
         since: Date? = nil,
         until: Date? = nil,
         limit: Int = 100,
         sessionId: String? = nil) {
        self.category = category
        self.level = level
        self.since = since
        self.until = until
        self.limit = limit
        self.sessionId = sessionId
    }
}

public enum LogExportFormat {
    case json
    case csv
    case txt
}

public struct LogStatistics {
    let totalLogs: Int
    let categoryBreakdown: [LogCategory: Int]
    let levelBreakdown: [LogLevel: Int]
    let errorCount: Int
    let warningCount: Int
    let timeRange: (first: Date?, last: Date?)
}

public struct LogAnalysis {
    let analyzedPeriod: (start: Date, end: Date)
    let totalLogsAnalyzed: Int
    let errorPatterns: [String: Int]
    let performanceIssues: [String]
    let securityEvents: [String]
    let frequentMessages: [String: Int]
    let recommendations: [String]
}

public enum LogEvent {
    case logAdded(LogEntry)
    case logsCleared
    case logsFlushed
    case storageRotated
    case errorThresholdReached
}

public protocol LogObserver: AnyObject {
    func logEvent(_ event: LogEvent)
}

// MARK: - Performance Monitor
public class LoggingPerformanceMonitor {
    private let configuration: LoggingPerformanceConfiguration
    private var currentMemoryUsage: Int = 0
    private var logQueue: [LogEntry] = []
    private var lastFlushTime: Date = Date()
    
    init(configuration: LoggingPerformanceConfiguration) {
        self.configuration = configuration
        startMonitoring()
    }
    
    private func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkPerformance()
        }
    }
    
    private func checkPerformance() {
        // Monitor memory usage
        if currentMemoryUsage > configuration.maxMemoryUsage {
            // Force flush to reduce memory usage
            Logger.shared.flush()
        }
        
        // Check if sampling should be enabled
        if configuration.enableSampling && Double.random(in: 0...1) > configuration.samplingRate {
            // Skip logging based on sampling rate
        }
        
        // Check queue size
        if logQueue.count > configuration.maxQueueSize {
            // Drop oldest logs
            logQueue.removeFirst(logQueue.count - configuration.maxQueueSize)
        }
    }
}

// MARK: - Extensions
extension Logger {
    var logStorage: LogStorage {
        // This would need to be exposed from the Logger implementation
        return LogStorage(configuration: LogStorageConfiguration.current)
    }
    
    var isEnabled: Bool {
        // This would need to be exposed from the Logger implementation
        return true
    }
    
    func setEnabled(_ enabled: Bool) {
        // This would need to be implemented in the Logger
    }
    
    func flush() {
        // This would need to be implemented in the Logger to flush pending logs
    }
}