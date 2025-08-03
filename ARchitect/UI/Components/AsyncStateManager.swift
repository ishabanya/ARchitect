import SwiftUI
import Combine
import Foundation

// MARK: - Async State Manager
@MainActor
public class AsyncStateManager<T>: ObservableObject {
    @Published public private(set) var state: AsyncState<T> = .idle
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var retryCount: Int = 0
    
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    private let timeout: TimeInterval
    private var retryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    
    public init(maxRetries: Int = 3, retryDelay: TimeInterval = 2.0, timeout: TimeInterval = 30.0) {
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.timeout = timeout
    }
    
    deinit {
        retryTask?.cancel()
        timeoutTask?.cancel()
    }
    
    // MARK: - Execute Async Operation
    public func execute(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) {
        guard !state.isLoading else { return }
        
        Task {
            await performOperation(operation, onSuccess: onSuccess, onFailure: onFailure)
        }
    }
    
    public func executeWithAutoRetry(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) {
        Task {
            await performOperationWithRetry(operation, onSuccess: onSuccess, onFailure: onFailure)
        }
    }
    
    // MARK: - Manual State Management
    public func setLoading() {
        state = .loading
        retryCount = 0
        startTimeout()
    }
    
    public func setSuccess(_ data: T) {
        cancelTasks()
        state = .success(data)
        lastUpdated = Date()
        retryCount = 0
    }
    
    public func setError(_ error: Error) {
        cancelTasks()
        state = .error(error)
        lastUpdated = Date()
    }
    
    public func reset() {
        cancelTasks()
        state = .idle
        lastUpdated = nil
        retryCount = 0
    }
    
    // MARK: - Retry Logic
    public func retry() {
        guard let operation = state.lastOperation else { return }
        
        retryCount += 1
        if retryCount <= maxRetries {
            Task {
                await performOperation(operation)
            }
        } else {
            setError(AsyncError.maxRetriesExceeded)
        }
    }
    
    public func canRetry() -> Bool {
        return retryCount < maxRetries && (state.isError || state.isTimeout)
    }
    
    // MARK: - Private Methods
    private func performOperation(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) async {
        setLoading()
        state = .loading(operation: operation)
        
        do {
            let result = try await operation()
            setSuccess(result)
            onSuccess?(result)
        } catch {
            if error is CancellationError {
                state = .cancelled
            } else {
                setError(error)
                onFailure?(error)
            }
        }
    }
    
    private func performOperationWithRetry(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) async {
        for attempt in 0...maxRetries {
            await performOperation(operation, onSuccess: onSuccess, onFailure: nil)
            
            if state.isSuccess {
                break
            } else if attempt < maxRetries && state.isError {
                retryCount = attempt + 1
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            } else {
                onFailure?(state.error ?? AsyncError.unknownError)
                break
            }
        }
    }
    
    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            
            if !Task.isCancelled && state.isLoading {
                setError(AsyncError.timeout)
            }
        }
    }
    
    private func cancelTasks() {
        retryTask?.cancel()
        timeoutTask?.cancel()
        retryTask = nil
        timeoutTask = nil
    }
}

// MARK: - Async State Enum
public enum AsyncState<T> {
    case idle
    case loading(operation: (() async throws -> T)? = nil)
    case success(T)
    case error(Error)
    case cancelled
    case timeout
    
    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
    
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var isError: Bool {
        if case .error = self { return true }
        return false
    }
    
    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
    
    public var isTimeout: Bool {
        if case .timeout = self { return true }
        return false
    }
    
    public var data: T? {
        if case .success(let data) = self { return data }
        return nil
    }
    
    public var error: Error? {
        if case .error(let error) = self { return error }
        if case .timeout = self { return AsyncError.timeout }
        return nil
    }
    
    public var lastOperation: (() async throws -> T)? {
        if case .loading(let operation) = self { return operation }
        return nil
    }
}

// MARK: - Async Error
public enum AsyncError: Error, LocalizedError {
    case timeout
    case cancelled
    case maxRetriesExceeded
    case unknownError
    
    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Operation timed out"
        case .cancelled:
            return "Operation was cancelled"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

// MARK: - SwiftUI Views for Async States
public struct AsyncStateView<Content: View, Loading: View, Error: View, T>: View {
    let asyncState: AsyncState<T>
    let content: (T) -> Content
    let loading: () -> Loading
    let error: (Swift.Error) -> Error
    let onRetry: (() -> Void)?
    
    public init(
        _ asyncState: AsyncState<T>,
        @ViewBuilder content: @escaping (T) -> Content,
        @ViewBuilder loading: @escaping () -> Loading = { ProgressView() },
        @ViewBuilder error: @escaping (Swift.Error) -> Error,
        onRetry: (() -> Void)? = nil
    ) {
        self.asyncState = asyncState
        self.content = content
        self.loading = loading
        self.error = error
        self.onRetry = onRetry
    }
    
