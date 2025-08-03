import Foundation
import Combine
import os.log

/// Implementation of LoggingSystemProtocol
final class LoggingSystemImpl: LoggingSystemProtocol {
    // MARK: - Properties
    private var isInitialized = false
    private var currentLogLevel: LogLevel = .info
    private var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)
    private var logEntries: [LogEntry] = []
    private let maxLogEntries = 1000
    private let logQueue = DispatchQueue(label: "com.architect.logging", qos: .utility)
    
    // OS Logger instances for each category
    private lazy var osLoggers: [LogCategory: OSLog] = {
        var loggers: [LogCategory: OSLog] = [:]
        for category in LogCategory.allCases {
            loggers[category] = OSLog(subsystem: "com.architect.app", category: category.rawValue)
        }
        return loggers
    }()
    
    // MARK: - Initialization
    func initialize() async throws {
        guard !isInitialized else { return }
        
        logQueue.async {
            self.isInitialized = true
            
            // Initialize with info level and all categories enabled
            self.currentLogLevel = .info
            self.enabledCategories = Set(LogCategory.allCases)
            
            // Log initialization
            self.logInfo("Logging system initialized", category: .general, context: LogContext())
        }
    }
    
    // MARK: - Logging Methods
    func logDebug(_ message: String, category: LogCategory, context: LogContext? = nil) {
        log(message, level: .debug, category: category, context: context ?? LogContext())
    }
    
    func logInfo(_ message: String, category: LogCategory, context: LogContext? = nil) {
        log(message, level: .info, category: category, context: context ?? LogContext())
    }
    
    func logWarning(_ message: String, category: LogCategory, context: LogContext? = nil) {
        log(message, level: .warning, category: category, context: context ?? LogContext())
    }
    
    func logError(_ message: String, category: LogCategory, context: LogContext? = nil) {
        log(message, level: .error, category: category, context: context ?? LogContext())
    }
    
    func logCritical(_ message: String, category: LogCategory, context: LogContext? = nil) {
        log(message, level: .critical, category: category, context: context ?? LogContext())
    }
    
    // MARK: - Log Retrieval
    func getLogs(for category: LogCategory? = nil, level: LogLevel? = nil, limit: Int? = nil) -> [LogEntry] {
        return logQueue.sync {
            var filteredLogs = logEntries
            
            if let category = category {
                filteredLogs = filteredLogs.filter { $0.category == category }
            }
            
            if let level = level {
                filteredLogs = filteredLogs.filter { $0.level.rawValue >= level.rawValue }
            }
            
            if let limit = limit {
                filteredLogs = Array(filteredLogs.suffix(limit))
            }
            
            return filteredLogs
        }
    }
    
    func getRecentLogs(count: Int) -> [LogEntry] {
        return logQueue.sync {
            return Array(logEntries.suffix(count))
        }
    }
    
    func searchLogs(query: String) -> [LogEntry] {
        return logQueue.sync {
            return logEntries.filter { entry in
                entry.message.localizedCaseInsensitiveContains(query) ||
                entry.context.fileName.localizedCaseInsensitiveContains(query) ||
                entry.context.functionName.localizedCaseInsensitiveContains(query)
            }
        }
    }
    
    // MARK: - Configuration
    func setLogLevel(_ level: LogLevel) {
        logQueue.async {
            self.currentLogLevel = level
        }
    }
    
    func enableCategory(_ category: LogCategory) {
        logQueue.async {
            self.enabledCategories.insert(category)
        }
    }
    
    func disableCategory(_ category: LogCategory) {
        logQueue.async {
            self.enabledCategories.remove(category)
        }
    }
    
    // MARK: - Export
    func exportLogs() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            logQueue.async {
                do {
                    let exportData = try self.createLogExport()
                    continuation.resume(returning: exportData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func clearLogs() async throws {
        return await withCheckedContinuation { continuation in
            logQueue.async {
                self.logEntries.removeAll()
                continuation.resume()
            }
        }
    }
    
    // MARK: - Private Methods
    private func log(_ message: String, level: LogLevel, category: LogCategory, context: LogContext) {
        guard isInitialized else { return }
        guard level.rawValue >= currentLogLevel.rawValue else { return }
        guard enabledCategories.contains(category) else { return }
        
        logQueue.async {
            // Create log entry
            let entry = LogEntry(
                level: level,
                category: category,
                message: message,
                context: context
            )
            
            // Add to internal storage
            self.addLogEntry(entry)
            
            // Log to OS Logger
            self.logToOSLogger(entry)
            
            // Log to console in debug builds
            #if DEBUG
            self.logToConsole(entry)
            #endif
        }
    }
    
    private func addLogEntry(_ entry: LogEntry) {
        logEntries.append(entry)
        
        // Keep log entries manageable
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst()
        }
    }
    
    private func logToOSLogger(_ entry: LogEntry) {
        guard let osLogger = osLoggers[entry.category] else { return }
        
        let formattedMessage = formatLogMessage(entry)
        
        switch entry.level {
        case .debug:
            os_log(.debug, log: osLogger, "%{public}@", formattedMessage)
        case .info:
            os_log(.info, log: osLogger, "%{public}@", formattedMessage)
        case .warning:
            os_log(.default, log: osLogger, "⚠️ %{public}@", formattedMessage)
        case .error:
            os_log(.error, log: osLogger, "❌ %{public}@", formattedMessage)
        case .critical:
            os_log(.fault, log: osLogger, "🚨 %{public}@", formattedMessage)
        }
    }
    
    private func logToConsole(_ entry: LogEntry) {
        let formattedMessage = formatLogMessage(entry)
        print("[\(entry.level.emoji) \(entry.level.displayName)] [\(entry.category.displayName)] \(formattedMessage)")
    }
    
    private func formatLogMessage(_ entry: LogEntry) -> String {
        let timestamp = DateFormatter.logTimestamp.string(from: entry.context.timestamp)
        let location = "\(entry.context.fileName):\(entry.context.lineNumber)"
        return "\(timestamp) [\(location)] \(entry.message)"
    }
    
    private func createLogExport() throws -> Data {
        let exportData: [String: Any] = [
            "export_timestamp": Date().timeIntervalSince1970,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
            "logs": logEntries.map { entry in
                [
                    "id": entry.id.uuidString,
                    "timestamp": entry.context.timestamp.timeIntervalSince1970,
                    "level": entry.level.displayName,
                    "category": entry.category.displayName,
                    "message": entry.message,
                    "file": entry.context.fileName,
                    "function": entry.context.functionName,
                    "line": entry.context.lineNumber,
                    "thread": entry.context.threadID,
                    "custom_data": entry.context.customData
                ]
            }
        ]
        
        return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
}

// MARK: - DateFormatter Extension
private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}