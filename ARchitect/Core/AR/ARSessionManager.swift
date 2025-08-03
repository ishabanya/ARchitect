import Foundation
import ARKit
import RealityKit
import Combine
import SwiftUI

// MARK: - AR Session State
public enum ARSessionState: String, CaseIterable {
    case notInitialized = "not_initialized"
    case initializing = "initializing"
    case ready = "ready"
    case running = "running"
    case paused = "paused"
    case interrupted = "interrupted"
    case failed = "failed"
    case unavailable = "unavailable"
    case relocalizating = "relocalizing"
    
    var displayName: String {
        switch self {
        case .notInitialized: return "Not Initialized"
        case .initializing: return "Starting AR..."
        case .ready: return "AR Ready"
        case .running: return "AR Active"
        case .paused: return "AR Paused"
        case .interrupted: return "AR Interrupted"
        case .failed: return "AR Failed"
        case .unavailable: return "AR Unavailable"
        case .relocalizating: return "Relocating..."
        }
    }
    
    var color: Color {
        switch self {
        case .notInitialized, .unavailable: return .gray
        case .initializing, .relocalizating: return .orange
        case .ready, .running: return .green
        case .paused: return .yellow
        case .interrupted: return .orange
        case .failed: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .notInitialized: return "circle"
        case .initializing: return "arrow.clockwise"
        case .ready: return "checkmark.circle"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle"
        case .interrupted: return "exclamationmark.triangle"
        case .failed: return "xmark.circle"
        case .unavailable: return "nosign"
        case .relocalizating: return "location.circle"
        }
    }
}

// MARK: - AR Tracking Quality
public enum ARTrackingQuality: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case unavailable = "unavailable"
    
    var displayName: String {
        return rawValue.capitalized
    }
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .mint
        case .fair: return .yellow
        case .poor: return .orange
        case .unavailable: return .red
        }
    }
    
    var score: Double {
        switch self {
        case .excellent: return 1.0
        case .good: return 0.8
        case .fair: return 0.6
        case .poor: return 0.4
        case .unavailable: return 0.0
        }
    }
}

// MARK: - AR Configuration Options
public struct ARConfigurationOptions {
    let planeDetection: ARWorldTrackingConfiguration.PlaneDetection
    let sceneReconstruction: ARWorldTrackingConfiguration.SceneReconstruction
    let environmentTexturing: ARWorldTrackingConfiguration.EnvironmentTexturing
    let frameSemantics: ARConfiguration.FrameSemantics
    let providesAudioData: Bool
    let isLightEstimationEnabled: Bool
    let isCollaborationEnabled: Bool
    let maximumNumberOfTrackedImages: Int
    let detectionImages: Set<ARReferenceImage>?
    
    static let `default` = ARConfigurationOptions(
        planeDetection: [.horizontal, .vertical],
        sceneReconstruction: .meshWithClassification,
        environmentTexturing: .automatic,
        frameSemantics: [.sceneDepth, .smoothedSceneDepth],
        providesAudioData: false,
        isLightEstimationEnabled: true,
        isCollaborationEnabled: false,
        maximumNumberOfTrackedImages: 4,
        detectionImages: nil
    )
    
    static func forInteriorDesign() -> ARConfigurationOptions {
        return ARConfigurationOptions(
            planeDetection: [.horizontal, .vertical],
            sceneReconstruction: .meshWithClassification,
            environmentTexturing: .automatic,
            frameSemantics: [.sceneDepth, .smoothedSceneDepth],
            providesAudioData: false,
            isLightEstimationEnabled: true,
            isCollaborationEnabled: true,
            maximumNumberOfTrackedImages: 10,
            detectionImages: nil
        )
    }
    
    static func fallback() -> ARConfigurationOptions {
        return ARConfigurationOptions(
            planeDetection: [.horizontal],
            sceneReconstruction: .none,
            environmentTexturing: .none,
            frameSemantics: [],
            providesAudioData: false,
            isLightEstimationEnabled: false,
            isCollaborationEnabled: false,
            maximumNumberOfTrackedImages: 0,
            detectionImages: nil
        )
    }
}

// MARK: - AR Session Manager
@MainActor
public class ARSessionManager: NSObject, ObservableObject, ARSessionManagerProtocol {
    // MARK: - Published Properties
    @Published public var sessionState: ARSessionState = .notInitialized
    @Published public var trackingState: ARCamera.TrackingState = .notAvailable
    @Published public var trackingQuality: ARTrackingQuality = .unavailable
    @Published public var sessionError: Error?
    @Published public var lastKnownError: AppErrorProtocol?
    @Published public var isCoachingActive = false
    @Published public var shouldShowCoaching = false
    @Published public var detectedPlanes: [ARPlaneAnchor] = []
    @Published public var trackingQualityHistory: [ARTrackingQuality] = []
    @Published public var sessionMetrics = ARSessionMetrics()
    
    // MARK: - Protocol Conformance
    public var sessionStatePublisher: AnyPublisher<ARSessionState, Never> {
        $sessionState.eraseToAnyPublisher()
    }
    
