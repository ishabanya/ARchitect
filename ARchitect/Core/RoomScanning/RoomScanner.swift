import Foundation
import ARKit
import RealityKit
import Combine
import simd

// MARK: - Room Scanner
public class RoomScanner: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published public var scanState: ScanState = .notStarted
    @Published public var scanProgress: ScanProgress = ScanProgress()
    @Published public var currentScan: RoomScan?
    @Published public var detectedPlanes: [DetectedPlane] = []
    @Published public var mergedPlanes: [MergedPlane] = []
    @Published public var roomDimensions: RoomDimensions?
    @Published public var scanQuality: ScanQuality?
    @Published public var scanIssues: [ScanIssue] = []
    @Published public var isScanning: Bool = false
    
    // MARK: - Private Properties
    private let sessionManager: ARSessionManager
    private let planeMerger = PlaneMerger()
    private let dimensionCalculator = RoomDimensionCalculator()
    private let qualityAssessor = ScanQualityAssessor()
    private let scanSettings: ScanSettings
    
    private var scanStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var scanTimer: Timer?
    private var progressUpdateTimer: Timer?
    private var frameCount = 0
    private var trackingQualitySum: Float = 0
    private var lastPlaneUpdate = Date()
    
    // Scanning state
    private var expectedFloorArea: Float = 0
    private var detectedFloorArea: Float = 0
    private var expectedWallCount = 4 // Default rectangular room
    private var detectedWallCount = 0
    
    // Performance monitoring
    private var peakMemoryUsage = 0
    
    // MARK: - Initialization
    public init(sessionManager: ARSessionManager, settings: ScanSettings = .default) {
        self.sessionManager = sessionManager
        self.scanSettings = settings
        super.init()
        
        setupObservers()
        setupScanning()
        
        logInfo("Room scanner initialized", category: .ar, context: LogContext(customData: [
            "quality_mode": settings.qualityMode.rawValue,
            "timeout_duration": settings.timeoutDuration
        ]))
    }
    
    deinit {
        stopScanning()
        scanTimer?.invalidate()
        progressUpdateTimer?.invalidate()
        
        logInfo("Room scanner deinitialized", category: .ar)
    }
    
    // MARK: - Public Methods
    
    /// Start the room scanning process
    public func startScanning(roomName: String = "Room \(Date().timeIntervalSince1970)") {
        guard !isScanning else {
            logWarning("Attempted to start scanning while already scanning", category: .ar)
            return
        }
        
        logInfo("Starting room scan", category: .ar, context: LogContext(customData: [
            "room_name": roomName,
            "quality_mode": scanSettings.qualityMode.rawValue
        ]))
        
        // Track room scan start
        AnalyticsManager.shared.trackFeatureUsage(.roomScanStart, parameters: [
            "room_name": roomName,
            "quality_mode": scanSettings.qualityMode.rawValue,
            "ar_tracking_state": sessionManager.trackingState.rawValue,
            "device_model": UIDevice.current.model
        ])
        
        // Reset state
        resetScanState()
        
        // Configure AR session for room scanning
        configureARSession()
        
        // Start scanning
        isScanning = true
        scanState = .initializing
        scanStartTime = Date()
        
        // Start timers
        startScanTimer()
        startProgressUpdateTimer()
        
        // Initialize progress
        scanProgress = ScanProgress(
            currentPhase: .floorDetection,
            scanDuration: 0
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.scanState = .scanning
        }
    }
    
    /// Stop the current scanning process
    public func stopScanning() {
        guard isScanning else { return }
        
        let scanDuration = scanStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        logInfo("Stopping room scan", category: .ar, context: LogContext(customData: [
            "scan_duration": scanProgress.scanDuration,
            "detected_planes": detectedPlanes.count,
            "completion": scanProgress.completionPercentage
        ]))
        
        // Track room scan completion
        AnalyticsManager.shared.trackFeatureUsage(.roomScanComplete, parameters: [
            "scan_duration": scanDuration,
            "detected_planes": detectedPlanes.count,
            "completion_percentage": scanProgress.completionPercentage,
            "quality_score": scanQuality?.overallScore ?? 0,
            "detected_walls": detectedWallCount,
            "floor_area": detectedFloorArea,
            "scan_issues": scanIssues.count
        ])
        
        // Track scan processing time
        let processingStartTime = Date()
        
        isScanning = false
        scanState = .processing
        
        // Stop timers
        scanTimer?.invalidate()
        progressUpdateTimer?.invalidate()
        
        // Process final scan
        processFinalScan()
        
        // Track processing time
        let processingTime = Date().timeIntervalSince(processingStartTime)
        AnalyticsManager.shared.trackPerformanceMetric(.scanProcessingTime, value: processingTime, parameters: [
            "plane_count": detectedPlanes.count,
            "room_complexity": detectedWallCount > 6 ? "complex" : "simple"
        ])
    }
    
    /// Cancel the current scanning process
    public func cancelScanning() {
        guard isScanning else { return }
        
        logInfo("Cancelling room scan", category: .ar)
        
        isScanning = false
        scanState = .cancelled
        
        // Stop timers
        scanTimer?.invalidate()
        progressUpdateTimer?.invalidate()
        
        // Reset state
        resetScanState()
    }
    
    /// Get the current scan as a RoomScan object
    public func getCurrentScan(name: String) -> RoomScan? {
        guard let startTime = scanStartTime,
              let dimensions = roomDimensions,
              let quality = scanQuality else {
            return nil
        }
        
        let roomBounds = RoomBounds(from: mergedPlanes)
        let metadata = ScanMetadata(
            startTime: startTime,
            endTime: Date(),
            totalFrames: frameCount,
            averageTrackingQuality: frameCount > 0 ? trackingQualitySum / Float(frameCount) : 0,
            memoryUsage: peakMemoryUsage,
            scanSettings: scanSettings
        )
        
        return RoomScan(
            name: name,
            scanDuration: Date().timeIntervalSince(startTime),
            scanQuality: quality,
            roomDimensions: dimensions,
            detectedPlanes: detectedPlanes,
            mergedPlanes: mergedPlanes,
            roomBounds: roomBounds,
            scanMetadata: metadata
        )
    }
    
    // MARK: - Private Setup Methods
    
    private func setupObservers() {
        // Observe AR session state changes
        sessionManager.$sessionState
            .sink { [weak self] state in
                self?.handleARSessionStateChange(state)
            }
            .store(in: &cancellables)
        
        // Observe tracking quality changes
        sessionManager.$trackingQuality
            .sink { [weak self] quality in
                self?.handleTrackingQualityChange(quality)
            }
            .store(in: &cancellables)
        
        // Observe detected planes from AR session
        sessionManager.$detectedPlanes
            .sink { [weak self] arPlanes in
                self?.handleDetectedPlanes(arPlanes)
            }
            .store(in: &cancellables)
    }
    
    private func setupScanning() {
        // Configure plane merger settings
        planeMerger.configure(
            mergingThreshold: scanSettings.mergingThreshold,
            minPlaneArea: scanSettings.minPlaneArea
        )
    }
    
    private func configureARSession() {
        // Create optimized configuration for room scanning
        let options = ARConfigurationOptions(
            planeDetection: [.horizontal, .vertical],
            sceneReconstruction: scanSettings.qualityMode == .accurate ? .meshWithClassification : .mesh,
            environmentTexturing: .automatic,
            frameSemantics: scanSettings.qualityMode == .accurate ? [.sceneDepth, .smoothedSceneDepth] : [],
            providesAudioData: false,
            isLightEstimationEnabled: true,
            isCollaborationEnabled: false,
            maximumNumberOfTrackedImages: 0,
            detectionImages: nil
        )
        
        sessionManager.updateConfiguration(options)
    }
    
    private func startScanTimer() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkScanTimeout()
        }
    }
    
    private func startProgressUpdateTimer() {
        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleARSessionStateChange(_ state: ARSessionState) {
        switch state {
        case .failed, .unavailable:
            if isScanning {
                failScanning(reason: "AR session failed")
            }
        case .interrupted:
            if isScanning {
                pauseScanning()
            }
        case .running:
            if scanState == .initializing {
                resumeScanning()
            }
        default:
            break
        }
    }
    
    private func handleTrackingQualityChange(_ quality: ARTrackingQuality) {
        guard isScanning else { return }
        
        // Track quality for assessment
        trackingQualitySum += quality.score
        frameCount += 1
        
        // Add issues for poor tracking
        if quality == .poor || quality == .unavailable {
            addScanIssue(
                type: .poorTracking,
                severity: .medium,
                description: "Poor tracking quality detected during scan"
            )
        }
    }
    
    private func handleDetectedPlanes(_ arPlanes: [ARPlaneAnchor]) {
        guard isScanning else { return }
        
        // Convert AR planes to DetectedPlanes
        let newDetectedPlanes = arPlanes.compactMap { anchor -> DetectedPlane? in
            guard anchor.extent.x * anchor.extent.z >= scanSettings.minPlaneArea else {
                return nil // Skip planes that are too small
            }
            
            return DetectedPlane(
                from: anchor,
                trackingQuality: sessionManager.trackingQuality.score
            )
        }
        
        // Update detected planes
        detectedPlanes = newDetectedPlanes
        lastPlaneUpdate = Date()
        
        // Merge planes if we have enough
        if detectedPlanes.count >= 2 {
            mergePlanes()
        }
        
        // Calculate dimensions if we have floor and walls
        if hasSufficientPlanes() {
            calculateRoomDimensions()
        }
        
        // Assess scan quality
        assessScanQuality()
        
        logDebug("Updated detected planes", category: .ar, context: LogContext(customData: [
            "total_planes": detectedPlanes.count,
            "horizontal_planes": detectedPlanes.filter { $0.alignment == .horizontal }.count,
            "vertical_planes": detectedPlanes.filter { $0.alignment == .vertical }.count
        ]))
    }
    
    // MARK: - Plane Processing
    
    private func mergePlanes() {
        do {
            let newMergedPlanes = try planeMerger.mergePlanes(detectedPlanes)
            
            // Update merged planes if changed
            if !newMergedPlanes.elementsEqual(mergedPlanes, by: { $0.id == $1.id }) {
                mergedPlanes = newMergedPlanes
                
                // Update counters
                updatePlaneCounters()
                
                logDebug("Merged planes updated", category: .ar, context: LogContext(customData: [
                    "merged_planes": mergedPlanes.count,
                    "floor_planes": mergedPlanes.filter { $0.type == .floor }.count,
                    "wall_planes": mergedPlanes.filter { $0.type == .wall }.count
                ]))
            }
        } catch {
            logError("Failed to merge planes: \(error)", category: .ar)
            addScanIssue(
                type: .overlappingPlanes,
                severity: .medium,
                description: "Failed to merge overlapping planes"
            )
        }
    }
    
    private func updatePlaneCounters() {
        let floorPlanes = mergedPlanes.filter { $0.type == .floor }
        let wallPlanes = mergedPlanes.filter { $0.type == .wall }
        
        detectedFloorArea = floorPlanes.reduce(0) { $0 + $1.area }
        detectedWallCount = wallPlanes.count
        
        // Estimate expected floor area based on detected walls
        if detectedWallCount >= 2 {
            estimateExpectedFloorArea()
        }
    }
    
    private func estimateExpectedFloorArea() {
        // Simple rectangular room estimation
        // This is a basic implementation - could be enhanced for complex room shapes
        let wallPlanes = mergedPlanes.filter { $0.type == .wall }
        
        guard wallPlanes.count >= 2 else { return }
        
        // Find perpendicular walls to estimate dimensions
        var dimensions: [Float] = []
        
        for i in 0..<wallPlanes.count {
            for j in (i+1)..<wallPlanes.count {
                let wall1 = wallPlanes[i]
                let wall2 = wallPlanes[j]
                
                // Check if walls are roughly perpendicular
                let dot = simd_dot(wall1.normal, wall2.normal)
                if abs(dot) < 0.3 { // Roughly perpendicular
                    let distance = simd_distance(wall1.center, wall2.center)
                    dimensions.append(distance)
                }
            }
        }
        
        if dimensions.count >= 2 {
            dimensions.sort()
            let width = dimensions[0]
            let length = dimensions[1]
            expectedFloorArea = width * length
        }
    }
    
    // MARK: - Room Dimension Calculation
    
    private func calculateRoomDimensions() {
        do {
            let dimensions = try dimensionCalculator.calculateDimensions(from: mergedPlanes)
            roomDimensions = dimensions
            
            logDebug("Room dimensions calculated", category: .ar, context: LogContext(customData: [
                "width": dimensions.width,
                "length": dimensions.length,
                "height": dimensions.height,
                "area": dimensions.area,
                "confidence": dimensions.confidence
            ]))
        } catch {
            logError("Failed to calculate room dimensions: \(error)", category: .ar)
            addScanIssue(
                type: .unstableGeometry,
                severity: .medium,
                description: "Unable to calculate accurate room dimensions"
            )
        }
    }
    
    // MARK: - Quality Assessment
    
    private func assessScanQuality() {
        let quality = qualityAssessor.assessQuality(
            detectedPlanes: detectedPlanes,
            mergedPlanes: mergedPlanes,
            roomDimensions: roomDimensions,
            scanDuration: scanProgress.scanDuration,
            trackingQuality: frameCount > 0 ? trackingQualitySum / Float(frameCount) : 0,
            issues: scanIssues
        )
        
        scanQuality = quality
    }
    
    // MARK: - Progress Management
    
    private func updateProgress() {
        guard isScanning, let startTime = scanStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        let floorCoverage = expectedFloorArea > 0 ? min(detectedFloorArea / expectedFloorArea, 1.0) : 0.0
        let wallCoverage = Float(detectedWallCount) / Float(expectedWallCount)
        
        // Determine current phase
        let phase = determineCurrentPhase()
        
        // Calculate completion percentage
        let completion = calculateCompletionPercentage(phase: phase, floorCoverage: floorCoverage, wallCoverage: wallCoverage)
        
        // Estimate time remaining
        let timeRemaining = estimateTimeRemaining(completion: completion, duration: duration)
        
        scanProgress = ScanProgress(
            completionPercentage: completion,
            detectedPlanes: detectedPlanes.count,
            floorCoverage: floorCoverage,
            wallCoverage: wallCoverage,
            scanDuration: duration,
            currentPhase: phase,
            estimatedTimeRemaining: timeRemaining
        )
        
        // Update memory usage
        updateMemoryUsage()
    }
    
    private func determineCurrentPhase() -> ScanProgress.ScanPhase {
        let floorPlanes = mergedPlanes.filter { $0.type == .floor }
        let wallPlanes = mergedPlanes.filter { $0.type == .wall }
        
        if floorPlanes.isEmpty {
            return .floorDetection
        } else if wallPlanes.count < 2 {
            return .wallDetection
        } else if scanProgress.completionPercentage < 0.8 {
            return .detailScanning
        } else {
            return .optimization
        }
    }
    
    private func calculateCompletionPercentage(phase: ScanProgress.ScanPhase, floorCoverage: Float, wallCoverage: Float) -> Float {
        switch phase {
        case .floorDetection:
            return floorCoverage * 0.3 // Floor detection is 30% of total
        case .wallDetection:
            return 0.3 + (wallCoverage * 0.4) // Walls are 40% of total
        case .detailScanning:
            return 0.7 + (min(floorCoverage, wallCoverage) * 0.2) // Details are 20% of total
        case .optimization:
            return 0.9 + (0.1 * Float(min(scanProgress.scanDuration / 30.0, 1.0))) // Final 10%
        case .finalization:
            return 1.0
        }
    }
    
    private func estimateTimeRemaining(completion: Float, duration: TimeInterval) -> TimeInterval? {
        guard completion > 0.1 else { return nil }
        
        let estimatedTotal = duration / Double(completion)
        return max(0, estimatedTotal - duration)
    }
    
    private func updateMemoryUsage() {
        let currentUsage = getCurrentMemoryUsage()
        peakMemoryUsage = max(peakMemoryUsage, currentUsage)
    }
    
    // MARK: - Scan State Management
    
    private func resetScanState() {
        detectedPlanes.removeAll()
        mergedPlanes.removeAll()
        roomDimensions = nil
        scanQuality = nil
        scanIssues.removeAll()
        frameCount = 0
        trackingQualitySum = 0
        expectedFloorArea = 0
        detectedFloorArea = 0
        detectedWallCount = 0
        peakMemoryUsage = 0
        lastPlaneUpdate = Date()
    }
    
    private func pauseScanning() {
        // Implementation for pausing scan
        scanTimer?.invalidate()
        progressUpdateTimer?.invalidate()
    }
    
    private func resumeScanning() {
        // Implementation for resuming scan
        startScanTimer()
        startProgressUpdateTimer()
    }
    
    private func failScanning(reason: String) {
        logError("Room scan failed: \(reason)", category: .ar)
        
        isScanning = false
        scanState = .failed
        
        scanTimer?.invalidate()
        progressUpdateTimer?.invalidate()
        
        addScanIssue(
            type: .unstableGeometry,
            severity: .critical,
            description: reason
        )
    }
    
    private func processFinalScan() {
        scanState = .processing
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Final processing
            self.mergePlanes()
            self.calculateRoomDimensions()
            self.assessScanQuality()
            
            DispatchQueue.main.async {
                self.scanState = .completed
                
                logInfo("Room scan completed", category: .ar, context: LogContext(customData: [
                    "scan_duration": self.scanProgress.scanDuration,
                    "detected_planes": self.detectedPlanes.count,
                    "merged_planes": self.mergedPlanes.count,
                    "scan_quality": self.scanQuality?.overallScore ?? 0,
                    "completion": self.scanProgress.completionPercentage
                ]))
            }
        }
    }
    
    private func checkScanTimeout() {
        guard let startTime = scanStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        if duration >= scanSettings.timeoutDuration {
            logWarning("Room scan timed out", category: .ar, context: LogContext(customData: [
                "duration": duration,
                "timeout": scanSettings.timeoutDuration
            ]))
            
            stopScanning()
        }
    }
    
    // MARK: - Utility Methods
    
    private func hasSufficientPlanes() -> Bool {
        let floorPlanes = mergedPlanes.filter { $0.type == .floor }
        let wallPlanes = mergedPlanes.filter { $0.type == .wall }
        
        return !floorPlanes.isEmpty && wallPlanes.count >= 2
    }
    
    private func addScanIssue(type: ScanIssue.IssueType, severity: ScanIssue.Severity, description: String, location: simd_float3? = nil) {
        let issue = ScanIssue(
            type: type,
            severity: severity,
            description: description,
            location: location
        )
        
        // Avoid duplicate issues
        if !scanIssues.contains(where: { $0.type == type && $0.description == description }) {
            scanIssues.append(issue)
        }
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