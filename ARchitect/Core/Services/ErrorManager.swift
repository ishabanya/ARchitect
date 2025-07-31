import Foundation
import Combine
import os.log

// MARK: - Error Queue Item
struct ErrorQueueItem {
    let id: UUID
    let error: AppErrorProtocol
    let timestamp: Date
    let context: [String: Any]
    var retryCount: Int
    var isBeingProcessed: Bool
    
    init(error: AppErrorProtocol, context: [String: Any] = [:]) {
        self.id = UUID()
        self.error = error
        self.timestamp = Date()
        self.context = context
        self.retryCount = 0
        self.isBeingProcessed = false
    }
}

// MARK: - Error Manager
class ErrorManager: ObservableObject {
    static let shared = ErrorManager()
    
    // MARK: - Published Properties
    @Published private(set) var activeErrors: [ErrorQueueItem] = []
    @Published private(set) var currentError: ErrorQueueItem?
    @Published private(set) var isProcessingErrors = false
    
    // MARK: - Private Properties
    private var errorQueue: [ErrorQueueItem] = []
    private let maxRetryCount = 3
    private let maxQueueSize = 50
    private let errorProcessingQueue = DispatchQueue(label: "com.architect.error-processing", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var retryTimers: [UUID: Timer] = [:]
    
    private let logger = Logger(subsystem: "com.architect.ARchitect", category: "ErrorManager")
    
    private init() {
        setupErrorProcessing()
    }
    
    // MARK: - Public Methods
    
    /// Report a new error to the system
    func reportError(_ error: AppErrorProtocol, context: [String: Any] = [:]) {
        errorProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let errorItem = ErrorQueueItem(error: error, context: context)
            
            // Log the error immediately
            self.logError(errorItem)
            
            // Check for duplicate errors to avoid spam
            if !self.isDuplicateError(errorItem) {
                self.addToQueue(errorItem)
            }
            
            // Process the queue
            self.processNextError()
        }
    }
    
    /// Manually retry the current error
    func retryCurrentError() {
        guard let currentError = currentError,
              currentError.error.isRetryable,
              currentError.retryCount < maxRetryCount else {
            return
        }
        
        errorProcessingQueue.async { [weak self] in
            self?.executeRetry(for: currentError)
        }
    }
    
    /// Dismiss the current error without retrying
    func dismissCurrentError() {
        errorProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.currentError = nil
                self.isProcessingErrors = false
            }
            
