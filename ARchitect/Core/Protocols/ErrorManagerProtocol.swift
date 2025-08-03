import Foundation
import Combine

/// Protocol defining error management capabilities
protocol ErrorManagerProtocol: AnyObject {
    // MARK: - Properties
    var currentError: Error? { get }
    var errorPublisher: AnyPublisher<Error?, Never> { get }
    
    // MARK: - Error Reporting
    func reportError(_ error: Error)
    func reportError(_ error: Error, context: ErrorContext)
    func reportCriticalError(_ error: Error, context: ErrorContext)
    
    // MARK: - Error Recovery
    func clearError()
    func clearAllErrors()
    func retryLastOperation() async throws
    
    // MARK: - Error Handling Strategy
    func setErrorHandler(_ handler: @escaping ErrorHandler)
    func setRecoveryStrategy(_ strategy: @escaping RecoveryStrategy)
    
    // MARK: - Error Analytics
    func getErrorStatistics() -> ErrorStatistics
    func getErrorHistory() -> [ErrorRecord]
}

// MARK: - Supporting Types
typealias ErrorHandler = (Error, ErrorContext) -> Void
typealias RecoveryStrategy = (Error) async throws -> Void

struct ErrorContext {
    let timestamp: Date
    let userID: String?
    let sessionID: String
    let feature: String?
    let customData: [String: Any]
    
    init(
        timestamp: Date = Date(),
        userID: String? = nil,
        sessionID: String = UUID().uuidString,
        feature: String? = nil,
        customData: [String: Any] = [:]
    ) {
        self.timestamp = timestamp
        self.userID = userID
        self.sessionID = sessionID
        self.feature = feature
        self.customData = customData
    }
}

struct ErrorRecord {
    let error: Error
    let context: ErrorContext
    let severity: ErrorSeverity
    let isResolved: Bool
    
    init(error: Error, context: ErrorContext, severity: ErrorSeverity = .medium, isResolved: Bool = false) {
        self.error = error
        self.context = context
        self.severity = severity
        self.isResolved = isResolved
    }
}

enum ErrorSeverity: Int, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

struct ErrorStatistics {
    let totalErrors: Int
    let errorsByCategory: [String: Int]
    let errorsBySeverity: [ErrorSeverity: Int]
    let averageResolutionTime: TimeInterval
    let mostCommonErrors: [String]
}

// MARK: - Common Error Types
enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case invalidResponse
    case serverError(Int)
    case invalidURL
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .noConnection: return "No internet connection available"
        case .timeout: return "Request timed out"
        case .invalidResponse: return "Invalid server response"
        case .serverError(let code): return "Server error (Code: \(code))"
        case .invalidURL: return "Invalid URL"
        case .decodingError: return "Failed to decode response"
        }
    }
}

enum ARError: LocalizedError {
    case trackingLost
    case sessionFailed
    case configurationNotSupported
    case planeDetectionFailed
    case anchorPlacementFailed
    case modelLoadingFailed
    
    var errorDescription: String? {
        switch self {
        case .trackingLost: return "AR tracking was lost"
        case .sessionFailed: return "AR session failed to start"
        case .configurationNotSupported: return "AR configuration not supported"
        case .planeDetectionFailed: return "Failed to detect planes"
        case .anchorPlacementFailed: return "Failed to place anchor"
        case .modelLoadingFailed: return "Failed to load 3D model"
        }
    }
}