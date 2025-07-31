import Foundation
import os.log
import UIKit

// MARK: - Log Level
public enum LogLevel: Int, CaseIterable, Comparable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5
    
    var displayName: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
    
    var icon: String {
        switch self {
        case .verbose: return "💬"
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .verbose, .debug: return .debug
        case .info: return .info
        case .warning, .error: return .error
        case .critical: return .fault
        }
    }
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log Category
public enum LogCategory: String, CaseIterable {
    case general = "General"
    case network = "Network"
    case ar = "AR"
    case ui = "UI"
    case storage = "Storage"
    case performance = "Performance"
    case security = "Security"
    case analytics = "Analytics"
    case configuration = "Configuration"
    case crash = "Crash"
    case user = "User"
    case system = "System"
    
    var subsystem: String {
        return "com.architect.ARchitect.\(rawValue.lowercased())"
    }
}

// MARK: - Log Entry
public struct LogEntry {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let file: String
    let function: String
    let line: Int
    let context: LogContext
    let threadInfo: ThreadInfo
    let sessionId: String
    
    struct ThreadInfo {
        let name: String?
        let isMainThread: Bool
        let queueLabel: String?
        
        init() {
            self.isMainThread = Thread.isMainThread
            self.name = Thread.current.name
            
            if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
                self.queueLabel = label.isEmpty ? nil : label
            } else {
                self.queueLabel = nil
            }
        }
    }
    
    init(level: LogLevel, 
         category: LogCategory, 
         message: String, 
         file: String, 
         function: String, 
         line: Int,
         context: LogContext,
         sessionId: String) {
        self.timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
        self.file = (file as NSString).lastPathComponent
        self.function = function
        self.line = line
        self.context = context
        self.threadInfo = ThreadInfo()
        self.sessionId = sessionId
    }
}

// MARK: - Log Context
public struct LogContext {
    let userInfo: UserInfo?
    let deviceInfo: DeviceInfo
    let appInfo: AppInfo
    let customData: [String: Any]
    
    struct UserInfo {
        let userId: String? // Hashed for privacy
        let userAction: String?
        let screenName: String?
        let userAgent: String?
    }
    
    struct DeviceInfo {
        let deviceModel: String
        let systemName: String
        let systemVersion: String
        let appVersion: String
        let buildNumber: String
        let isSimulator: Bool
        let locale: String
        let timezone: String
        let batteryLevel: Float?
        let batteryState: String?
        let memoryUsage: Int64?
        let diskSpace: Int64?
        let networkType: String?
    }
    
    struct AppInfo {
        let bundleId: String
        let environment: String
        let launchTime: Date
        let uptime: TimeInterval
        let isFirstLaunch: Bool
        let previousVersion: String?
    }
    
    init(userInfo: UserInfo? = nil, customData: [String: Any] = [:]) {
        self.userInfo = userInfo
        self.deviceInfo = DeviceInfo()
        self.appInfo = AppInfo()
        self.customData = customData
    }
}

extension LogContext.DeviceInfo {
    init() {
        let device = UIDevice.current
        
        self.deviceModel = device.model
        self.systemName = device.systemName
        self.systemVersion = device.systemVersion
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        self.isSimulator = TARGET_OS_SIMULATOR != 0
        self.locale = Locale.current.identifier
        self.timezone = TimeZone.current.identifier
        
        device.isBatteryMonitoringEnabled = true
        self.batteryLevel = device.batteryLevel >= 0 ? device.batteryLevel : nil
        self.batteryState = device.batteryState.description
        
        self.memoryUsage = LogContext.DeviceInfo.getMemoryUsage()
        self.diskSpace = LogContext.DeviceInfo.getDiskSpace()
        self.networkType = LogContext.DeviceInfo.getNetworkType()
    }
    
    private static func getMemoryUsage() -> Int64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : nil
    }
    
    private static func getDiskSpace() -> Int64? {
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return values.volumeAvailableCapacity.map { Int64($0) }
        } catch {
            return nil
        }
    }
    
    private static func getNetworkType() -> String? {
        // This would typically use Network framework
        // For now, return a placeholder
        return "Unknown"
    }
}