            // Process next error if any
            self.processNextError()
        }
    }
    
    /// Clear all errors from the queue
    func clearAllErrors() {
        errorProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel all retry timers
            self.retryTimers.values.forEach { $0.invalidate() }
            self.retryTimers.removeAll()
            
            DispatchQueue.main.async {
                self.errorQueue.removeAll()
                self.activeErrors.removeAll()
                self.currentError = nil
                self.isProcessingErrors = false
            }
        }
    }
    
    /// Get error statistics for debugging
    func getErrorStatistics() -> [String: Any] {
        return [
            "totalActiveErrors": activeErrors.count,
            "queuedErrors": errorQueue.count,
            "currentlyProcessing": isProcessingErrors,
            "errorsByCategory": getErrorsByCategory(),
            "errorsBySeverity": getErrorsBySeverity()
        ]
    }
    
    // MARK: - Private Methods
    
    private func setupErrorProcessing() {
        // Monitor app state changes to pause/resume error processing
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.pauseErrorProcessing()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.resumeErrorProcessing()
            }
            .store(in: &cancellables)
    }
    
    private func addToQueue(_ errorItem: ErrorQueueItem) {
        // Maintain queue size limit
        if errorQueue.count >= maxQueueSize {
            // Remove oldest low-severity errors first
            if let oldestLowSeverityIndex = errorQueue.firstIndex(where: { $0.error.severity == .low }) {
                errorQueue.remove(at: oldestLowSeverityIndex)
            } else {
                errorQueue.removeFirst()
            }
        }
        
        // Insert error based on priority (severity)
        let insertIndex = errorQueue.firstIndex { existingError in
            errorItem.error.severity.rawValue > existingError.error.severity.rawValue
        } ?? errorQueue.count
        
        errorQueue.insert(errorItem, at: insertIndex)
        
        DispatchQueue.main.async {
            self.activeErrors = self.errorQueue
        }
    }
    
    private func processNextError() {
        guard !isProcessingErrors,
              let nextError = errorQueue.first else {
            return
        }
        
        var errorToProcess = nextError
        errorToProcess.isBeingProcessed = true
        
        // Update the queue
        if let index = errorQueue.firstIndex(where: { $0.id == nextError.id }) {
            errorQueue[index] = errorToProcess
        }
        
        DispatchQueue.main.async {
            self.currentError = errorToProcess
            self.isProcessingErrors = true
            self.activeErrors = self.errorQueue
        }
        
        // Handle automatic retry for retryable errors
        if errorToProcess.error.isRetryable,
           let recoveryAction = errorToProcess.error.recoveryAction {
            handleAutomaticRetry(for: errorToProcess, recoveryAction: recoveryAction)
        }
    }
    
    private func handleAutomaticRetry(for errorItem: ErrorQueueItem, recoveryAction: RecoveryAction) {
        switch recoveryAction {
        case .retryWithDelay(let delay):
            scheduleRetry(for: errorItem, after: delay)
        case .retry:
            scheduleRetry(for: errorItem, after: 1.0)
        default:
            // Manual recovery required - keep error displayed
            break
        }
    }
    
    private func scheduleRetry(for errorItem: ErrorQueueItem, after delay: TimeInterval) {
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.executeRetry(for: errorItem)
        }
        
        retryTimers[errorItem.id] = timer
    }
    
    private func executeRetry(for errorItem: ErrorQueueItem) {
        guard errorItem.retryCount < maxRetryCount else {
            // Max retries reached, remove from queue
            removeFromQueue(errorItem.id)
            return
        }
        
        var updatedItem = errorItem
        updatedItem.retryCount += 1
        
        // Update the queue
        if let index = errorQueue.firstIndex(where: { $0.id == errorItem.id }) {
            errorQueue[index] = updatedItem
        }
        
        // Cancel existing timer
        retryTimers[errorItem.id]?.invalidate()
        retryTimers.removeValue(forKey: errorItem.id)
        
        // For now, just log the retry attempt
        // In a real implementation, this would trigger the actual retry logic
        logger.info("Retrying error: \(errorItem.error.errorCode), attempt: \(updatedItem.retryCount)")
        
        // Simulate retry success/failure (in real app, this would be determined by the actual operation)
        let retrySuccess = Bool.random() // Replace with actual retry logic
        
        if retrySuccess {
            removeFromQueue(errorItem.id)
        } else if updatedItem.retryCount >= maxRetryCount {
            // Max retries reached, convert to non-retryable error
            removeFromQueue(errorItem.id)
            
            // Optionally report a new error indicating retry failure
            let retryFailedError = createRetryFailedError(from: errorItem.error)
            reportError(retryFailedError)
        } else {
            // Schedule next retry with exponential backoff
            let nextDelay = calculateBackoffDelay(retryCount: updatedItem.retryCount)
            scheduleRetry(for: updatedItem, after: nextDelay)
        }
    }
    
    private func removeFromQueue(_ errorId: UUID) {
        errorQueue.removeAll { $0.id == errorId }
        retryTimers[errorId]?.invalidate()
        retryTimers.removeValue(forKey: errorId)
        
        DispatchQueue.main.async {
            self.activeErrors = self.errorQueue
            
            if self.currentError?.id == errorId {
                self.currentError = nil
                self.isProcessingErrors = false
            }
        }
        
        // Process next error
        processNextError()
    }
    
    private func calculateBackoffDelay(retryCount: Int) -> TimeInterval {
        // Exponential backoff: 2^retryCount seconds, capped at 60 seconds
        return min(pow(2.0, Double(retryCount)), 60.0)
    }
    
    private func createRetryFailedError(from error: AppErrorProtocol) -> AppErrorProtocol {
        // Create a generic retry failed error
        return SystemError.retryFailed(originalError: error)
    }
    
    private func isDuplicateError(_ errorItem: ErrorQueueItem) -> Bool {
        // Check if similar error exists in recent history (last 5 seconds)
        let recentThreshold = Date().addingTimeInterval(-5.0)
        
        return errorQueue.contains { existingError in
            existingError.error.errorCode == errorItem.error.errorCode &&
            existingError.timestamp > recentThreshold
        }
    }
    
    private func logError(_ errorItem: ErrorQueueItem) {
        let errorData: [String: Any] = [
            "errorCode": errorItem.error.errorCode,
            "category": errorItem.error.errorCategory.rawValue,
            "severity": errorItem.error.severity.rawValue,
            "timestamp": errorItem.timestamp.timeIntervalSince1970,
            "context": errorItem.context
        ]
        
        // Log based on severity
        switch errorItem.error.severity {
        case .critical:
            logger.critical("Critical error: \(errorData)")
        case .high:
            logger.error("High severity error: \(errorData)")
        case .medium:
            logger.info("Medium severity error: \(errorData)")
        case .low:
            logger.debug("Low severity error: \(errorData)")
        }
    }
    
    private func pauseErrorProcessing() {
        // Pause automatic retries but keep errors in queue
        retryTimers.values.forEach { $0.invalidate() }
        retryTimers.removeAll()
    }
    
    private func resumeErrorProcessing() {
        // Resume processing if there are queued errors
        if !errorQueue.isEmpty && !isProcessingErrors {
            processNextError()
        }
    }
    
    private func getErrorsByCategory() -> [String: Int] {
        let categories = Dictionary(grouping: activeErrors, by: { $0.error.errorCategory.rawValue })
        return categories.mapValues { $0.count }
    }
    
    private func getErrorsBySeverity() -> [String: Int] {
        let severities = Dictionary(grouping: activeErrors, by: { $0.error.severity.rawValue })
        return severities.mapValues { $0.count }
    }
}