    public var trackingQualityPublisher: AnyPublisher<ARTrackingQuality, Never> {
        $trackingQuality.eraseToAnyPublisher()
    }
    
    public var detectedPlanesPublisher: AnyPublisher<[ARPlaneAnchor], Never> {
        $detectedPlanes.eraseToAnyPublisher()
    }
    
    public var isSessionRunningPublisher: AnyPublisher<Bool, Never> {
        $sessionState.map { $0 == .running }.eraseToAnyPublisher()
    }
    
    // MARK: - Public Properties
    public var isSessionRunning: Bool {
        return sessionState == .running
    }
    
    public var isARAvailable: Bool {
        return ARWorldTrackingConfiguration.isSupported
    }
    
    public var arView: ARView {
        return _arView
    }
    
    public var session: ARSession {
        return _arView.session
    }
    
    // MARK: - Private Properties
    private let _arView: ARView
    private var cancellables = Set<AnyCancellable>()
    private let errorManager = ErrorManager.shared
    private var sessionRestartAttempts = 0
    private let maxRestartAttempts = 3
    private var configurationOptions: ARConfigurationOptions
    private var trackingQualityTimer: Timer?
    private var sessionStartTime: Date?
    private var lastTrackingUpdate: Date = Date()
    private var interruptionReason: String?
    
    // Coaching
    private var coachingOverlay: ARCoachingOverlayView?
    
    // Fallback mode
    private var isFallbackMode = false
    private var fallbackReason: String?
    
    // MARK: - Initialization
    public override init() {
        self._arView = ARView(frame: .zero)
        self.configurationOptions = .forInteriorDesign()
        super.init()
        
        setupARView()
        setupSession()
        setupCoaching()
        setupMonitoring()
        
        logInfo("AR Session Manager initialized", category: .ar, context: LogContext(customData: [
            "ar_supported": isARAvailable,
            "device_model": UIDevice.current.model
        ]))
    }
    
    deinit {
        trackingQualityTimer?.invalidate()
        session.pause()
        
        logInfo("AR Session Manager deinitialized", category: .ar)
    }
    
    // MARK: - Public Methods
    
    public func startSession() async throws {
        try await startSession(with: nil)
    }
    
    private func startSession(with options: ARConfigurationOptions? = nil) async throws {
        let startTime = Date()
        
        if let options = options {
            self.configurationOptions = options
        }
        
        guard isARAvailable else {
            enterFallbackMode(reason: "ARKit not supported on this device")
            // Track AR unavailable
            AnalyticsManager.shared.trackFeatureUsage(.arSessionStart, parameters: [
                "result": "unavailable",
                "reason": "ARKit not supported"
            ])
            return
        }
        
        sessionState = .initializing
        sessionStartTime = Date()
        sessionRestartAttempts = 0
        
        logInfo("Starting AR session", category: .ar, context: LogContext(customData: [
            "configuration": describeConfiguration(configurationOptions)
        ]))
        
        // Track AR session start attempt
        AnalyticsManager.shared.trackFeatureUsage(.arSessionStart, parameters: [
            "plane_detection": configurationOptions.planeDetection.contains(.horizontal) ? "horizontal" : "none",
            "scene_reconstruction": configurationOptions.sceneReconstruction != .none ? "enabled" : "disabled",
            "collaboration": configurationOptions.isCollaborationEnabled,
            "light_estimation": configurationOptions.isLightEstimationEnabled
        ])
        
        do {
            let config = try createARConfiguration(options: configurationOptions)
            
            return try await withCheckedThrowingContinuation { continuation in
                session.run(config)
                
                // Wait for session to become ready
                let cancellable = $sessionState
                    .filter { $0 == .ready || $0 == .failed }
                    .first()
                    .sink { state in
                        if state == .ready {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: ARError.sessionFailed)
                        }
                    }
                
                // Set initial state
                sessionState = .ready
            
            // Track successful AR initialization
            let initTime = Date().timeIntervalSince(startTime)
            AnalyticsManager.shared.trackPerformanceMetric(.arInitializationTime, value: initTime, parameters: [
                "configuration_type": String(describing: type(of: config))
            ])
            
            // Show coaching if needed
            if shouldShowCoachingForCurrentState() {
                showCoaching()
            }
            
        } catch {
            handleARConfigurationError(error)
            
            // Track AR initialization failure
            AnalyticsManager.shared.trackError(error: error, context: [
                "function": "startSession",
                "configuration": describeConfiguration(configurationOptions)
            ])
        }
    }
    
    public func pauseSession() async {
        guard sessionState == .running || sessionState == .ready else { return }
        
        // Track session duration before pausing
        let sessionDuration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        session.pause()
        sessionState = .paused
        hideCoaching()
        
        logInfo("AR session paused", category: .ar)
        
        // Track AR session pause
        AnalyticsManager.shared.trackFeatureUsage(.arSessionEnd, parameters: [
            "reason": "paused",
            "session_duration": sessionDuration,
            "tracking_state": trackingState.rawValue
        ])
    }
    
