import Foundation
import Combine

/// Protocol defining logging system capabilities
protocol LoggingSystemProtocol: AnyObject {
    // MARK: - Initialization
    func initialize() async throws
    
    // MARK: - Logging Methods
    func logDebug(_ message: String, category: LogCategory, context: LogContext?)
    func logInfo(_ message: String, category: LogCategory, context: LogContext?)
    func logWarning(_ message: String, category: LogCategory, context: LogContext?)
    func logError(_ message: String, category: LogCategory, context: LogContext?)
    func logCritical(_ message: String, category: LogCategory, context: LogContext?)
    
    // MARK: - Log Retrieval
    func getLogs(for category: LogCategory?, level: LogLevel?, limit: Int?) -> [LogEntry]
    func getRecentLogs(count: Int) -> [LogEntry]
    func searchLogs(query: String) -> [LogEntry]
    
    // MARK: - Configuration
    func setLogLevel(_ level: LogLevel)
    func enableCategory(_ category: LogCategory)
    func disableCategory(_ category: LogCategory)
    
    // MARK: - Export
    func exportLogs() async throws -> Data
    func clearLogs() async throws
}

// MARK: - Supporting Types
enum LogLevel: Int, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4
    
    var displayName: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}

enum LogCategory: String, CaseIterable {
    case general = "general"
    case ar = "ar"
    case network = "network"
    case ui = "ui"
    case performance = "performance"
    case storage = "storage"
    case analytics = "analytics"
    case security = "security"
    
    var displayName: String {
        return rawValue.capitalized
    }
}

struct LogContext {
    let timestamp: Date
    let threadID: String
    let fileName: String
    let functionName: String
    let lineNumber: Int
    let customData: [String: Any]
    
    init(
        timestamp: Date = Date(),
        threadID: String = Thread.current.description,
        fileName: String = #file,
        functionName: String = #function,
        lineNumber: Int = #line,
        customData: [String: Any] = [:]
    ) {
        self.timestamp = timestamp
        self.threadID = threadID
        self.fileName = (fileName as NSString).lastPathComponent
        self.functionName = functionName
        self.lineNumber = lineNumber
        self.customData = customData
    }
}

struct LogEntry {
    let id: UUID
    let level: LogLevel
    let category: LogCategory
    let message: String
    let context: LogContext
    
    init(
        id: UUID = UUID(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        context: LogContext
    ) {
        self.id = id
        self.level = level
        self.category = category
        self.message = message
        self.context = context
    }
}

// MARK: - Convenience Logging Functions
func logDebug(_ message: String, category: LogCategory = .general, context: LogContext? = nil) {
    LoggingSystem.shared.logDebug(message, category: category, context: context ?? LogContext())
}

func logInfo(_ message: String, category: LogCategory = .general, context: LogContext? = nil) {
    LoggingSystem.shared.logInfo(message, category: category, context: context ?? LogContext())
}

func logWarning(_ message: String, category: LogCategory = .general, context: LogContext? = nil) {
    LoggingSystem.shared.logWarning(message, category: category, context: context ?? LogContext())
}

func logError(_ message: String, category: LogCategory = .general, context: LogContext? = nil) {
    LoggingSystem.shared.logError(message, category: category, context: context ?? LogContext())
}

func logCritical(_ message: String, category: LogCategory = .general, context: LogContext? = nil) {
    LoggingSystem.shared.logCritical(message, category: category, context: context ?? LogContext())
}