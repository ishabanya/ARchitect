import Foundation
import ARKit
import RealityKit
import Combine
import simd

// MARK: - Measurement Engine
public class MeasurementEngine: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published public var currentMeasurement: Measurement?
    @Published public var activeMeasurements: [Measurement] = []
    @Published public var measurementHistory: MeasurementHistory = MeasurementHistory()
    @Published public var currentSession: MeasurementSession?
    @Published public var measurementMode: MeasurementMode = .distance
    @Published public var unitSystem: UnitSystem = .metric
    @Published public var isCapturing = false
    @Published public var captureProgress: Float = 0.0
    
    // MARK: - Private Properties
    private let sessionManager: ARSessionManager
    private let geometryCalculator = GeometryCalculator()
    private let accuracyAssessor = AccuracyAssessor()
    private let persistence = MeasurementPersistence.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var currentPoints: [MeasurementPoint] = []
    private var hitTestQueue = DispatchQueue(label: "measurement.hittest", qos: .userInteractive)
    
    // Settings
    private let maxMeasurementDistance: Float = 50.0 // 50 meters
    private let minMeasurementDistance: Float = 0.01 // 1 centimeter
    private let hitTestBuffer = 5 // Number of hit tests to average
    
    // State tracking
    private var lastTrackingQuality: ARTrackingQuality = .unavailable
    private var trackingQualityHistory: [Float] = []
    private var lightingAssessment: LightingCondition = .good
    
    public init(sessionManager: ARSessionManager) {
        self.sessionManager = sessionManager
        super.init()
        
        setupObservers()
        Task {
            await loadMeasurementHistory()
        }
        
        logInfo("Measurement engine initialized", category: .measurement, context: LogContext(customData: [
            "unit_system": unitSystem.rawValue,
            "measurement_mode": measurementMode.rawValue
        ]))
    }
    
    deinit {
        Task {
            await saveMeasurementHistory()
        }
        logInfo("Measurement engine deinitialized", category: .measurement)
    }
    
    // MARK: - Public Methods
    
    /// Start a new measurement session
    public func startMeasurementSession(name: String? = nil) {
        let sessionName = name ?? "Session \(Date().formatted(date: .abbreviated, time: .shortened))"
        currentSession = MeasurementSession(
            name: sessionName,
            preferredUnitSystem: unitSystem
        )
        
        activeMeasurements.removeAll()
        currentMeasurement = nil
        currentPoints.removeAll()
        
        logInfo("Started measurement session", category: .measurement, context: LogContext(customData: [
            "session_name": sessionName,
            "unit_system": unitSystem.rawValue
        ]))
    }
    
    /// End the current measurement session
    public func endMeasurementSession() {
        guard var session = currentSession else { return }
        
        // Add all active measurements to the session
        session.measurements = activeMeasurements
        
        // Add session to history
        measurementHistory.addSession(session)
        
        // Clear current state
        currentSession = nil
        activeMeasurements.removeAll()
        currentMeasurement = nil
        currentPoints.removeAll()
        
        // Save history
        Task {
            await saveMeasurementHistory()
        }
        
        logInfo("Ended measurement session", category: .measurement, context: LogContext(customData: [
            "session_name": session.name,
            "measurements_count": session.measurements.count
        ]))
    }
    
    /// Add a measurement point at the specified screen coordinate
    public func addMeasurementPoint(at screenPoint: CGPoint) async -> Bool {
        guard sessionManager.sessionState == .running else {
            logWarning("Cannot add measurement point: AR session not running", category: .measurement)
            return false
        }
        
        isCapturing = true
        captureProgress = 0.0
        
        defer {
            isCapturing = false
        }
        
        do {
            // Perform hit test with multiple attempts for accuracy
            let point = try await performAccurateHitTest(at: screenPoint)
            
            // Check distance constraints
            if let lastPoint = currentPoints.last {
                let distance = point.distance(to: lastPoint)
                if distance < minMeasurementDistance {
                    logWarning("Point too close to previous point", category: .measurement)
                    return false
                }
                if distance > maxMeasurementDistance {
                    logWarning("Point too far from previous point", category: .measurement)
                    return false
                }
            }
            
            // Add point to current measurement
            currentPoints.append(point)
            captureProgress = 1.0
            
            // Check if we can complete the measurement
            await checkMeasurementCompletion()
            
            logDebug("Added measurement point", category: .measurement, context: LogContext(customData: [
                "point_count": currentPoints.count,
                "position": [point.position.x, point.position.y, point.position.z],
                "tracking_quality": point.trackingQuality
            ]))
            
            return true
            
        } catch {
            logError("Failed to add measurement point: \(error)", category: .measurement)
            return false
        }
    }
    
    /// Complete the current measurement
    public func completeMeasurement(name: String? = nil) async {
        guard currentPoints.count >= measurementMode.type.minimumPoints else {
            logWarning("Not enough points to complete measurement", category: .measurement)
            return
        }
        
        do {
            let measurement = try await createMeasurement(
                type: measurementMode.type,
                points: currentPoints,
                name: name
            )
            
            // Add to active measurements
            activeMeasurements.append(measurement)
            currentMeasurement = measurement
            
            // Add to current session if active
            currentSession?.measurements.append(measurement)
            
            // Clear current points for next measurement
            currentPoints.removeAll()
            
            logInfo("Completed measurement", category: .measurement, context: LogContext(customData: [
                "measurement_id": measurement.id.uuidString,
                "type": measurement.type.rawValue,
                "value": measurement.value.formattedString,
                "accuracy": measurement.accuracy.level.rawValue
            ]))
            
        } catch {
            logError("Failed to complete measurement: \(error)", category: .measurement)
        }
    }
    
    /// Cancel the current measurement in progress
    public func cancelCurrentMeasurement() {
        currentPoints.removeAll()
        currentMeasurement = nil
        captureProgress = 0.0
        isCapturing = false
        
        logDebug("Cancelled current measurement", category: .measurement)
    }
    
    /// Delete a measurement
    public func deleteMeasurement(_ measurement: Measurement) {
        activeMeasurements.removeAll { $0.id == measurement.id }
        
        // Remove from current session
        currentSession?.measurements.removeAll { $0.id == measurement.id }
        
        // Remove from history
        for sessionIndex in measurementHistory.sessions.indices {
            measurementHistory.sessions[sessionIndex].measurements.removeAll { $0.id == measurement.id }
        }
        
        Task {
            await saveMeasurementHistory()
        }
        
        logInfo("Deleted measurement", category: .measurement, context: LogContext(customData: [
            "measurement_id": measurement.id.uuidString
        ]))
    }
    
    /// Update measurement visibility
    public func updateMeasurementVisibility(_ measurement: Measurement, isVisible: Bool) {
        if let index = activeMeasurements.firstIndex(where: { $0.id == measurement.id }) {
            activeMeasurements[index].isVisible = isVisible
        }
        
        // Update in current session
        if let sessionIndex = currentSession?.measurements.firstIndex(where: { $0.id == measurement.id }) {
            currentSession?.measurements[sessionIndex].isVisible = isVisible
        }
        
        // Update in history
        for sessionIndex in measurementHistory.sessions.indices {
            if let measurementIndex = measurementHistory.sessions[sessionIndex].measurements.firstIndex(where: { $0.id == measurement.id }) {
                measurementHistory.sessions[sessionIndex].measurements[measurementIndex].isVisible = isVisible
            }
        }
        
        Task {
            await saveMeasurementHistory()
        }
    }
    
    /// Change unit system and update all measurements
    public func changeUnitSystem(_ newSystem: UnitSystem) {
        unitSystem = newSystem
        
        // Update current session preference
        currentSession?.preferredUnitSystem = newSystem
        
        // Update all active measurements (they convert on-demand, no need to modify)
        
        logInfo("Changed unit system", category: .measurement, context: LogContext(customData: [
            "new_system": newSystem.rawValue
        ]))
    }
    
    /// Get measurement at screen point (for editing/selection)
    public func getMeasurement(at screenPoint: CGPoint, tolerance: Float = 0.1) -> Measurement? {
        // This would involve hit testing against measurement geometry
        // For now, return nil as this is a complex implementation
        return nil
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observe AR session state changes
        sessionManager.$sessionState
            .sink { [weak self] state in
                self?.handleSessionStateChange(state)
            }
            .store(in: &cancellables)
        
        // Observe tracking quality changes
        sessionManager.$trackingQuality
            .sink { [weak self] quality in
                self?.handleTrackingQualityChange(quality)
            }
            .store(in: &cancellables)
        
        // Observe detected planes for surface alignment
        sessionManager.$detectedPlanes
            .sink { [weak self] planes in
                self?.handleDetectedPlanesChange(planes)
            }
            .store(in: &cancellables)
    }
    
    private func performAccurateHitTest(at screenPoint: CGPoint) async throws -> MeasurementPoint {
        return try await withCheckedThrowingContinuation { continuation in
            hitTestQueue.async {
                var hitResults: [ARHitTestResult] = []
                var attempts = 0
                let maxAttempts = self.hitTestBuffer
                
                // Perform multiple hit tests for better accuracy
                while attempts < maxAttempts {
                    let results = self.sessionManager.arView.hitTest(screenPoint, types: [.existingPlaneUsingGeometry, .featurePoint])
                    if !results.isEmpty {
                        hitResults.append(results[0])
                    }
                    attempts += 1
                    
                    // Small delay between attempts
                    Thread.sleep(forTimeInterval: 0.02)
                }
                
                guard !hitResults.isEmpty else {
                    continuation.resume(throwing: MeasurementError.hitTestFailed("No surface found at screen point"))
                    return
                }
                
                // Calculate average position for better accuracy
                let averageTransform = self.calculateAverageTransform(from: hitResults)
                let position = simd_float3(averageTransform.columns.3.x, averageTransform.columns.3.y, averageTransform.columns.3.z)
                
                // Assess point quality
                let confidence = self.assessPointConfidence(from: hitResults)
                let trackingQuality = self.sessionManager.trackingQuality.score
                
                // Create measurement point
                let point = MeasurementPoint(
                    position: position,
                    worldTransform: averageTransform,
                    confidence: confidence,
                    trackingQuality: trackingQuality,
                    screenPosition: screenPoint,
                    surfaceNormal: self.calculateSurfaceNormal(from: hitResults[0]),
                    anchorID: hitResults[0].anchor?.identifier.uuidString
                )
                
                DispatchQueue.main.async {
                    continuation.resume(returning: point)
                }
            }
        }
    }
    
    private func calculateAverageTransform(from results: [ARHitTestResult]) -> simd_float4x4 {
        guard !results.isEmpty else {
            return matrix_identity_float4x4
        }
        
        var averagePosition = simd_float3(0, 0, 0)
        var averageRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        
        for result in results {
            let transform = result.worldTransform
            averagePosition += simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            // For rotation, we'd need more complex quaternion averaging
            // For simplicity, use the first result's rotation
            if result == results[0] {
                averageRotation = simd_quatf(transform)
            }
        }
        
        averagePosition /= Float(results.count)
        
        return simd_float4x4(averageRotation) * simd_float4x4(translation: averagePosition)
    }
    
    private func assessPointConfidence(from results: [ARHitTestResult]) -> Float {
        guard !results.isEmpty else { return 0.0 }
        
        // Calculate consistency of hit test results
        let positions = results.map { simd_float3($0.worldTransform.columns.3.x, $0.worldTransform.columns.3.y, $0.worldTransform.columns.3.z) }
        
        if positions.count == 1 {
            return 0.8 // Single result has moderate confidence
        }
        
        // Calculate variance
        let averagePosition = positions.reduce(simd_float3(0, 0, 0), +) / Float(positions.count)
        let variance = positions.map { simd_length_squared($0 - averagePosition) }.reduce(0, +) / Float(positions.count)
        
        // Lower variance = higher confidence
        let confidence = max(0.1, min(1.0, 1.0 - variance * 100))
        
        return confidence
    }
    
    private func calculateSurfaceNormal(from result: ARHitTestResult) -> simd_float3? {
        // Extract normal from hit test result
        if let planeAnchor = result.anchor as? ARPlaneAnchor {
            // Use plane's normal
            let transform = planeAnchor.transform
            return simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
        } else {
            // For feature points, estimate normal from nearby geometry
            // This is a simplified implementation
            let transform = result.worldTransform
            return simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
        }
    }
    
    private func checkMeasurementCompletion() async {
        let requiredPoints = measurementMode.type.minimumPoints
        
        guard currentPoints.count >= requiredPoints else { return }
        
        // For some measurement types, auto-complete when minimum points reached
        switch measurementMode.type {
        case .distance, .height:
            if currentPoints.count == 2 {
                await completeMeasurement()
            }
        case .angle:
            if currentPoints.count == 3 {
                await completeMeasurement()
            }
        default:
            // Area, volume, perimeter require manual completion
            break
        }
    }
    
    private func createMeasurement(type: MeasurementType, points: [MeasurementPoint], name: String?) async throws -> Measurement {
        guard points.count >= type.minimumPoints else {
            throw MeasurementError.insufficientPoints("Need at least \(type.minimumPoints) points for \(type.displayName)")
        }
        
        // Calculate measurement value
        let value = try await calculateMeasurementValue(type: type, points: points)
        
        // Assess accuracy
        let accuracy = assessMeasurementAccuracy(type: type, points: points, value: value)
        
        // Generate name if not provided
        let measurementName = name ?? generateMeasurementName(type: type, points: points)
        
        // Get current tracking quality
        let trackingQuality = sessionManager.trackingQuality.score
        let sessionState = sessionManager.sessionState.rawValue
        
        return Measurement(
            type: type,
            name: measurementName,
            points: points,
            value: value,
            accuracy: accuracy,
            trackingQuality: trackingQuality,
            sessionState: sessionState
        )
    }
    
    private func calculateMeasurementValue(type: MeasurementType, points: [MeasurementPoint]) async throws -> MeasurementValue {
        switch type {
        case .distance:
            return try geometryCalculator.calculateDistance(from: points[0], to: points[1], unitSystem: unitSystem)
            
        case .height:
            return try geometryCalculator.calculateHeight(from: points[0], to: points[1], unitSystem: unitSystem)
            
        case .area:
            return try geometryCalculator.calculateArea(points: points, unitSystem: unitSystem)
            
        case .volume:
            return try geometryCalculator.calculateVolume(points: points, unitSystem: unitSystem)
            
        case .perimeter:
            return try geometryCalculator.calculatePerimeter(points: points, unitSystem: unitSystem)
            
        case .angle:
            return try geometryCalculator.calculateAngle(points: points, unitSystem: unitSystem)
        }
    }
    
    private func assessMeasurementAccuracy(type: MeasurementType, points: [MeasurementPoint], value: MeasurementValue) -> MeasurementAccuracy {
        let averageConfidence = points.map { $0.confidence }.reduce(0, +) / Float(points.count)
        let averageTrackingQuality = points.map { $0.trackingQuality }.reduce(0, +) / Float(points.count)
        
        // Calculate measurement distance for accuracy assessment
        let measurementDistance = points.count >= 2 ? points[0].distance(to: points[1]) : 1.0
        
        return MeasurementAccuracy.assess(
            trackingQuality: averageTrackingQuality,
            distance: measurementDistance,
            pointConfidence: averageConfidence,
            lightingConditions: lightingAssessment
        )
    }
    
    private func generateMeasurementName(type: MeasurementType, points: [MeasurementPoint]) -> String {
        let timestamp = Date().formatted(date: .omitted, time: .shortened)
        return "\(type.displayName) \(timestamp)"
    }
    
    // MARK: - Event Handlers
    
    private func handleSessionStateChange(_ state: ARSessionState) {
        if state != .running && isCapturing {
            cancelCurrentMeasurement()
        }
    }
    
    private func handleTrackingQualityChange(_ quality: ARTrackingQuality) {
        lastTrackingQuality = quality
        
        // Track quality history for assessment
        trackingQualityHistory.append(quality.score)
        if trackingQualityHistory.count > 10 {
            trackingQualityHistory.removeFirst()
        }
        
        // Update lighting assessment based on tracking quality changes
        updateLightingAssessment()
    }
    
    private func handleDetectedPlanesChange(_ planes: [ARPlaneAnchor]) {
        // Plane changes could affect measurement accuracy
    }
    
    private func updateLightingAssessment() {
        // Simple heuristic based on tracking quality consistency
        let recentQuality = trackingQualityHistory.suffix(5)
        let averageQuality = recentQuality.reduce(0, +) / Float(recentQuality.count)
        let variance = recentQuality.map { pow($0 - averageQuality, 2) }.reduce(0, +) / Float(recentQuality.count)
        
        if averageQuality > 0.8 && variance < 0.1 {
            lightingAssessment = .excellent
        } else if averageQuality > 0.6 && variance < 0.2 {
            lightingAssessment = .good
        } else if averageQuality > 0.4 {
            lightingAssessment = .fair
        } else {
            lightingAssessment = .poor
        }
    }
    
    // MARK: - Persistence
    
    private func loadMeasurementHistory() async {
        do {
            measurementHistory = try await persistence.loadMeasurementHistory()
            logDebug("Loaded measurement history", category: .measurement, context: LogContext(customData: [
                "sessions_count": measurementHistory.sessions.count,
                "total_measurements": measurementHistory.allMeasurements.count
            ]))
        } catch {
            logError("Failed to load measurement history: \(error)", category: .measurement)
            measurementHistory = MeasurementHistory()
        }
    }
    
    private func saveMeasurementHistory() async {
        do {
            try await persistence.saveMeasurementHistory(measurementHistory)
            logDebug("Saved measurement history", category: .measurement, context: LogContext(customData: [
                "sessions_count": measurementHistory.sessions.count,
                "total_measurements": measurementHistory.allMeasurements.count
            ]))
        } catch {
            logError("Failed to save measurement history: \(error)", category: .measurement)
        }
    }
    
    // MARK: - Export/Import Methods
    
    /// Export measurement history to a file
    public func exportMeasurementHistory(format: ExportFormat = .json) async throws -> URL {
        return try await persistence.exportMeasurementHistory(measurementHistory, format: format)
    }
    
    /// Import measurement history from a file
    public func importMeasurementHistory(from url: URL, mergeWithExisting: Bool = true) async throws {
        let importedHistory = try await persistence.importMeasurementHistory(from: url)
        
        if mergeWithExisting {
            // Merge imported sessions with existing ones
            for session in importedHistory.sessions {
                measurementHistory.addSession(session)
            }
        } else {
            // Replace existing history
            measurementHistory = importedHistory
        }
        
        await saveMeasurementHistory()
        
        logInfo("Imported measurement history", category: .measurement, context: LogContext(customData: [
            "imported_sessions": importedHistory.sessions.count,
            "merged_with_existing": mergeWithExisting,
            "total_sessions": measurementHistory.sessions.count
        ]))
    }
    
    /// Create a backup of current measurement history
    public func createBackup() async throws -> URL {
        return try await persistence.createBackup(measurementHistory)
    }
    
    /// Get available backups
    public func getAvailableBackups() async throws -> [BackupInfo] {
        return try await persistence.getAvailableBackups()
    }
    
    /// Restore from a backup
    public func restoreFromBackup(_ backup: BackupInfo) async throws {
        measurementHistory = try await persistence.restoreFromBackup(backup)
        
        logInfo("Restored measurement history from backup", category: .measurement, context: LogContext(customData: [
            "backup_filename": backup.filename,
            "sessions_count": measurementHistory.sessions.count
        ]))
    }
}

