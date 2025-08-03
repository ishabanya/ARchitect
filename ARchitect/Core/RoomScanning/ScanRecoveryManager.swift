import Foundation
import Combine
import ARKit

// MARK: - Scan Recovery Manager
public class ScanRecoveryManager: ObservableObject {
    @Published public var recoveryState: RecoveryState = .none
    @Published public var recoveryProgress: RecoveryProgress?
    @Published public var recoveryRecommendations: [RecoveryRecommendation] = []
    @Published public var canRecover: Bool = false
    
    private let scanner: RoomScanner
    private let sessionManager: ARSessionManager
    private let qualityAssessor: ScanQualityAssessor
    
    private var recoveryTimer: Timer?
    private var monitoringCancellables = Set<AnyCancellable>()
    private var lastKnownGoodState: ScanSnapshot?
    private var recoveryAttempts = 0
    private let maxRecoveryAttempts = 3
    
    // Recovery thresholds
    private let minQualityThreshold: Float = 0.3
    private let minCompletenessThreshold: Float = 0.4
    private let trackingLossTimeout: TimeInterval = 10.0
    private let planeLossTimeout: TimeInterval = 15.0
    
    public init(scanner: RoomScanner, sessionManager: ARSessionManager) {
        self.scanner = scanner
        self.sessionManager = sessionManager
        self.qualityAssessor = ScanQualityAssessor()
        
        setupMonitoring()
        
        logInfo("Scan recovery manager initialized", category: .ar)
    }
    
    deinit {
        recoveryTimer?.invalidate()
        monitoringCancellables.removeAll()
        
        logInfo("Scan recovery manager deinitialized", category: .ar)
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring scan for potential recovery needs
    public func startMonitoring() {
        guard scanner.isScanning else { return }
        
        logDebug("Starting scan recovery monitoring", category: .ar)
        
        recoveryState = .monitoring
        recoveryAttempts = 0
        
        // Create initial snapshot
        createSnapshot()
        
        // Start monitoring timer
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkRecoveryNeeds()
        }
    }
    
    /// Stop monitoring and reset recovery state
    public func stopMonitoring() {
        logDebug("Stopping scan recovery monitoring", category: .ar)
        
        recoveryTimer?.invalidate()
        recoveryState = .none
        recoveryProgress = nil
        recoveryRecommendations.removeAll()
        canRecover = false
        lastKnownGoodState = nil
    }
    
    /// Attempt to recover from current scan issues
    public func attemptRecovery() async {
        guard canRecover && recoveryAttempts < maxRecoveryAttempts else {
            logWarning("Cannot attempt recovery: canRecover=\(canRecover), attempts=\(recoveryAttempts)", category: .ar)
            return
        }
        
        logInfo("Attempting scan recovery", category: .ar, context: LogContext(customData: [
            "attempt": recoveryAttempts + 1,
            "recovery_state": recoveryState.rawValue
        ]))
        
        recoveryAttempts += 1
        recoveryState = .recovering
        
        // Create recovery progress
        let progress = RecoveryProgress(
            phase: .analyzing,
            completionPercentage: 0.0,
            estimatedTimeRemaining: 30.0
        )
        
        await MainActor.run {
            recoveryProgress = progress
        }
        
        do {
            // Perform recovery based on identified issues
            try await performRecoveryActions()
            
            // Verify recovery success
            let success = await verifyRecoverySuccess()
            
            if success {
                await completeRecovery()
            } else {
                await failRecovery(reason: "Recovery verification failed")
            }
            
        } catch {
            await failRecovery(reason: error.localizedDescription)
        }
    }
    