    public func resumeSession() async throws {
        guard sessionState == .paused else { return }
        
        let config = try createARConfiguration(options: configurationOptions)
        
        return try await withCheckedThrowingContinuation { continuation in
            session.run(config)
            
            let cancellable = $sessionState
                .filter { $0 == .running || $0 == .failed }
                .first()
                .sink { state in
                    if state == .running {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ARError.sessionFailed)
                    }
                }
            
            sessionState = .running
            logInfo("AR session resumed", category: .ar)
        }
    }
    
    public func resetSession() async throws {
        logInfo("Resetting AR session", category: .ar)
        
        let config = try createARConfiguration(options: configurationOptions)
        
        return try await withCheckedThrowingContinuation { continuation in
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
            
            // Clear detected planes
            detectedPlanes.removeAll()
            
            // Reset metrics
            sessionMetrics = ARSessionMetrics()
            sessionStartTime = Date()
            
            let cancellable = $sessionState
                .filter { $0 == .running || $0 == .failed }
                .first()
                .sink { state in
                    if state == .running {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ARError.sessionFailed)
                    }
                }
            
            sessionState = .running
        }
    }
    
    public func switchToFallbackMode() {
        enterFallbackMode(reason: "User requested fallback mode")
    }
    
    public func stopSession() async {
        session.pause()
        sessionState = .paused
        hideCoaching()
        
        logInfo("AR session stopped", category: .ar)
    }
    
    public func updateConfiguration(_ configuration: ARWorldTrackingConfiguration) async throws {
        guard sessionState == .running || sessionState == .ready else { return }
        
        return try await withCheckedThrowingContinuation { continuation in
            session.run(configuration)
            continuation.resume()
        }
    }
    
    public func enablePlaneDetection(_ types: ARPlaneDetection) async {
        configurationOptions = ARConfigurationOptions(
            planeDetection: types,
            sceneReconstruction: configurationOptions.sceneReconstruction,
            environmentTexturing: configurationOptions.environmentTexturing,
            frameSemantics: configurationOptions.frameSemantics,
            providesAudioData: configurationOptions.providesAudioData,
            isLightEstimationEnabled: configurationOptions.isLightEstimationEnabled,
            isCollaborationEnabled: configurationOptions.isCollaborationEnabled,
            maximumNumberOfTrackedImages: configurationOptions.maximumNumberOfTrackedImages,
            detectionImages: configurationOptions.detectionImages
        )
        
        if sessionState == .running || sessionState == .ready {
            do {
                let config = try createARConfiguration(options: configurationOptions)
                try await updateConfiguration(config)
            } catch {
                logError("Failed to enable plane detection: \(error)", category: .ar)
            }
        }
    }
    
    public func disablePlaneDetection() async {
        await enablePlaneDetection([])
    }
    
    public func updateConfigurationOptions(_ options: ARConfigurationOptions) async {
        self.configurationOptions = options
        
        guard sessionState == .running || sessionState == .ready else { return }
        
        logInfo("Updating AR configuration", category: .ar, context: LogContext(customData: [
            "new_configuration": describeConfiguration(options)
        ]))
        
        do {
            let config = try createARConfiguration(options: options)
            try await updateConfiguration(config)
        } catch {
            logError("Failed to update AR configuration: \(error)", category: .ar)
        }
    }
    
    public func addAnchor(_ anchor: ARAnchor) {
        session.add(anchor: anchor)
        
        logDebug("Added AR anchor", category: .ar, context: LogContext(customData: [
            "anchor_type": String(describing: type(of: anchor)),
            "anchor_id": anchor.identifier.uuidString
        ]))
    }
    
    public func removeAnchor(_ anchor: ARAnchor) {
        session.remove(anchor: anchor)
        
        logDebug("Removed AR anchor", category: .ar, context: LogContext(customData: [
            "anchor_type": String(describing: type(of: anchor)),
            "anchor_id": anchor.identifier.uuidString
        ]))
    }
    
    // MARK: - Private Setup Methods
    
    private func setupARView() {
        _arView.session.delegate = self
        _arView.automaticallyConfigureSession = false
        _arView.debugOptions = []
        
        #if DEBUG
        if AppEnvironment.current == .development {
            _arView.debugOptions = [.showFeaturePoints, .showAnchorOrigins]
        }
        #endif
    }
    
    private func setupSession() {
        // Listen for session notifications
        NotificationCenter.default.publisher(for: .restartARSession)
            .sink { [weak self] _ in
                self?.handleSessionRestart()
            }
            .store(in: &cancellables)
        
        // Listen for app lifecycle changes
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &cancellables)
        
        // Monitor device orientation changes
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleOrientationChange()
            }
            .store(in: &cancellables)
    }
    
    private func setupCoaching() {
        coachingOverlay = ARCoachingOverlayView()
        guard let coaching = coachingOverlay else { return }
        
        coaching.session = session
        coaching.delegate = self
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = false
        
        // Add coaching overlay to AR view
        _arView.addSubview(coaching)
        coaching.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coaching.centerXAnchor.constraint(equalTo: _arView.centerXAnchor),
            coaching.centerYAnchor.constraint(equalTo: _arView.centerYAnchor),
            coaching.widthAnchor.constraint(equalTo: _arView.widthAnchor),
            coaching.heightAnchor.constraint(equalTo: _arView.heightAnchor)
        ])
    }
    
    private func setupMonitoring() {
        // Start tracking quality monitoring
        trackingQualityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTrackingQuality()
            self?.updateSessionMetrics()
        }
    }
    
    // MARK: - Configuration Creation
    
    private func createARConfiguration(options: ARConfigurationOptions) throws -> ARWorldTrackingConfiguration {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ARError.unsupportedDevice
        }
        
        let config = ARWorldTrackingConfiguration()
        
        // Plane detection
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(options.sceneReconstruction) {
            config.sceneReconstruction = options.sceneReconstruction
        } else {
            config.sceneReconstruction = .none
            logWarning("Scene reconstruction not supported, falling back to none", category: .ar)
        }
        
        config.planeDetection = options.planeDetection
        config.environmentTexturing = options.environmentTexturing
        config.providesAudioData = options.providesAudioData
        config.isLightEstimationEnabled = options.isLightEstimationEnabled
        config.isCollaborationEnabled = options.isCollaborationEnabled
        
        // Frame semantics
        if ARWorldTrackingConfiguration.supportsFrameSemantics(options.frameSemantics) {
            config.frameSemantics = options.frameSemantics
        } else {
            config.frameSemantics = []
            logWarning("Frame semantics not supported, disabling", category: .ar)
        }
        
        // Detection images
        if let detectionImages = options.detectionImages, !detectionImages.isEmpty {
            config.detectionImages = detectionImages
            config.maximumNumberOfTrackedImages = options.maximumNumberOfTrackedImages
        }
        
        return config
    }
    
    // MARK: - State Management
    
    private func updateTrackingQuality() {
        let quality = calculateTrackingQuality()
        
        if quality != trackingQuality {
            trackingQuality = quality
            trackingQualityHistory.append(quality)
            
            // Keep only last 60 seconds of history
            if trackingQualityHistory.count > 60 {
                trackingQualityHistory.removeFirst()
            }
            
            // Update coaching visibility based on quality
            updateCoachingVisibility()
            
            // Log significant quality changes
            if quality == .poor || quality == .unavailable {
                logWarning("AR tracking quality degraded to \(quality.rawValue)", category: .ar, context: LogContext(customData: [
                    "tracking_state": trackingState.description,
                    "plane_count": detectedPlanes.count
                ]))
            }
        }
        
        lastTrackingUpdate = Date()
    }
    
    private func calculateTrackingQuality() -> ARTrackingQuality {
        switch trackingState {
        case .normal:
            let planeCount = detectedPlanes.count
            let sessionDuration = sessionStartTime?.timeIntervalSinceNow ?? 0
            
            if planeCount >= 3 && abs(sessionDuration) > 5 {
                return .excellent
            } else if planeCount >= 1 && abs(sessionDuration) > 2 {
                return .good
            } else {
                return .fair
            }
            
        case .limited(let reason):
            switch reason {
            case .initializing:
                return .fair
            case .relocalizing:
                return .poor
            case .excessiveMotion:
                return .poor
            case .insufficientFeatures:
                return .poor
            @unknown default:
                return .poor
            }
            
        case .notAvailable:
            return .unavailable
        }
    }
    
    private func updateSessionMetrics() {
        sessionMetrics.updateTime = Date()
        sessionMetrics.sessionDuration = sessionStartTime?.timeIntervalSinceNow ?? 0
        sessionMetrics.trackingQuality = trackingQuality
        sessionMetrics.planeCount = detectedPlanes.count
        sessionMetrics.trackingStateChanges += (trackingQuality != sessionMetrics.trackingQuality) ? 1 : 0
    }
    
    // MARK: - Coaching Management
    
    private func shouldShowCoachingForCurrentState() -> Bool {
        guard !isFallbackMode else { return false }
        
        // Show coaching if tracking quality is poor or no planes detected
        return trackingQuality == .poor || 
               trackingQuality == .unavailable || 
               (detectedPlanes.isEmpty && sessionState == .running)
    }
    
    private func updateCoachingVisibility() {
        let shouldShow = shouldShowCoachingForCurrentState()
        
        if shouldShow && !isCoachingActive {
            showCoaching()
        } else if !shouldShow && isCoachingActive {
            hideCoaching()
        }
    }
    
    private func showCoaching() {
        guard let coaching = coachingOverlay, !isCoachingActive else { return }
        
        isCoachingActive = true
        shouldShowCoaching = true
        coaching.setActive(true, animated: true)
        
        logInfo("AR coaching overlay activated", category: .ar, context: LogContext(customData: [
            "tracking_quality": trackingQuality.rawValue,
            "plane_count": detectedPlanes.count
        ]))
    }
    
    private func hideCoaching() {
        guard let coaching = coachingOverlay, isCoachingActive else { return }
        
        isCoachingActive = false
        shouldShowCoaching = false
        coaching.setActive(false, animated: true)
        
        logInfo("AR coaching overlay deactivated", category: .ar)
    }
    
    // MARK: - Fallback Mode
    
    private func enterFallbackMode(reason: String) {
        isFallbackMode = true
        fallbackReason = reason
        sessionState = .unavailable
        hideCoaching()
        
        logWarning("Entering AR fallback mode", category: .ar, context: LogContext(customData: [
            "reason": reason,
            "ar_supported": isARAvailable
        ]))
        
        // Switch to minimal configuration or disable AR features
        configurationOptions = .fallback()
        
        // Implement fallback behaviors
        implementFallbackBehaviors()
        
        // Notify other systems about fallback mode
        NotificationCenter.default.post(name: .arFallbackModeActivated, object: reason)
    }
    
    private func implementFallbackBehaviors() {
        // Enable 2D mode for furniture placement
        enableTwoDimensionalMode()
        
        // Use device gyroscope for basic orientation tracking
        startGyroscopeTracking()
        
        // Enable manual measurement mode
        enableManualMeasurementMode()
        
        // Disable AR-dependent features gracefully
        disableAROnlyFeatures()
        
        logInfo("AR fallback behaviors implemented", category: .ar, context: LogContext(customData: [
            "2d_mode": true,
            "gyroscope_tracking": true,
            "manual_measurement": true
        ]))
    }
    
    private func enableTwoDimensionalMode() {
        // Switch to 2D furniture catalog view
        NotificationCenter.default.post(name: .enableTwoDimensionalMode, object: nil)
    }
    
    private func startGyroscopeTracking() {
        // Use CoreMotion for basic device orientation
        NotificationCenter.default.post(name: .startGyroscopeTracking, object: nil)
    }
    
    private func enableManualMeasurementMode() {
        // Allow users to input measurements manually
        NotificationCenter.default.post(name: .enableManualMeasurement, object: nil)
    }
    
    private func disableAROnlyFeatures() {
        // Disable features that require AR
        let disabledFeatures = [
            "real_time_occlusion",
            "plane_detection",
            "3d_room_scanning",
            "ar_collaboration"
        ]
        
        NotificationCenter.default.post(
            name: .disableARFeatures, 
            object: nil,
            userInfo: ["disabled_features": disabledFeatures]
        )
    }
    
    private func exitFallbackMode() {
        guard isFallbackMode else { return }
        
        isFallbackMode = false
        fallbackReason = nil
        configurationOptions = .forInteriorDesign()
        
        logInfo("Exiting AR fallback mode", category: .ar)
        
        // Restart session with full configuration
        startSession()
        
        NotificationCenter.default.post(name: .arFallbackModeDeactivated, object: nil)
    }
    
    // MARK: - Error Handling
    
    private func handleARConfigurationError(_ error: Error) {
        let arError: ARError
        
        if let arkitError = error as? ARKit.ARError {
            arError = arkitError.toAppError()
        } else {
            arError = ARError.sessionFailed(ARKit.ARError.Code.unsupportedConfiguration)
        }
        
        lastKnownError = arError
        sessionError = error
        sessionState = .failed
        
        logError("AR configuration error: \(error.localizedDescription)", category: .ar, context: LogContext(customData: [
            "error_code": (error as NSError).code,
            "restart_attempts": sessionRestartAttempts
        ]))
        
        // Try to recover or enter fallback mode
        if sessionRestartAttempts < maxRestartAttempts {
            sessionRestartAttempts += 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.startSession(with: .fallback())
            }
        } else {
            enterFallbackMode(reason: "Max restart attempts reached")
        }
        
        errorManager.reportError(arError, context: [
            "session_state": sessionState.rawValue,
            "restart_attempts": sessionRestartAttempts
        ])
    }
    
    private func handleSessionRestart() {
        guard sessionRestartAttempts < maxRestartAttempts else {
            enterFallbackMode(reason: "Max restart attempts exceeded")
            return
        }
        
        sessionRestartAttempts += 1
        
        logInfo("Restarting AR session", category: .ar, context: LogContext(customData: [
            "attempt": sessionRestartAttempts,
            "max_attempts": maxRestartAttempts
        ]))
        
        resetSession()
    }
    
    // MARK: - App Lifecycle Handling
    
    private func handleAppDidBecomeActive() {
        guard sessionState == .paused || sessionState == .interrupted else { return }
        
        logInfo("App became active, resuming AR session", category: .ar)
        resumeSession()
    }
    
    private func handleAppWillResignActive() {
        guard sessionState == .running else { return }
        
        logInfo("App will resign active, pausing AR session", category: .ar)
        pauseSession()
    }
    
    private func handleOrientationChange() {
        // Update AR configuration if needed based on orientation
        logDebug("Device orientation changed", category: .ar, context: LogContext(customData: [
            "orientation": UIDevice.current.orientation.rawValue
        ]))
    }
    
    // MARK: - Utility Methods
    
    private func describeConfiguration(_ options: ARConfigurationOptions) -> [String: Any] {
        return [
            "plane_detection": String(describing: options.planeDetection),
            "scene_reconstruction": String(describing: options.sceneReconstruction),
            "environment_texturing": String(describing: options.environmentTexturing),
            "light_estimation": options.isLightEstimationEnabled,
            "collaboration": options.isCollaborationEnabled,
            "max_tracked_images": options.maximumNumberOfTrackedImages
        ]
    }
}

