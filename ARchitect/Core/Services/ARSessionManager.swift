import Foundation
import ARKit
import RealityKit
import Combine

class ARSessionManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var sessionError: Error?
    @Published var lastKnownError: AppErrorProtocol?
    
    private let arView: ARView
    private let session: ARSession
    private var cancellables = Set<AnyCancellable>()
    private let errorManager = ErrorManager.shared
    private let errorLogger = ErrorLogger.shared
    private var sessionRestartAttempts = 0
    private let maxRestartAttempts = 3
    
    override init() {
        self.arView = ARView(frame: .zero)
        self.session = arView.session
        super.init()
        
        setupSession()
        setupErrorHandling()
    }
    
    private func setupSession() {
        session.delegate = self
        
        // Configure AR session for room scanning
        do {
            let config = try createARConfiguration()
            session.run(config)
            isSessionRunning = true
            sessionRestartAttempts = 0
        } catch {
            handleARConfigurationError(error)
        }
    }
    
    private func setupErrorHandling() {
        // Listen for session restart notifications
        NotificationCenter.default.publisher(for: .restartARSession)
            .sink { [weak self] _ in
                self?.handleSessionRestart()
            }
            .store(in: &cancellables)
        
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
    }
    
    private func createARConfiguration() throws -> ARWorldTrackingConfiguration {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ARError.unsupportedDevice
        }
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        
        // Check for scene reconstruction support
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else {
            // Report limitation but continue
            let context = ErrorContextBuilder()
                .withFeature("ar_session")
                .withUserAction("configure_session")
                .build()
            
            errorLogger.logError(
                ARError.meshGenerationFailed,
                context: context
            )
        }
        
        config.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        
        return config
    }
    
    private func handleARConfigurationError(_ error: Error) {
        let arError: ARError
        
        if let arkitError = error as? ARKit.ARError {
            arError = arkitError.toAppError()
        } else {
            arError = ARError.sessionFailed(ARKit.ARError.Code.unsupportedConfiguration)
        }
        
        let context = ErrorContextBuilder()
            .withFeature("ar_session")
            .withUserAction("configure_session")
            .with(key: "restart_attempts", value: sessionRestartAttempts)
            .build()
        
        lastKnownError = arError
        errorManager.reportError(arError, context: context)
        isSessionRunning = false
    }
    
    private func handleSessionRestart() {
        guard sessionRestartAttempts < maxRestartAttempts else {
            let error = ARError.sessionFailed(ARKit.ARError.Code.worldTrackingFailed)
            let context = ErrorContextBuilder()
                .withFeature("ar_session")
                .withUserAction("restart_session")
                .with(key: "max_attempts_reached", value: true)
                .build()
            
            errorManager.reportError(error, context: context)
            return
        }
        
        sessionRestartAttempts += 1
        resetSession()
    }
    
    private func handleMemoryWarning() {
        // Reduce AR session quality to conserve memory
        pauseSession()
        
        let context = ErrorContextBuilder()
            .withFeature("ar_session")
            .withUserAction("handle_memory_warning")
            .with(key: "session_was_running", value: isSessionRunning)
            .build()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Try to resume with reduced settings
            self.resumeSessionWithReducedSettings()
        }
    }
    
    private func resumeSessionWithReducedSettings() {
        do {
            let config = try createReducedARConfiguration()
            session.run(config)
            isSessionRunning = true
        } catch {
            handleARConfigurationError(error)
        }
    }
    
    private func createReducedARConfiguration() throws -> ARWorldTrackingConfiguration {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ARError.unsupportedDevice
        }
        
        let config = ARWorldTrackingConfiguration()
        // Reduce plane detection to horizontal only
        config.planeDetection = [.horizontal]
        // Disable scene reconstruction to save memory
        config.sceneReconstruction = .none
        // Disable environment texturing
        config.environmentTexturing = .none
        
        return config
    }
    
    func pauseSession() {
        session.pause()
        isSessionRunning = false
    }
    
    func resumeSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.sceneReconstruction = .meshWithClassification
        
        session.run(config)
        isSessionRunning = true
    }
    
    func resetSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.sceneReconstruction = .meshWithClassification
        
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
}