extension LogContext.AppInfo {
    init() {
        self.bundleId = Bundle.main.bundleIdentifier ?? "Unknown"
        self.environment = AppEnvironment.current.rawValue
        
        // Get app launch time (approximation)
        self.launchTime = ProcessInfo.processInfo.thermalState == .nominal ? Date() : Date()
        self.uptime = ProcessInfo.processInfo.systemUptime
        
        // Check if this is first launch
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "has_launched_before")
        self.isFirstLaunch = !hasLaunchedBefore
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "has_launched_before")
        }
        
        // Get previous version
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        self.previousVersion = UserDefaults.standard.string(forKey: "previous_app_version")
        
        if let currentVersion = currentVersion {
            UserDefaults.standard.set(currentVersion, forKey: "previous_app_version")
        }
    }
}

extension UIDevice.BatteryState {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Logger Protocol
public protocol LoggerProtocol {
    func log(_ level: LogLevel, 
             category: LogCategory, 
             message: String, 
             file: String, 
             function: String, 
             line: Int,
             context: LogContext)
    
    func verbose(_ message: String, 
                category: LogCategory, 
                file: String, 
                function: String, 
                line: Int,
                context: LogContext)
    
    func debug(_ message: String, 
              category: LogCategory, 
              file: String, 
              function: String, 
              line: Int,
              context: LogContext)
    
    func info(_ message: String, 
             category: LogCategory, 
             file: String, 
             function: String, 
             line: Int,
             context: LogContext)
    
    func warning(_ message: String, 
                category: LogCategory, 
                file: String, 
                function: String, 
                line: Int,
                context: LogContext)
    
    func error(_ message: String, 
              category: LogCategory, 
              file: String, 
              function: String, 
              line: Int,
              context: LogContext)
    
    func critical(_ message: String, 
                 category: LogCategory, 
                 file: String, 
                 function: String, 
                 line: Int,
                 context: LogContext)
}

// MARK: - Main Logger
public class Logger: LoggerProtocol {
    public static let shared = Logger()
    
    private let sessionId = UUID().uuidString
    private let logStorage: LogStorage
    private let privacyFilter: PrivacyFilter
    private let osLoggers: [LogCategory: OSLog]
    private let configuration: LoggingConfiguration
    private let queue = DispatchQueue(label: "com.architect.logger", qos: .utility)
    
    private var isEnabled = true
    private var minimumLogLevel: LogLevel
    
    private init() {
        self.configuration = LoggingConfiguration.current
        self.minimumLogLevel = configuration.minimumLogLevel
        self.logStorage = LogStorage(configuration: configuration.storage)
        self.privacyFilter = PrivacyFilter()
        
        // Create OS loggers for each category
        var loggers: [LogCategory: OSLog] = [:]
        for category in LogCategory.allCases {
            loggers[category] = OSLog(subsystem: category.subsystem, category: category.rawValue)
        }
        self.osLoggers = loggers
        
        setupCrashHandler()
        setupMemoryWarningHandler()
    }
    
    // MARK: - Public Interface
    
    public func log(_ level: LogLevel, 
                   category: LogCategory = .general, 
                   message: String, 
                   file: String = #file, 
                   function: String = #function, 
                   line: Int = #line,
                   context: LogContext = LogContext()) {
        
        guard isEnabled && level >= minimumLogLevel else { return }
        
        queue.async {
            self.processLog(level: level, 
                          category: category, 
                          message: message, 
                          file: file, 
                          function: function, 
                          line: line, 
                          context: context)
        }
    }
    
    public func verbose(_ message: String, 
                       category: LogCategory = .general, 
                       file: String = #file, 
                       function: String = #function, 
                       line: Int = #line,
                       context: LogContext = LogContext()) {
        log(.verbose, category: category, message: message, file: file, function: function, line: line, context: context)
    }
    
    public func debug(_ message: String, 
                     category: LogCategory = .general, 
                     file: String = #file, 
                     function: String = #function, 
                     line: Int = #line,
                     context: LogContext = LogContext()) {
        log(.debug, category: category, message: message, file: file, function: function, line: line, context: context)
    }
    