// MARK: - ARSessionDelegate
extension ARSessionManager: ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async {
            let previousState = self.trackingState
            self.trackingState = frame.camera.trackingState
            
            // Handle tracking state changes
            self.handleTrackingStateChange(from: previousState, to: frame.camera.trackingState)
            
            // Update session state based on tracking
            if self.sessionState == .ready || self.sessionState == .initializing {
                self.sessionState = .running
            }
        }
    }
    
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                DispatchQueue.main.async {
                    self.detectedPlanes.append(planeAnchor)
                    
                    // Notify about plane detection
                    NotificationCenter.default.post(
                        name: .arPlaneDetected,
                        object: planeAnchor,
                        userInfo: ["plane_type": planeAnchor.alignment.rawValue]
                    )
                    
                    logDebug("AR plane detected", category: .ar, context: LogContext(customData: [
                        "plane_id": planeAnchor.identifier.uuidString,
                        "plane_type": planeAnchor.alignment.rawValue,
                        "total_planes": self.detectedPlanes.count
                    ]))
                }
            }
        }
    }
    
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                DispatchQueue.main.async {
                    // Update existing plane anchor
                    if let index = self.detectedPlanes.firstIndex(where: { $0.identifier == planeAnchor.identifier }) {
                        self.detectedPlanes[index] = planeAnchor
                    }
                }
            }
        }
    }
    
    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                DispatchQueue.main.async {
                    self.detectedPlanes.removeAll { $0.identifier == planeAnchor.identifier }
                    
                    logDebug("AR plane removed", category: .ar, context: LogContext(customData: [
                        "plane_id": planeAnchor.identifier.uuidString,
                        "remaining_planes": self.detectedPlanes.count
                    ]))
                }
            }
        }
    }
    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.sessionError = error
            self.sessionState = .failed
            
            logError("AR session failed: \(error.localizedDescription)", category: .ar, context: LogContext(customData: [
                "error_code": (error as NSError).code,
                "error_domain": (error as NSError).domain,
                "tracking_state": self.trackingState.description,
                "restart_attempts": self.sessionRestartAttempts
            ]))
            
            self.handleARConfigurationError(error)
        }
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.sessionState = .interrupted
            self.interruptionReason = "Session was interrupted"
            self.hideCoaching()
            
            logWarning("AR session interrupted", category: .ar, context: LogContext(customData: [
                "tracking_state": self.trackingState.description,
                "plane_count": self.detectedPlanes.count
            ]))
            
            NotificationCenter.default.post(name: .arSessionStateChanged, object: self.sessionState)
        }
    }
    
    public func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            self.sessionState = .ready
            self.interruptionReason = nil
            
            logInfo("AR session interruption ended", category: .ar)
            
            // Try to resume with recovery
            self.resumeSession()
            
            // Show coaching if needed
            if self.shouldShowCoachingForCurrentState() {
                self.showCoaching()
            }
            
            NotificationCenter.default.post(name: .arSessionStateChanged, object: self.sessionState)
        }
    }
    
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async {
            let previousState = self.trackingState
            self.trackingState = camera.trackingState
            
            self.handleTrackingStateChange(from: previousState, to: camera.trackingState)
            
            NotificationCenter.default.post(
                name: .arTrackingQualityChanged,
                object: self.trackingQuality,
                userInfo: ["previous_quality": self.trackingQuality]
            )
        }
    }
    
    public func session(_ session: ARSession, didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer) {
        // Handle audio data if needed for future features
    }
    
    private func handleTrackingStateChange(from previousState: ARCamera.TrackingState, to newState: ARCamera.TrackingState) {
        // Update session state based on tracking changes
        switch newState {
        case .notAvailable:
            if sessionState == .running {
                sessionState = .interrupted
                interruptionReason = "Tracking not available"
            }
            
        case .limited(let reason):
            handleLimitedTrackingReason(reason)
            
            // Show coaching for limited tracking if appropriate
            if sessionState == .running && shouldShowCoachingForCurrentState() {
                showCoaching()
            }
            
        case .normal:
            // Resume normal operation
            if sessionState == .interrupted || sessionState == .relocalizating {
                sessionState = .running
                interruptionReason = nil
            }
            
            // Clear any tracking-related errors
            if let lastError = lastKnownError as? ARError {
                switch lastError {
                case .trackingLost, .insufficientFeatures:
                    lastKnownError = nil
                default:
                    break
                }
            }
        }
    }
    
    private func handleLimitedTrackingReason(_ reason: ARCamera.TrackingState.Reason) {
        let arError: ARError?
        let shouldShowError: Bool
        
        switch reason {
        case .excessiveMotion:
            arError = nil // Don't treat as error, just show coaching
            shouldShowError = false
            
        case .insufficientFeatures:
            arError = ARError.insufficientFeatures
            shouldShowError = true
            
        case .initializing:
            sessionState = .initializing
            arError = nil
            shouldShowError = false
            
        case .relocalizing:
            sessionState = .relocalizating
            arError = nil
            shouldShowError = false
            
        @unknown default:
            arError = ARError.trackingLost
            shouldShowError = true
        }
        
        if let error = arError, shouldShowError {
            lastKnownError = error
            
            let context = [
                "tracking_reason": reason.localizedDescription,
                "session_state": sessionState.rawValue,
                "plane_count": detectedPlanes.count
            ]
            
            errorManager.reportError(error, context: context)
        }
        
        logDebug("AR tracking limited", category: .ar, context: LogContext(customData: [
            "reason": reason.localizedDescription,
            "session_state": sessionState.rawValue,
            "should_show_coaching": shouldShowCoachingForCurrentState()
        ]))
    }
}

