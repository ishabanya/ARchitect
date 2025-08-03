import Foundation
import Combine
import ARKit

/// Protocol defining AR session management capabilities
/// 
/// This protocol provides a comprehensive interface for managing ARKit sessions,
/// including session lifecycle, configuration, and state monitoring.
/// 
/// ## Usage
/// 
/// ```swift
/// let sessionManager: ARSessionManagerProtocol = DIContainer.shared.resolve(ARSessionManagerProtocol.self)
/// 
/// // Start AR session
/// try await sessionManager.startSession()
/// 
/// // Monitor session state
/// sessionManager.sessionStatePublisher
///     .sink { state in
///         print("AR Session state: \(state)")
///     }
///     .store(in: &cancellables)
/// ```
/// 
/// ## Key Features
/// 
/// - **Async/await support**: All methods use modern Swift concurrency
/// - **Reactive updates**: Publishers for real-time state monitoring  
/// - **Memory management**: Automatic cleanup and weak references
/// - **Error handling**: Comprehensive error reporting and recovery
/// 
/// ## Thread Safety
/// 
/// All methods and properties are marked `@MainActor` and must be called from the main thread.
/// Publishers will emit values on the main thread.
@MainActor
protocol ARSessionManagerProtocol: ObservableObject {
    // MARK: - Properties
    
    /// Indicates whether the AR session is currently running
    /// - Returns: `true` if session is active, `false` otherwise
    var isSessionRunning: Bool { get }
    
    /// Current state of the AR session
    /// - Returns: Current `ARSessionState` value
    var sessionState: ARSessionState { get }
    
    /// Current tracking quality assessment
    /// - Returns: Current `ARTrackingQuality` level
    var trackingQuality: ARTrackingQuality { get }
    
    /// Array of currently detected plane anchors
    /// - Returns: Array of `ARPlaneAnchor` objects representing detected planes
    var detectedPlanes: [ARPlaneAnchor] { get }
    
    // MARK: - Publishers
    
    /// Publisher that emits AR session state changes
    /// - Returns: Publisher emitting `ARSessionState` values on the main thread
    var sessionStatePublisher: AnyPublisher<ARSessionState, Never> { get }
    
    /// Publisher that emits tracking quality changes  
    /// - Returns: Publisher emitting `ARTrackingQuality` values on the main thread
    var trackingQualityPublisher: AnyPublisher<ARTrackingQuality, Never> { get }
    
    /// Publisher that emits detected plane updates
    /// - Returns: Publisher emitting arrays of `ARPlaneAnchor` on the main thread
    var detectedPlanesPublisher: AnyPublisher<[ARPlaneAnchor], Never> { get }
    
    /// Publisher that emits session running state changes
    /// - Returns: Publisher emitting `Bool` values indicating if session is running
    var isSessionRunningPublisher: AnyPublisher<Bool, Never> { get }
    
    // MARK: - Methods
    
    /// Starts the AR session with default configuration
    /// - Throws: `ARError` if session fails to start
    /// - Note: This method is async and will complete when session is ready
    func startSession() async throws
    
    /// Pauses the currently running AR session
    /// - Note: Session can be resumed later with `resumeSession()`
    func pauseSession() async
    
    /// Resets the AR session, clearing all tracking data
    /// - Throws: `ARError` if reset fails
    /// - Note: This will remove all anchors and restart tracking
    func resetSession() async throws
    
    /// Stops the AR session completely
    /// - Note: Session must be restarted with `startSession()` after stopping
    func stopSession() async
    
    // MARK: - Configuration
    
    /// Updates the AR session with a new configuration
    /// - Parameter configuration: New `ARWorldTrackingConfiguration` to apply
    /// - Throws: `ARError` if configuration update fails
    func updateConfiguration(_ configuration: ARWorldTrackingConfiguration) async throws
    
    /// Enables plane detection for specified plane types
    /// - Parameter types: `ARPlaneDetection` options to enable
    func enablePlaneDetection(_ types: ARPlaneDetection) async
    
    /// Disables all plane detection
    func disablePlaneDetection() async
}