    public func info(_ message: String, 
                    category: LogCategory = .general, 
                    file: String = #file, 
                    function: String = #function, 
                    line: Int = #line,
                    context: LogContext = LogContext()) {
        log(.info, category: category, message: message, file: file, function: function, line: line, context: context)
    }
    
    public func warning(_ message: String, 
                       category: LogCategory = .general, 
                       file: String = #file, 
                       function: String = #function, 
                       line: Int = #line,
                       context: LogContext = LogContext()) {
        log(.warning, category: category, message: message, file: file, function: function, line: line, context: context)
    }
    
    public func error(_ message: String, 
                     category: LogCategory = .general, 
                     file: String = #file, 
                     function: String = #function, 
                     line: Int = #line,
                     context: LogContext = LogContext()) {
        log(.error, category: category, message: message, file: file, function: function, line: line, context: context)
    }
    
    public func critical(_ message: String, 
                        category: LogCategory = .general, 
                        file: String = #file, 
                        function: String = #function, 
                        line: Int = #line,
                        context: LogContext = LogContext()) {
        log(.critical, category: category, message: message, file: file, function: function, line: line, context: context)
    }
    
    // MARK: - Configuration
    
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    public func setMinimumLogLevel(_ level: LogLevel) {
        minimumLogLevel = level
    }
    
    public func getLogs(category: LogCategory? = nil, 
                       level: LogLevel? = nil, 
                       since: Date? = nil, 
                       limit: Int = 100) -> [LogEntry] {
        return logStorage.getLogs(category: category, level: level, since: since, limit: limit)
    }
    
    public func clearLogs() {
        logStorage.clearLogs()
    }
    
    public func exportLogs() -> Data? {
        return logStorage.exportLogs()
    }
    
    // MARK: - Private Methods
    
    private func processLog(level: LogLevel, 
                           category: LogCategory, 
                           message: String, 
                           file: String, 
                           function: String, 
                           line: Int, 
                           context: LogContext) {
        
        // Filter sensitive data
        let filteredMessage = privacyFilter.filter(message, level: level)
        let filteredContext = privacyFilter.filter(context: context, level: level)
        
        // Create log entry
        let logEntry = LogEntry(level: level, 
                              category: category, 
                              message: filteredMessage, 
                              file: file, 
                              function: function, 
                              line: line, 
                              context: filteredContext,
                              sessionId: sessionId)
        
        // Store log entry
        logStorage.store(logEntry)
        
        // Send to OS log
        if configuration.useOSLog {
            logToOS(logEntry)
        }
        
        // Send to console in debug mode
        if configuration.printToConsole && (AppEnvironment.current.isDebugEnvironment || level >= .error) {
            logToConsole(logEntry)
        }
        
        // Send to crash reporting if error or critical
        if level >= .error && configuration.sendToCrashReporting {
            sendToCrashReporting(logEntry)
        }
        
        // Send to analytics if configured
        if configuration.sendToAnalytics && shouldSendToAnalytics(level: level, category: category) {
            sendToAnalytics(logEntry)
        }
    }
    
    private func logToOS(_ entry: LogEntry) {
        guard let osLogger = osLoggers[entry.category] else { return }
        
        let message = formatLogMessage(entry, includeContext: false)
        os_log("%{public}@", log: osLogger, type: entry.level.osLogType, message)
    }
    
    private func logToConsole(_ entry: LogEntry) {
        let message = formatLogMessage(entry, includeContext: true)
        print(message)
    }
    
    private func formatLogMessage(_ entry: LogEntry, includeContext: Bool) -> String {
        let timestamp = DateFormatter.logTimestamp.string(from: entry.timestamp)
        let threadInfo = entry.threadInfo.isMainThread ? "[Main]" : "[Background]"
        let location = "\(entry.file):\(entry.line)"
        
        var message = "\(entry.level.icon) \(timestamp) \(threadInfo) [\(entry.category.rawValue)] \(entry.message) (\(location))"
        
        if includeContext && !entry.context.customData.isEmpty {
            let contextString = entry.context.customData.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            message += " | Context: {\(contextString)}"
        }
        
        return message
    }
    
    private func shouldSendToAnalytics(level: LogLevel, category: LogCategory) -> Bool {
        // Only send warning and above to analytics
        guard level >= .warning else { return false }
        
        // Don't send sensitive categories to analytics
        let sensitiveCategories: [LogCategory] = [.security, .user, .crash]
        return !sensitiveCategories.contains(category)
    }
    