// MARK: - ARCoachingOverlayViewDelegate
extension ARSessionManager: ARCoachingOverlayViewDelegate {
    public func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        logInfo("AR coaching overlay will activate", category: .ar, context: LogContext(customData: [
            "tracking_quality": trackingQuality.rawValue,
            "session_state": sessionState.rawValue
        ]))
    }
    
    public func coachingOverlayViewDidActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        DispatchQueue.main.async {
            self.isCoachingActive = true
            self.shouldShowCoaching = true
        }
        
        logInfo("AR coaching overlay activated", category: .ar)
    }
    
    public func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        DispatchQueue.main.async {
            self.isCoachingActive = false
            self.shouldShowCoaching = false
            
            // Update tracking quality after coaching
            self.updateTrackingQuality()
        }
        
        logInfo("AR coaching overlay deactivated", category: .ar, context: LogContext(customData: [
            "final_tracking_quality": trackingQuality.rawValue,
            "plane_count": detectedPlanes.count
        ]))
    }
    
    public func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        logInfo("AR coaching requested session reset", category: .ar)
        resetSession()
    }
}

// MARK: - AR Session Metrics
public struct ARSessionMetrics {
    var sessionDuration: TimeInterval = 0
    var trackingQuality: ARTrackingQuality = .unavailable
    var planeCount: Int = 0
    var trackingStateChanges: Int = 0
    var updateTime: Date = Date()
    var averageTrackingQuality: Double {
        return trackingQuality.score
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let arFallbackModeActivated = Notification.Name("arFallbackModeActivated")
    static let arFallbackModeDeactivated = Notification.Name("arFallbackModeDeactivated")
    static let arTrackingQualityChanged = Notification.Name("arTrackingQualityChanged")
    static let arPlaneDetected = Notification.Name("arPlaneDetected")
    static let arSessionStateChanged = Notification.Name("arSessionStateChanged")
    static let restartARSession = Notification.Name("restartARSession")
    static let enableTwoDimensionalMode = Notification.Name("enableTwoDimensionalMode")
    static let startGyroscopeTracking = Notification.Name("startGyroscopeTracking")
    static let enableManualMeasurement = Notification.Name("enableManualMeasurement")
    static let disableARFeatures = Notification.Name("disableARFeatures")
}

// MARK: - ARCamera Extensions
extension ARCamera.TrackingState {
    var description: String {
        switch self {
        case .notAvailable:
            return "notAvailable"
        case .normal:
            return "normal"
        case .limited(let reason):
            return "limited(\(reason.localizedDescription))"
        }
    }
}

extension ARCamera.TrackingState.Reason {
    var localizedDescription: String {
        switch self {
        case .excessiveMotion:
            return "excessiveMotion"
        case .insufficientFeatures:
            return "insufficientFeatures"
        case .initializing:
            return "initializing"
        case .relocalizing:
            return "relocalizing"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - AR Session Debugging and Diagnostics
public class ARSessionDiagnostics {
    private let sessionManager: ARSessionManager
    private var diagnosticsData: [String: Any] = [:]
    
    public init(sessionManager: ARSessionManager) {
        self.sessionManager = sessionManager
    }
    
    public func generateDiagnosticsReport() -> ARDiagnosticsReport {
        let session = sessionManager.session
        let arView = sessionManager.arView
        
        // Collect system information
        let systemInfo = collectSystemInfo()
        
        // Collect AR capabilities
        let arCapabilities = collectARCapabilities()
        
        // Collect session metrics
        let sessionMetrics = collectSessionMetrics()
        
        // Collect tracking information
        let trackingInfo = collectTrackingInfo()
        
        // Collect performance metrics
        let performanceMetrics = collectPerformanceMetrics()
        
        return ARDiagnosticsReport(
            timestamp: Date(),
            systemInfo: systemInfo,
            arCapabilities: arCapabilities,
            sessionMetrics: sessionMetrics,
            trackingInfo: trackingInfo,
            performanceMetrics: performanceMetrics,
            detectedIssues: analyzeIssues()
        )
    }
    
    private func collectSystemInfo() -> [String: Any] {
        let device = UIDevice.current
        return [
            "device_model": device.model,
            "device_name": device.name,
            "system_name": device.systemName,
            "system_version": device.systemVersion,
            "is_ar_supported": ARWorldTrackingConfiguration.isSupported,
            "memory_usage": getCurrentMemoryUsage()
        ]
    }
    
    private func collectARCapabilities() -> [String: Any] {
        let config = ARWorldTrackingConfiguration()
        
        return [
            "world_tracking_supported": ARWorldTrackingConfiguration.isSupported,
            "scene_reconstruction_supported": ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification),
            "user_face_tracking_supported": ARFaceTrackingConfiguration.isSupported,
            "frame_semantics_supported": ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]),
            "plane_detection_supported": true,
            "environment_texturing_supported": true,
            "collaboration_supported": true,
            "max_tracked_images": config.maximumNumberOfTrackedImages
        ]
    }
    
