import Foundation
import Combine
import ARKit

// MARK: - Result Extensions for Error Handling
extension Result {
    /// Convert a Result to an AppErrorProtocol if it's a failure
    func mapToAppError<E: AppErrorProtocol>(
        successTransform: (Success) -> Success = { $0 },
        errorTransform: (Failure) -> E
    ) -> Result<Success, E> {
        switch self {
        case .success(let value):
            return .success(successTransform(value))
        case .failure(let error):
            return .failure(errorTransform(error))
        }
    }
    
    /// Log errors automatically when Result is a failure
    func logErrorOnFailure(context: [String: Any] = [:]) -> Result<Success, Failure> {
        if case .failure(let error) = self,
           let appError = error as? AppErrorProtocol {
            ErrorLogger.shared.logError(appError, context: context)
        }
        return self
    }
}

// MARK: - Publisher Extensions for Error Handling
extension Publisher {
    /// Convert any error to an AppErrorProtocol
    func mapErrorToAppError<E: AppErrorProtocol>(_ transform: @escaping (Failure) -> E) -> Publishers.MapError<Self, E> {
        return mapError(transform)
    }
    
    /// Automatically retry with exponential backoff for retryable errors
    func retryOnAppError(maxRetries: Int = 3, delay: TimeInterval = 1.0) -> Publishers.Catch<Publishers.Delay<Self, DispatchQueue>, Self> {
        return self.catch { error -> Publishers.Delay<Self, DispatchQueue> in
            if let appError = error as? AppErrorProtocol,
               appError.isRetryable {
                return self.delay(for: .seconds(delay), scheduler: DispatchQueue.global())
            } else {
                return self.delay(for: .seconds(0), scheduler: DispatchQueue.global())
            }
        }
        .retry(maxRetries)
        .catch { error in
            // After max retries, emit the error
            Fail(error: error)
        }
    }
    
    /// Log errors automatically in a Combine pipeline
    func logErrors(context: [String: Any] = [:]) -> Publishers.HandleEvents<Self> {
        return handleEvents(receiveCompletion: { completion in
            if case .failure(let error) = completion,
               let appError = error as? AppErrorProtocol {
                ErrorLogger.shared.logError(appError, context: context)
            }
        })
    }
    
    /// Report errors to ErrorManager automatically
    func reportErrors(context: [String: Any] = [:]) -> Publishers.HandleEvents<Self> {
        return handleEvents(receiveCompletion: { completion in
            if case .failure(let error) = completion,
               let appError = error as? AppErrorProtocol {
                ErrorManager.shared.reportError(appError, context: context)
            }
        })
    }
}

// MARK: - ARKit Error Conversion
extension ARError {
    /// Convert ARKit errors to our AppError system
    func toAppError() -> ARError {
        switch self.code {
        case .cameraUnauthorized:
            return .permissionDenied
        case .unsupportedConfiguration:
            return .unsupportedDevice
        case .sensorUnavailable, .sensorFailed:
            return .sessionFailed(self.code)
        case .worldTrackingFailed:
            return .trackingLost
        case .insufficientFeatures:
            return .insufficientFeatures
        default:
            return .sessionFailed(self.code)
        }
    }
}

// MARK: - URLError Conversion
extension URLError {
    /// Convert URLError to NetworkError
    func toNetworkError() -> NetworkError {
        switch self.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .timedOut:
            return .timeout
        case .badServerResponse:
            return .invalidResponse
        case .userAuthenticationRequired:
            return .unauthorized
        case .fileDoesNotExist:
            return .notFound
        case .badURL:
            return .badRequest
        default:
            return .serverError(self.errorCode)
        }
    }
}

// MARK: - Core Data Error Conversion
extension NSError {
    /// Convert NSError to appropriate AppError
    func toAppError() -> AppErrorProtocol {
        switch self.domain {
        case NSCocoaErrorDomain:
            return convertCocoaError()
        case NSURLErrorDomain:
            if let urlError = self as? URLError {
                return urlError.toNetworkError()
            }
            return NetworkError.serverError(self.code)
        default:
            return SystemError.unexpectedError(self)
        }
    }
    
    private func convertCocoaError() -> StorageError {
        switch NSCocoaError.Code(rawValue: self.code) {
        case .fileWriteFileExistsError, .fileWriteVolumeReadOnlyError:
            return .writeFailure
        case .fileReadNoSuchFileError:
            return .readFailure
        case .fileWriteOutOfSpaceError:
            return .diskFull
        default:
            return .writeFailure
        }
    }
}