// MARK: - ARSessionDelegate
extension ARSessionManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async {
            let previousState = self.trackingState
            self.trackingState = frame.camera.trackingState
            
            // Handle tracking state changes
            self.handleTrackingStateChange(from: previousState, to: frame.camera.trackingState)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.sessionError = error
            self.isSessionRunning = false
            
            let arError: ARError
            if let arkitError = error as? ARKit.ARError {
                arError = arkitError.toAppError()
            } else {
                arError = ARError.sessionFailed(ARKit.ARError.Code.unknown)
            }
            
            let context = ErrorContextBuilder()
                .withFeature("ar_session")
                .withUserAction("session_failure")
                .with(key: "underlying_error", value: error.localizedDescription)
                .with(key: "tracking_state", value: self.trackingState.description)
                .build()
            
            self.lastKnownError = arError
            self.errorManager.reportError(arError, context: context)
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.isSessionRunning = false
            
            // Log interruption for debugging
            let context = ErrorContextBuilder()
                .withFeature("ar_session")
                .withUserAction("session_interrupted")
                .with(key: "tracking_state", value: self.trackingState.description)
                .build()
            
            self.errorLogger.logError(
                ARError.trackingLost,
                context: context
            )
        }
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            // Try to resume the session
            do {
                let config = try self.createARConfiguration()
                session.run(config, options: [.resetTracking, .removeExistingAnchors])
                self.isSessionRunning = true
                self.sessionRestartAttempts = 0
                
                // Clear any previous tracking errors
                if let lastError = self.lastKnownError as? ARError,
                   case .trackingLost = lastError {
                    self.lastKnownError = nil
                }
            } catch {
                self.handleARConfigurationError(error)
            }
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async {
            self.handleTrackingStateChange(from: self.trackingState, to: camera.trackingState)
            self.trackingState = camera.trackingState
        }
    }
    
    private func handleTrackingStateChange(from previousState: ARCamera.TrackingState, to newState: ARCamera.TrackingState) {
        // Only report significant tracking issues
        switch newState {
        case .notAvailable:
            let context = ErrorContextBuilder()
                .withFeature("ar_session")
                .withUserAction("tracking_unavailable")
                .with(key: "previous_state", value: previousState.description)
                .build()
            
            let error = ARError.trackingLost
            lastKnownError = error
            errorManager.reportError(error, context: context)
            
        case .limited(let reason):
            handleLimitedTrackingReason(reason, previousState: previousState)
            
        case .normal:
            // Clear tracking errors when tracking is restored
            if let lastError = lastKnownError as? ARError,
               case .trackingLost = lastError {
                lastKnownError = nil
            }
        }
    }
    
    private func handleLimitedTrackingReason(_ reason: ARCamera.TrackingState.Reason, previousState: ARCamera.TrackingState) {
        let error: ARError
        let context = ErrorContextBuilder()
            .withFeature("ar_session")
            .withUserAction("limited_tracking")
            .with(key: "reason", value: reason.description)
            .with(key: "previous_state", value: previousState.description)
        
        switch reason {
        case .excessiveMotion:
            // Don't report excessive motion as an error, just log it
            errorLogger.logError(ARError.trackingLost, context: context.build())
            return
            
        case .insufficientFeatures:
            error = ARError.insufficientFeatures
            
        case .initializing:
            // Don't report initialization as an error
            return
            
        case .relocalizing:
            // Don't report relocalization as an error, it's expected
            return
            
        @unknown default:
            error = ARError.trackingLost
        }
        
        // Only report if this is a new issue
        if let lastError = lastKnownError as? ARError,
           lastError.errorCode == error.errorCode {
            return
        }
        
        lastKnownError = error
        errorManager.reportError(error, context: context.build())
    }
}

// MARK: - Tracking State Extensions
extension ARCamera.TrackingState {
    var description: String {
        switch self {
        case .notAvailable:
            return "notAvailable"
        case .normal:
            return "normal"
        case .limited(let reason):
            return "limited(\(reason.description))"
        }
    }
}

extension ARCamera.TrackingState.Reason {
    var description: String {
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