    private func collectSessionMetrics() -> [String: Any] {
        let metrics = sessionManager.sessionMetrics
        
        return [
            "session_duration": metrics.sessionDuration,
            "tracking_quality": metrics.trackingQuality.rawValue,
            "plane_count": metrics.planeCount,
            "tracking_state_changes": metrics.trackingStateChanges,
            "average_tracking_quality": metrics.averageTrackingQuality,
            "session_state": sessionManager.sessionState.rawValue,
            "is_session_running": sessionManager.isSessionRunning
        ]
    }
    
    private func collectTrackingInfo() -> [String: Any] {
        return [
            "current_tracking_state": sessionManager.trackingState.description,
            "tracking_quality": sessionManager.trackingQuality.rawValue,
            "tracking_quality_history": sessionManager.trackingQualityHistory.map { $0.rawValue },
            "detected_planes": sessionManager.detectedPlanes.map { plane in
                [
                    "id": plane.identifier.uuidString,
                    "alignment": plane.alignment.rawValue,
                    "extent": [plane.extent.x, plane.extent.z],
                    "center": [plane.center.x, plane.center.y, plane.center.z]
                ]
            },
            "is_coaching_active": sessionManager.isCoachingActive
        ]
    }
    
    private func collectPerformanceMetrics() -> [String: Any] {
        return [
            "memory_usage_mb": getCurrentMemoryUsage() / 1024 / 1024,
            "frame_rate": sessionManager.arView.preferredFramesPerSecond,
            "render_stats": collectRenderStats()
        ]
    }
    