    public var body: some View {
        switch asyncState {
        case .idle:
            EmptyView()
            
        case .loading:
            loading()
            
        case .success(let data):
            content(data)
            
        case .error(let err), .timeout:
            VStack(spacing: 16) {
                error(err ?? AsyncError.unknownError)
                
                if let onRetry = onRetry {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.bordered)
                }
            }
            
        case .cancelled:
            Text("Operation cancelled")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Loading State View
public struct LoadingStateView: View {
    let message: String
    let showProgress: Bool
    let progress: Double?
    
    public init(
        message: String = "Loading...",
        showProgress: Bool = true,
        progress: Double? = nil
    ) {
        self.message = message
        self.showProgress = showProgress
        self.progress = progress
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            if showProgress {
                if let progress = progress {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                }
            }
            
            Text(message)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Error State View
public struct ErrorStateView: View {
    let error: Error
    let onRetry: (() -> Void)?
    let showDetails: Bool
    
    @State private var showingDetails = false
    
    public init(
        error: Error,
        onRetry: (() -> Void)? = nil,
        showDetails: Bool = false
    ) {
        self.error = error
        self.onRetry = onRetry
        self.showDetails = showDetails
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Something went wrong")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if showDetails {
                Button("Show Details") {
                    showingDetails.toggle()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if let onRetry = onRetry {
                Button("Try Again") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .sheet(isPresented: $showingDetails) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Error Details")
                            .font(.headline)
                        
                        Text(String(describing: error))
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding()
                }
                .navigationTitle("Error Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingDetails = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Timeout Handler
public class TimeoutHandler: ObservableObject {
    @Published public var isTimedOut = false
    @Published public var timeRemaining: TimeInterval = 0
    
    private var timer: Timer?
    private let timeout: TimeInterval
    
    public init(timeout: TimeInterval) {
        self.timeout = timeout
        self.timeRemaining = timeout
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        timeRemaining = timeout
        isTimedOut = false
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.timeRemaining -= 1.0
            
            if self.timeRemaining <= 0 {
                self.isTimedOut = true
                self.stop()
            }
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    public func reset() {
        stop()
        timeRemaining = timeout
        isTimedOut = false
    }
}

// MARK: - Debounced Async Operation
@MainActor
public class DebouncedAsyncOperation<T>: ObservableObject {
    @Published public private(set) var state: AsyncState<T> = .idle
    
    private var debounceTask: Task<Void, Never>?
    private let debounceTime: TimeInterval
    private let asyncManager: AsyncStateManager<T>
    
    public init(debounceTime: TimeInterval = 0.5) {
        self.debounceTime = debounceTime
        self.asyncManager = AsyncStateManager<T>()
        
        // Mirror the async manager's state
        asyncManager.$state.assign(to: &$state)
    }
    
    public func execute(_ operation: @escaping () async throws -> T) {
        debounceTask?.cancel()
        
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceTime * 1_000_000_000))
            
            if !Task.isCancelled {
                await asyncManager.performOperation(operation)
            }
        }
    }
    
    public func cancel() {
        debounceTask?.cancel()
        asyncManager.reset()
    }
}

// MARK: - Progress Tracking
@MainActor
public class ProgressTracker: ObservableObject {
    @Published public var progress: Double = 0.0
    @Published public var isIndeterminate: Bool = true
    @Published public var statusMessage: String = ""
    @Published public var isCompleted: Bool = false
    
    private var totalSteps: Int = 0
    private var completedSteps: Int = 0
    
    public init() {}
    
    public func startProgress(totalSteps: Int, message: String = "Processing...") {
        self.totalSteps = totalSteps
        self.completedSteps = 0
        self.progress = 0.0
        self.isIndeterminate = false
        self.statusMessage = message
        self.isCompleted = false
    }
    
    public func updateProgress(completedSteps: Int? = nil, message: String? = nil) {
        if let completedSteps = completedSteps {
            self.completedSteps = completedSteps
        } else {
            self.completedSteps += 1
        }
        
        if let message = message {
            self.statusMessage = message
        }
        
        if totalSteps > 0 {
            progress = Double(self.completedSteps) / Double(totalSteps)
            isCompleted = self.completedSteps >= totalSteps
        }
    }
    
    public func setIndeterminate(message: String = "Loading...") {
        isIndeterminate = true
        statusMessage = message
        progress = 0.0
        isCompleted = false
    }
    
    public func complete(message: String = "Completed") {
        progress = 1.0
        isCompleted = true
        statusMessage = message
        isIndeterminate = false
    }
    
    public func reset() {
        progress = 0.0
        isIndeterminate = true
        statusMessage = ""
        isCompleted = false
        totalSteps = 0
        completedSteps = 0
    }
}

// MARK: - Convenience Extensions
extension AsyncStateManager {
    public var isLoading: Bool { state.isLoading }
    public var isSuccess: Bool { state.isSuccess }
    public var isError: Bool { state.isError }
    public var data: T? { state.data }
    public var error: Error? { state.error }
}

// MARK: - View Modifiers
extension View {
    public func asyncState<T>(
        _ state: AsyncState<T>,
        onRetry: (() -> Void)? = nil
    ) -> some View {
        self.overlay(
            Group {
                switch state {
                case .loading:
                    LoadingStateView()
                        .background(.ultraThinMaterial)
                        
                case .error(let error):
                    ErrorStateView(error: error, onRetry: onRetry)
                        .background(.ultraThinMaterial)
                        
                default:
                    EmptyView()
                }
            }
        )
    }
    
    public func loadingOverlay(
        isLoading: Bool,
        message: String = "Loading..."
    ) -> some View {
        self.overlay(
            Group {
                if isLoading {
                    LoadingStateView(message: message)
                        .background(.ultraThinMaterial)
                }
            }
        )
    }
}