    /// Get recovery suggestions for manual intervention
    public func getRecoverySuggestions() -> [RecoveryRecommendation] {
        var suggestions: [RecoveryRecommendation] = []
        
        // Analyze current scan state
        let currentQuality = scanner.scanQuality
        let issues = scanner.scanIssues
        let sessionState = sessionManager.sessionState
        let trackingQuality = sessionManager.trackingQuality
        
        // Generate suggestions based on issues
        if trackingQuality == .poor || trackingQuality == .unavailable {
            suggestions.append(RecoveryRecommendation(
                type: .improveTracking,
                priority: .high,
                title: "Improve Tracking",
                description: "Move device slowly and ensure good lighting conditions",
                estimatedTime: 15,
                actions: [
                    "Move to a well-lit area",
                    "Reduce device movement speed",
                    "Point camera at textured surfaces",
                    "Avoid reflective or featureless walls"
                ]
            ))
        }
        
        if let quality = currentQuality, quality.completeness < 0.5 {
            suggestions.append(RecoveryRecommendation(
                type: .rescanMissingSurfaces,
                priority: .high,
                title: "Scan Missing Surfaces",
                description: "Important room surfaces are missing from the scan",
                estimatedTime: 30,
                actions: [
                    "Locate and scan the floor completely",
                    "Scan each wall from corner to corner",
                    "Include ceiling if visible",
                    "Ensure overlapping coverage between surfaces"
                ]
            ))
        }
        
        if let quality = currentQuality, quality.accuracy < 0.6 {
            suggestions.append(RecoveryRecommendation(
                type: .improveAccuracy,
                priority: .medium,
                title: "Improve Scan Accuracy",
                description: "Scan accuracy can be improved with better technique",
                estimatedTime: 20,
                actions: [
                    "Hold device steady while scanning",
                    "Maintain consistent distance from surfaces",
                    "Scan surfaces multiple times from different angles",
                    "Avoid scanning furniture or obstacles"
                ]
            ))
        }
        
        if sessionState == .interrupted || sessionState == .failed {
            suggestions.append(RecoveryRecommendation(
                type: .restartSession,
                priority: .critical,
                title: "Restart AR Session",
                description: "AR session needs to be restarted due to technical issues",
                estimatedTime: 10,
                actions: [
                    "Stop current scan",
                    "Restart AR session",
                    "Resume scanning from last position",
                    "Verify tracking quality before continuing"
                ]
            ))
        }
        
        // Check for specific issue types
        let criticalIssues = issues.filter { $0.severity == .critical }
        if !criticalIssues.isEmpty {
            let issueDescriptions = criticalIssues.map { $0.description }.joined(separator: ", ")
            suggestions.append(RecoveryRecommendation(
                type: .resolveCriticalIssues,
                priority: .critical,
                title: "Resolve Critical Issues",
                description: "Critical issues must be resolved: \(issueDescriptions)",
                estimatedTime: 45,
                actions: criticalIssues.compactMap { getActionForIssue($0) }
            ))
        }
        
        return suggestions.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }
    
    // MARK: - Private Methods
    
    private func setupMonitoring() {
        // Monitor scan state changes
        scanner.$scanState
            .sink { [weak self] state in
                self?.handleScanStateChange(state)
            }
            .store(in: &monitoringCancellables)
        
        // Monitor scan quality changes
        scanner.$scanQuality
            .compactMap { $0 }
            .sink { [weak self] quality in
                self?.handleQualityChange(quality)
            }
            .store(in: &monitoringCancellables)
        
        // Monitor AR session state
        sessionManager.$sessionState
            .sink { [weak self] state in
                self?.handleSessionStateChange(state)
            }
            .store(in: &monitoringCancellables)
        
        // Monitor tracking quality
        sessionManager.$trackingQuality
            .sink { [weak self] quality in
                self?.handleTrackingQualityChange(quality)
            }
            .store(in: &monitoringCancellables)
    }
    
    private func checkRecoveryNeeds() {
        guard recoveryState == .monitoring else { return }
        
        let needsRecovery = assessRecoveryNeeds()
        
        if needsRecovery && !canRecover {
            prepareRecovery()
        } else if !needsRecovery && canRecover {
            clearRecoveryNeeds()
        }
        
        // Update recommendations
        recoveryRecommendations = getRecoverySuggestions()
    }
    
    private func assessRecoveryNeeds() -> Bool {
        // Check scan quality
        if let quality = scanner.scanQuality {
            if quality.overallScore < minQualityThreshold {
                return true
            }
            
            if quality.completeness < minCompletenessThreshold {
                return true
            }
        }
        
        // Check AR session health
        if sessionManager.sessionState == .failed || sessionManager.sessionState == .interrupted {
            return true
        }
        
        if sessionManager.trackingQuality == .unavailable {
            return true
        }
        
        // Check critical issues
        let criticalIssues = scanner.scanIssues.filter { $0.severity == .critical }
        if criticalIssues.count > 1 {
            return true
        }
        
        // Check for extended poor tracking
        if sessionManager.trackingQuality == .poor {
            // This would need to track duration of poor tracking
            return true
        }
        
        return false
    }
    
    private func prepareRecovery() {
        logInfo("Preparing scan recovery", category: .ar)
        
        canRecover = true
        recoveryState = .needsRecovery
        
        // Create snapshot of current state
        createSnapshot()
        
        // Generate recovery recommendations
        recoveryRecommendations = getRecoverySuggestions()
    }
    
    private func clearRecoveryNeeds() {
        logDebug("Clearing recovery needs", category: .ar)
        
        canRecover = false
        recoveryState = .monitoring
        recoveryRecommendations.removeAll()
    }
    