// MARK: - System Errors
enum SystemError: AppErrorProtocol {
    case retryFailed(originalError: AppErrorProtocol)
    case unexpectedError(Error)
    case memoryWarning
    case backgroundTaskExpired
    
    var errorCode: String {
        switch self {
        case .retryFailed:
            return "SYSTEM_RETRY_FAILED"
        case .unexpectedError:
            return "SYSTEM_UNEXPECTED_ERROR"
        case .memoryWarning:
            return "SYSTEM_MEMORY_WARNING"
        case .backgroundTaskExpired:
            return "SYSTEM_BACKGROUND_TASK_EXPIRED"
        }
    }
    
    var errorCategory: ErrorCategory { .system }
    
    var severity: ErrorSeverity {
        switch self {
        case .memoryWarning:
            return .critical
        case .retryFailed:
            return .high
        case .unexpectedError, .backgroundTaskExpired:
            return .medium
        }
    }
    
    var isRetryable: Bool { false }
    
    var userMessage: String {
        switch self {
        case .retryFailed(let originalError):
            return "Unable to resolve the issue after multiple attempts. Original error: \(originalError.userMessage)"
        case .unexpectedError:
            return "An unexpected error occurred. Please try again."
        case .memoryWarning:
            return "The app is running low on memory. Please close other apps and try again."
        case .backgroundTaskExpired:
            return "Background operation was interrupted. Please try again when the app is active."
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .retryFailed:
            return .contactSupport
        case .unexpectedError:
            return .retry
        case .memoryWarning:
            return .none
        case .backgroundTaskExpired:
            return .retry
        }
    }
    
    var underlyingError: Error? {
        switch self {
        case .unexpectedError(let error):
            return error
        default:
            return nil
        }
    }
    
    var metadata: [String: Any] { [:] }
    var errorDescription: String? { userMessage }
}