// MARK: - Async/Await Error Handling
extension Task where Failure == Error {
    /// Create a task with automatic error reporting
    static func withErrorReporting<T>(
        priority: TaskPriority? = nil,
        context: [String: Any] = [:],
        operation: @escaping @Sendable () async throws -> T
    ) -> Task<T, Error> {
        return Task(priority: priority) {
            do {
                return try await operation()
            } catch {
                if let appError = error as? AppErrorProtocol {
                    ErrorManager.shared.reportError(appError, context: context)
                } else {
                    let systemError = SystemError.unexpectedError(error)
                    ErrorManager.shared.reportError(systemError, context: context)
                }
                throw error
            }
        }
    }
}

// MARK: - Error Recovery Utilities
class ErrorRecoveryManager {
    static let shared = ErrorRecoveryManager()
    
    private init() {}
    
    /// Execute a recovery action for an error
    func executeRecoveryAction(_ action: RecoveryAction, for error: AppErrorProtocol) {
        switch action {
        case .retry:
            // Handled by caller
            break
        case .retryWithDelay(let delay):
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Trigger retry through ErrorManager
                ErrorManager.shared.retryCurrentError()
            }
        case .restartSession:
            executeSessionRestart()
        case .requestPermission(let permission):
            requestPermission(permission)
        case .goToSettings:
            openAppSettings()
        case .contactSupport:
            openSupportOptions()
        case .none:
            break
        }
    }
    
    private func executeSessionRestart() {
        // Restart AR session or other app sessions
        NotificationCenter.default.post(name: .restartARSession, object: nil)
    }
    
    private func requestPermission(_ permission: String) {
        // Handle specific permission requests
        switch permission.lowercased() {
        case "camera":
            // Camera permissions are handled by ARKit automatically
            openAppSettings()
        default:
            openAppSettings()
        }
    }
    
    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        
        DispatchQueue.main.async {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    private func openSupportOptions() {
        // This would typically open a support form or contact options
        // For now, we'll prepare the error logs for export
        if let logsData = ErrorLogger.shared.exportLogsForSupport() {
            presentSupportOptions(with: logsData)
        }
    }
    
    private func presentSupportOptions(with logsData: Data) {
        // Present activity view controller with logs data
        let activityVC = UIActivityViewController(
            activityItems: [logsData],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Error Context Builders
struct ErrorContextBuilder {
    private var context: [String: Any] = [:]
    
    init() {}
    
    func with(key: String, value: Any) -> ErrorContextBuilder {
        var builder = self
        builder.context[key] = value
        return builder
    }
    
    func withUserAction(_ action: String) -> ErrorContextBuilder {
        return with(key: "user_action", value: action)
    }
    
    func withScreenName(_ screenName: String) -> ErrorContextBuilder {
        return with(key: "screen_name", value: screenName)
    }
    
    func withFeature(_ feature: String) -> ErrorContextBuilder {
        return with(key: "feature", value: feature)
    }
    
    func withNetworkInfo(_ info: [String: Any]) -> ErrorContextBuilder {
        return with(key: "network_info", value: info)
    }
    
    func withPerformanceMetrics(_ metrics: [String: Any]) -> ErrorContextBuilder {
        return with(key: "performance_metrics", value: metrics)
    }
    
    func build() -> [String: Any] {
        return context
    }
}

// MARK: - Global Error Handler
class GlobalErrorHandler {
    static let shared = GlobalErrorHandler()
    
    private init() {
        setupGlobalErrorHandling()
    }
    
    private func setupGlobalErrorHandling() {
        // Handle uncaught exceptions
        NSSetUncaughtExceptionHandler { exception in
            let error = SystemError.unexpectedError(
                NSError(domain: "UncaughtException", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: exception.reason ?? "Unknown exception"
                ])
            )
            ErrorManager.shared.reportError(error, context: [
                "exception_name": exception.name.rawValue,
                "stack_trace": exception.callStackSymbols
            ])
        }
        
        // Handle memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            let error = SystemError.memoryWarning
            ErrorManager.shared.reportError(error, context: [
                "available_memory": self.getAvailableMemory()
            ])
        }
    }
    
    private func getAvailableMemory() -> [String: Any] {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return ["error": "Could not retrieve memory info"]
        }
        
        return [
            "resident_size_mb": Double(info.resident_size) / 1024 / 1024,
            "virtual_size_mb": Double(info.virtual_size) / 1024 / 1024
        ]
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let restartARSession = Notification.Name("restartARSession")
    static let errorOccurred = Notification.Name("errorOccurred")
    static let errorResolved = Notification.Name("errorResolved")
}

// MARK: - Error Handling Middleware for SwiftUI
struct ErrorHandlingModifier: ViewModifier {
    @ObservedObject private var errorManager = ErrorManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Error presentation overlay
            ErrorPresentationView()
        }
    }
}

extension View {
    /// Add error handling to any SwiftUI view
    func withErrorHandling() -> some View {
        modifier(ErrorHandlingModifier())
    }
}