    private func createSnapshot() {
        lastKnownGoodState = ScanSnapshot(
            timestamp: Date(),
            detectedPlanes: scanner.detectedPlanes,
            mergedPlanes: scanner.mergedPlanes,
            roomDimensions: scanner.roomDimensions,
            scanQuality: scanner.scanQuality,
            sessionState: sessionManager.sessionState,
            trackingQuality: sessionManager.trackingQuality,
            scanProgress: scanner.scanProgress
        )
        
        logDebug("Created scan snapshot", category: .ar, context: LogContext(customData: [
            "detected_planes": scanner.detectedPlanes.count,
            "merged_planes": scanner.mergedPlanes.count,
            "quality_score": scanner.scanQuality?.overallScore ?? 0
        ]))
    }
    
    // MARK: - Recovery Actions
    
    private func performRecoveryActions() async throws {
        await updateRecoveryProgress(.analyzing, completion: 0.1)
        
        // Identify specific recovery actions needed
        let actions = identifyRecoveryActions()
        
        await updateRecoveryProgress(.executing, completion: 0.2)
        
        for (index, action) in actions.enumerated() {
            try await executeRecoveryAction(action)
            
            let progress = 0.2 + (0.6 * Float(index + 1) / Float(actions.count))
            await updateRecoveryProgress(.executing, completion: progress)
        }
        
        await updateRecoveryProgress(.verifying, completion: 0.9)
    }
    
    private func identifyRecoveryActions() -> [RecoveryAction] {
        var actions: [RecoveryAction] = []
        
        // Session recovery
        if sessionManager.sessionState == .failed || sessionManager.sessionState == .interrupted {
            actions.append(.restartARSession)
        }
        
        // Tracking recovery
        if sessionManager.trackingQuality == .poor || sessionManager.trackingQuality == .unavailable {
            actions.append(.improveTracking)
        }
        
        // Quality recovery
        if let quality = scanner.scanQuality {
            if quality.completeness < minCompletenessThreshold {
                actions.append(.rescanMissingSurfaces)
            }
            
            if quality.accuracy < 0.5 {
                actions.append(.recalibrateGeometry)
            }
        }
        
        // Issue-specific recovery
        let criticalIssues = scanner.scanIssues.filter { $0.severity == .critical }
        for issue in criticalIssues {
            if let action = getRecoveryActionForIssue(issue) {
                actions.append(action)
            }
        }
        
        return actions
    }
    
    private func executeRecoveryAction(_ action: RecoveryAction) async throws {
        logDebug("Executing recovery action: \(action)", category: .ar)
        
        switch action {
        case .restartARSession:
            try await restartARSession()
            
        case .improveTracking:
            try await improveTracking()
            
        case .rescanMissingSurfaces:
            try await guideMissingSurfacesScan()
            
        case .recalibrateGeometry:
            try await recalibrateGeometry()
            
        case .clearPoorQualityPlanes:
            try await clearPoorQualityPlanes()
            
        case .resetToSnapshot:
            try await resetToSnapshot()
        }
    }
    
    private func restartARSession() async throws {
        logInfo("Restarting AR session for recovery", category: .ar)
        
        // Reset session
        sessionManager.resetSession()
        
        // Wait for session to stabilize
        try await Task.sleep(for: .seconds(3))
        
        // Verify session is running
        guard sessionManager.sessionState == .running else {
            throw RecoveryError.sessionRestartFailed
        }
    }
    
    private func improveTracking() async throws {
        logInfo("Attempting to improve tracking", category: .ar)
        
        // This would involve guiding the user to better tracking conditions
        // For now, we'll simulate a delay and check if tracking improves
        
        let maxWaitTime: TimeInterval = 15.0
        let checkInterval: TimeInterval = 1.0
        var waitedTime: TimeInterval = 0
        
        while waitedTime < maxWaitTime {
            try await Task.sleep(for: .seconds(checkInterval))
            waitedTime += checkInterval
            
            if sessionManager.trackingQuality == .good || sessionManager.trackingQuality == .excellent {
                return // Tracking improved
            }
        }
        
        // If we get here, tracking didn't improve sufficiently
        logWarning("Tracking improvement attempt timed out", category: .ar)
    }
    