// MARK: - Measurement Mode

public enum MeasurementMode: String, CaseIterable {
    case distance = "distance"
    case area = "area"
    case volume = "volume"
    case angle = "angle"
    case height = "height"
    case perimeter = "perimeter"
    
    public var type: MeasurementType {
        return MeasurementType(rawValue: rawValue) ?? .distance
    }
    
    public var displayName: String {
        return type.displayName
    }
    
    public var icon: String {
        return type.icon
    }
    
    public var instructions: String {
        switch self {
        case .distance:
            return "Tap two points to measure distance"
        case .area:
            return "Tap points to outline an area, then tap 'Complete'"
        case .volume:
            return "Tap points to define a volume, then tap 'Complete'"
        case .angle:
            return "Tap three points to measure angle"
        case .height:
            return "Tap bottom and top points to measure height"
        case .perimeter:
            return "Tap points around the perimeter, then tap 'Complete'"
        }
    }
}

// MARK: - Error Types

public enum MeasurementError: Error, LocalizedError {
    case hitTestFailed(String)
    case insufficientPoints(String)
    case invalidGeometry(String)
    case calculationFailed(String)
    case trackingLost
    case distanceOutOfRange
    
    public var errorDescription: String? {
        switch self {
        case .hitTestFailed(let reason):
            return "Hit test failed: \(reason)"
        case .insufficientPoints(let reason):
            return "Insufficient points: \(reason)"
        case .invalidGeometry(let reason):
            return "Invalid geometry: \(reason)"
        case .calculationFailed(let reason):
            return "Calculation failed: \(reason)"
        case .trackingLost:
            return "AR tracking lost"
        case .distanceOutOfRange:
            return "Measurement distance out of range"
        }
    }
}