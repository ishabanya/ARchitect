import Foundation
import Combine

/// Implementation of ErrorManagerProtocol
final class ErrorManagerImpl: ErrorManagerProtocol {
    // MARK: - Published Properties
    @Published private(set) var currentError: Error?
    
    var errorPublisher: AnyPublisher<Error?, Never> {
        $currentError.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    private var errorHistory: [ErrorRecord] = []
    private var errorHandler: ErrorHandler?
    private var recoveryStrategy: RecoveryStrategy?
    private let maxHistorySize = 50
    private var lastOperation: (() async throws -> Void)?
    
    // MARK: - Error Reporting
    func reportError(_ error: Error) {
        reportError(error, context: ErrorContext())
    }
    
    func reportError(_ error: Error, context: ErrorContext) {
        currentError = error
        
        let severity = determineSeverity(for: error)
        let record = ErrorRecord(error: error, context: context, severity: severity)
        
        addToHistory(record)
        
        // Call error handler if set
        errorHandler?(error, context)
        
        // Log the error
        logError("Error reported: \(error.localizedDescription)", category: .general, context: LogContext(customData: [
            "error_type": String(describing: type(of: error)),
            "severity": severity.displayName,
            "user_id": context.userID ?? "unknown",
            "feature": context.feature ?? "unknown"
        ]))
        
        // Track in analytics if available
        if let analyticsManager = DIContainer.shared.tryResolve(AnalyticsManagerProtocol.self) {
            analyticsManager.trackError(error, context: [
                "severity": severity.displayName,
                "feature": context.feature ?? "unknown"
            ])
        }
    }
    
    func reportCriticalError(_ error: Error, context: ErrorContext) {
        let criticalRecord = ErrorRecord(error: error, context: context, severity: .critical)
        addToHistory(criticalRecord)
        
        reportError(error, context: context)
        
        logCritical("Critical error reported: \(error.localizedDescription)", category: .general, context: LogContext(customData: [
            "error_type": String(describing: type(of: error)),
            "user_id": context.userID ?? "unknown",
            "feature": context.feature ?? "unknown"
        ]))
    }
    
    // MARK: - Error Recovery
    func clearError() {
        currentError = nil
    }
    
    func clearAllErrors() {
        currentError = nil
        errorHistory.removeAll()
    }
    
    func retryLastOperation() async throws {
        guard let operation = lastOperation else {
            throw ErrorManagerError.noOperationToRetry
        }
        
        try await operation()
    }
    
    // MARK: - Error Handling Strategy
    func setErrorHandler(_ handler: @escaping ErrorHandler) {
        self.errorHandler = handler
    }
    
    func setRecoveryStrategy(_ strategy: @escaping RecoveryStrategy) {
        self.recoveryStrategy = strategy
    }
    
    // MARK: - Error Analytics
    func getErrorStatistics() -> ErrorStatistics {
        let totalErrors = errorHistory.count
        
        var errorsByCategory: [String: Int] = [:]
        var errorsBySeverity: [ErrorSeverity: Int] = [:]
        var resolutionTimes: [TimeInterval] = []
        var errorTypes: [String: Int] = [:]
        
        for record in errorHistory {
            let errorType = String(describing: type(of: record.error))
            errorsByCategory[record.context.feature ?? "unknown", default: 0] += 1
            errorsBySeverity[record.severity, default: 0] += 1
            errorTypes[errorType, default: 0] += 1
            
            if record.isResolved {
                // Calculate resolution time (simplified)
                resolutionTimes.append(60.0) // Placeholder
            }
        }
        
        let averageResolutionTime = resolutionTimes.isEmpty ? 0 : resolutionTimes.reduce(0, +) / Double(resolutionTimes.count)
        let mostCommonErrors = errorTypes.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
        
        return ErrorStatistics(
            totalErrors: totalErrors,
            errorsByCategory: errorsByCategory,
            errorsBySeverity: errorsBySeverity,
            averageResolutionTime: averageResolutionTime,
            mostCommonErrors: Array(mostCommonErrors)
        )
    }
    
    func getErrorHistory() -> [ErrorRecord] {
        return errorHistory
    }
    
    // MARK: - Private Methods
    private func addToHistory(_ record: ErrorRecord) {
        errorHistory.append(record)
        
        // Keep history size manageable
        if errorHistory.count > maxHistorySize {
            errorHistory.removeFirst()
        }
    }
    
    private func determineSeverity(for error: Error) -> ErrorSeverity {
        switch error {
        case is NetworkError:
            return .medium
        case is ARError:
            return .high
        case let nsError as NSError:
            switch nsError.domain {
            case NSCocoaErrorDomain:
                return .low
            case NSURLErrorDomain:
                return .medium
            default:
                return .medium
            }
        default:
            return .medium
        }
    }
    
    func storeLastOperation(_ operation: @escaping () async throws -> Void) {
        lastOperation = operation
    }
}

// MARK: - Error Manager Specific Errors
enum ErrorManagerError: LocalizedError {
    case noOperationToRetry
    
    var errorDescription: String? {
        switch self {
        case .noOperationToRetry:
            return "No operation available to retry"
        }
    }
}