    private func collectRenderStats() -> [String: Any] {
        // This would collect RealityKit render statistics if available
        return [
            "rendered_frames": 0, // Placeholder
            "dropped_frames": 0,  // Placeholder
            "average_frame_time": 0.0 // Placeholder
        ]
    }
    
    private func analyzeIssues() -> [ARDiagnosticIssue] {
        var issues: [ARDiagnosticIssue] = []
        
        // Check for tracking issues
        if sessionManager.trackingQuality == .poor || sessionManager.trackingQuality == .unavailable {
            issues.append(ARDiagnosticIssue(
                severity: .high,
                category: "Tracking",
                description: "Poor tracking quality detected",
                recommendation: "Ensure good lighting and move device slowly to scan environment"
            ))
        }
        
        // Check for plane detection issues
        if sessionManager.detectedPlanes.isEmpty && sessionManager.sessionState == .running {
            issues.append(ARDiagnosticIssue(
                severity: .medium,
                category: "Plane Detection",
                description: "No planes detected",
                recommendation: "Point camera at flat surfaces like floors or tables"
            ))
        }
        
        // Check memory usage
        let memoryUsage = getCurrentMemoryUsage() / 1024 / 1024 // MB
        if memoryUsage > 200 {
            issues.append(ARDiagnosticIssue(
                severity: .medium,
                category: "Performance",
                description: "High memory usage: \(memoryUsage)MB",
                recommendation: "Consider reducing AR session complexity or clearing cached data"
            ))
        }
        
        // Check for session errors
        if let error = sessionManager.lastKnownError {
            issues.append(ARDiagnosticIssue(
                severity: .high,
                category: "Session Error",
                description: error.userMessage,
                recommendation: error.recoveryAction?.description ?? "Restart AR session"
            ))
        }
        
        return issues
    }
    
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}

public struct ARDiagnosticsReport {
    let timestamp: Date
    let systemInfo: [String: Any]
    let arCapabilities: [String: Any]
    let sessionMetrics: [String: Any]
    let trackingInfo: [String: Any]
    let performanceMetrics: [String: Any]
    let detectedIssues: [ARDiagnosticIssue]
    
    public func export() -> Data? {
        let report: [String: Any] = [
            "timestamp": timestamp.timeIntervalSince1970,
            "system_info": systemInfo,
            "ar_capabilities": arCapabilities,
            "session_metrics": sessionMetrics,
            "tracking_info": trackingInfo,
            "performance_metrics": performanceMetrics,
            "detected_issues": detectedIssues.map { issue in
                [
                    "severity": issue.severity.rawValue,
                    "category": issue.category,
                    "description": issue.description,
                    "recommendation": issue.recommendation
                ]
            }
        ]
        
        do {
            return try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
        } catch {
            logError("Failed to export diagnostics report: \(error)", category: .ar)
            return nil
        }
    }
}

public struct ARDiagnosticIssue {
    let severity: Severity
    let category: String
    let description: String
    let recommendation: String
    
    public enum Severity: String {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }
}