    private func guideMissingSurfacesScan() async throws {
        logInfo("Guiding missing surfaces rescan", category: .ar)
        
        // This would involve UI guidance to scan missing surfaces
        // For now, we'll simulate the process
        
        try await Task.sleep(for: .seconds(5))
        
        // Check if we have minimum required surfaces
        let floorPlanes = scanner.mergedPlanes.filter { $0.type == .floor }
        let wallPlanes = scanner.mergedPlanes.filter { $0.type == .wall }
        
        guard !floorPlanes.isEmpty && wallPlanes.count >= 2 else {
            throw RecoveryError.insufficientSurfaces
        }
    }
    
    private func recalibrateGeometry() async throws {
        logInfo("Recalibrating geometry", category: .ar)
        
        // This would involve re-running plane merging and dimension calculation
        // For now, we'll simulate the process
        
        try await Task.sleep(for: .seconds(3))
        
        // In a real implementation, you would:
        // 1. Re-run plane merging with adjusted parameters
        // 2. Recalculate room dimensions
        // 3. Update scan quality assessment
    }
    
    private func clearPoorQualityPlanes() async throws {
        logInfo("Clearing poor quality planes", category: .ar)
        
        // This would remove planes below quality threshold
        try await Task.sleep(for: .seconds(2))
    }
    
    private func resetToSnapshot() async throws {
        guard let snapshot = lastKnownGoodState else {
            throw RecoveryError.noSnapshotAvailable
        }
        
        logInfo("Resetting to last known good state", category: .ar)
        
        // In a real implementation, you would restore the scan state
        // from the snapshot
        
        try await Task.sleep(for: .seconds(2))
    }
    
    // MARK: - Recovery Verification
    
    private func verifyRecoverySuccess() async -> Bool {
        logDebug("Verifying recovery success", category: .ar)
        
        // Wait for systems to stabilize
        try? await Task.sleep(for: .seconds(3))
        
        // Check if recovery criteria are met
        let sessionHealthy = sessionManager.sessionState == .running && 
                           sessionManager.trackingQuality != .unavailable
        
        let qualityImproved = scanner.scanQuality?.overallScore ?? 0 >= minQualityThreshold
        
        let criticalIssuesResolved = scanner.scanIssues.filter { $0.severity == .critical }.count <= 1
        
        let recoverySuccessful = sessionHealthy && qualityImproved && criticalIssuesResolved
        
        logDebug("Recovery verification result", category: .ar, context: LogContext(customData: [
            "session_healthy": sessionHealthy,
            "quality_improved": qualityImproved,
            "critical_issues_resolved": criticalIssuesResolved,
            "overall_success": recoverySuccessful
        ]))
        
        return recoverySuccessful
    }
    