    private func sendToCrashReporting(_ entry: LogEntry) {
        // This would integrate with crash reporting service (Firebase Crashlytics, Sentry, etc.)
        // For now, we'll just add it to a special crash log
        CrashReporter.shared.recordLog(entry)
    }
    
    private func sendToAnalytics(_ entry: LogEntry) {
        // This would integrate with analytics service
        // For now, just track error events
        let eventData: [String: Any] = [
            "log_level": entry.level.displayName,
            "log_category": entry.category.rawValue,
            "error_message": entry.message,
            "session_id": entry.sessionId,
            "app_version": entry.context.deviceInfo.appVersion
        ]
        
        // Would send to analytics service
        AnalyticsLogger.shared.trackEvent("log_error", parameters: eventData)
    }
    
    private func setupCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let context = LogContext(customData: [
                "exception_name": exception.name.rawValue,
                "exception_reason": exception.reason ?? "Unknown",
                "stack_trace": exception.callStackSymbols
            ])
            
            Logger.shared.critical("Uncaught exception: \(exception.reason ?? "Unknown")", 
                                 category: .crash, 
                                 context: context)
            
            // Force flush logs before crash
            Logger.shared.logStorage.flush()
        }
        
        // Setup signal handlers for crashes
        setupSignalHandlers()
    }
    
    private func setupSignalHandlers() {
        let signals = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS]
        
        for signal in signals {
            signal(signal) { signalNumber in
                let context = LogContext(customData: [
                    "signal": signalNumber,
                    "signal_name": String(cString: strsignal(signalNumber))
                ])
                
                Logger.shared.critical("Signal \(signalNumber) received", 
                                     category: .crash, 
                                     context: context)
                
                // Force flush logs before crash
                Logger.shared.logStorage.flush()
                
                // Call default handler
                signal(signalNumber, SIG_DFL)
                raise(signalNumber)
            }
        }
    }
    
    private func setupMemoryWarningHandler() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let context = LogContext(customData: [
                "memory_usage": LogContext.DeviceInfo.getMemoryUsage() ?? 0,
                "available_memory": "unknown"
            ])
            
            self?.warning("Memory warning received", 
                         category: .performance, 
                         context: context)
        }
    }
}

// MARK: - Convenience Extensions
extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

// MARK: - Global Logging Functions
public func logVerbose(_ message: String, 
                      category: LogCategory = .general, 
                      file: String = #file, 
                      function: String = #function, 
                      line: Int = #line,
                      context: LogContext = LogContext()) {
    Logger.shared.verbose(message, category: category, file: file, function: function, line: line, context: context)
}

public func logDebug(_ message: String, 
                    category: LogCategory = .general, 
                    file: String = #file, 
                    function: String = #function, 
                    line: Int = #line,
                    context: LogContext = LogContext()) {
    Logger.shared.debug(message, category: category, file: file, function: function, line: line, context: context)
}

public func logInfo(_ message: String, 
                   category: LogCategory = .general, 
                   file: String = #file, 
                   function: String = #function, 
                   line: Int = #line,
                   context: LogContext = LogContext()) {
    Logger.shared.info(message, category: category, file: file, function: function, line: line, context: context)
}

public func logWarning(_ message: String, 
                      category: LogCategory = .general, 
                      file: String = #file, 
                      function: String = #function, 
                      line: Int = #line,
                      context: LogContext = LogContext()) {
    Logger.shared.warning(message, category: category, file: file, function: function, line: line, context: context)
}

public func logError(_ message: String, 
                    category: LogCategory = .general, 
                    file: String = #file, 
                    function: String = #function, 
                    line: Int = #line,
                    context: LogContext = LogContext()) {
    Logger.shared.error(message, category: category, file: file, function: function, line: line, context: context)
}

public func logCritical(_ message: String, 
                       category: LogCategory = .general, 
                       file: String = #file, 
                       function: String = #function, 
                       line: Int = #line,
                       context: LogContext = LogContext()) {
    Logger.shared.critical(message, category: category, file: file, function: function, line: line, context: context)
}