    private func completeRecovery() async {
        logInfo("Recovery completed successfully", category: .ar)
        
        await MainActor.run {
            recoveryState = .recovered
            recoveryProgress = RecoveryProgress(
                phase: .completed,
                completionPercentage: 1.0,
                estimatedTimeRemaining: 0
            )
            canRecover = false
            recoveryRecommendations.removeAll()
        }
        
        // Return to monitoring after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.recoveryState = .monitoring
            self.recoveryProgress = nil
        }
    }
    
    private func failRecovery(reason: String) async {
        logError("Recovery failed: \(reason)", category: .ar)
        
        await MainActor.run {
            recoveryState = .failed
            recoveryProgress = RecoveryProgress(
                phase: .failed,
                completionPercentage: 0.0,
                estimatedTimeRemaining: 0,
                error: reason
            )
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleScanStateChange(_ state: ScanState) {
        switch state {
        case .scanning:
            if recoveryState == .none {
                startMonitoring()
            }
        case .completed, .cancelled, .failed:
            stopMonitoring()
        default:
            break
        }
    }
    
    private func handleQualityChange(_ quality: ScanQuality) {
        // Quality changes are handled in the monitoring loop
    }
    
    private func handleSessionStateChange(_ state: ARSessionState) {
        if state == .failed || state == .interrupted {
            logWarning("AR session issue detected: \(state)", category: .ar)
        }
    }
    
    private func handleTrackingQualityChange(_ quality: ARTrackingQuality) {
        if quality == .poor || quality == .unavailable {
            logWarning("Poor tracking quality detected: \(quality)", category: .ar)
        }
    }
    
    // MARK: - Utility Methods
    
    private func updateRecoveryProgress(_ phase: RecoveryProgress.Phase, completion: Float) async {
        await MainActor.run {
            recoveryProgress = RecoveryProgress(
                phase: phase,
                completionPercentage: completion,
                estimatedTimeRemaining: (1.0 - completion) * 30.0 // Rough estimate
            )
        }
    }
    
    private func getActionForIssue(_ issue: ScanIssue) -> String? {
        switch issue.type {
        case .missingWall:
            return "Scan the missing wall completely"
        case .poorTracking:
            return "Improve lighting and move slowly"
        case .incompleteFloor:
            return "Complete the floor scan"
        case .overlappingPlanes:
            return "Avoid scanning the same area multiple times"
        case .lowLighting:
            return "Move to a better-lit area"
        case .excessiveMotion:
            return "Reduce device movement speed"
        case .occludedSurfaces:
            return "Remove obstacles blocking surfaces"
        case .unstableGeometry:
            return "Rescan with more consistent movements"
        }
    }
    
    private func getRecoveryActionForIssue(_ issue: ScanIssue) -> RecoveryAction? {
        switch issue.type {
        case .poorTracking, .excessiveMotion:
            return .improveTracking
        case .missingWall, .incompleteFloor:
            return .rescanMissingSurfaces
        case .overlappingPlanes, .unstableGeometry:
            return .clearPoorQualityPlanes
        default:
            return nil
        }
    }
}

// MARK: - Supporting Types

public enum RecoveryState: String, CaseIterable {
    case none = "none"
    case monitoring = "monitoring"
    case needsRecovery = "needs_recovery"
    case recovering = "recovering"
    case recovered = "recovered"
    case failed = "failed"
    
    public var displayName: String {
        switch self {
        case .none: return "Not Active"
        case .monitoring: return "Monitoring"
        case .needsRecovery: return "Needs Recovery"
        case .recovering: return "Recovering"
        case .recovered: return "Recovered"
        case .failed: return "Recovery Failed"
        }
    }
}

public struct RecoveryProgress {
    public let phase: Phase
    public let completionPercentage: Float
    public let estimatedTimeRemaining: TimeInterval
    public let error: String?
    
    public enum Phase: String, CaseIterable {
        case analyzing = "analyzing"
        case executing = "executing"
        case verifying = "verifying"
        case completed = "completed"
        case failed = "failed"
        
        public var displayName: String {
            switch self {
            case .analyzing: return "Analyzing Issues"
            case .executing: return "Executing Recovery"
            case .verifying: return "Verifying Results"
            case .completed: return "Recovery Complete"
            case .failed: return "Recovery Failed"
            }
        }
    }
    
    public init(phase: Phase, completionPercentage: Float, estimatedTimeRemaining: TimeInterval, error: String? = nil) {
        self.phase = phase
        self.completionPercentage = completionPercentage
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.error = error
    }
}

public struct RecoveryRecommendation: Identifiable {
    public let id = UUID()
    public let type: RecommendationType
    public let priority: Priority
    public let title: String
    public let description: String
    public let estimatedTime: TimeInterval // in seconds
    public let actions: [String]
    
    public enum RecommendationType: String, CaseIterable {
        case improveTracking = "improve_tracking"
        case rescanMissingSurfaces = "rescan_missing_surfaces"
        case improveAccuracy = "improve_accuracy"
        case restartSession = "restart_session"
        case resolveCriticalIssues = "resolve_critical_issues"
    }
    
    public enum Priority: String, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
        
        public var sortOrder: Int {
            switch self {
            case .critical: return 0
            case .high: return 1
            case .medium: return 2
            case .low: return 3
            }
        }
        
        public var color: String {
            switch self {
            case .low: return "blue"
            case .medium: return "orange"
            case .high: return "red"
            case .critical: return "purple"
            }
        }
    }
}

private enum RecoveryAction {
    case restartARSession
    case improveTracking
    case rescanMissingSurfaces
    case recalibrateGeometry
    case clearPoorQualityPlanes
    case resetToSnapshot
}

private struct ScanSnapshot {
    let timestamp: Date
    let detectedPlanes: [DetectedPlane]
    let mergedPlanes: [MergedPlane]
    let roomDimensions: RoomDimensions?
    let scanQuality: ScanQuality?
    let sessionState: ARSessionState
    let trackingQuality: ARTrackingQuality
    let scanProgress: ScanProgress
}

// MARK: - Error Types
public enum RecoveryError: Error, LocalizedError {
    case sessionRestartFailed
    case insufficientSurfaces
    case noSnapshotAvailable
    case recoveryTimeout
    case maxAttemptsReached
    
    public var errorDescription: String? {
        switch self {
        case .sessionRestartFailed:
            return "Failed to restart AR session"
        case .insufficientSurfaces:
            return "Insufficient surfaces detected for recovery"
        case .noSnapshotAvailable:
            return "No previous state available for recovery"
        case .recoveryTimeout:
            return "Recovery attempt timed out"
        case .maxAttemptsReached:
            return "Maximum recovery attempts reached"
        }
    }
}