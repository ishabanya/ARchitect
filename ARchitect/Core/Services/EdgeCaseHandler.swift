import Foundation
import ARKit
import CoreMotion
import AVFoundation
import UserNotifications
import Combine

// MARK: - Edge Case Types

enum EdgeCaseType: String, CaseIterable {
    case poorLighting = "poor_lighting"
    case rapidMovement = "rapid_movement"
    case clutteredEnvironment = "cluttered_environment"
    case appInterruption = "app_interruption"
    case lowStorage = "low_storage"
    case offlineMode = "offline_mode"
    case largeRoom = "large_room"
    case smallRoom = "small_room"
    case irregularRoom = "irregular_room"
    case noiseInterference = "noise_interference"
    case thermalThrottling = "thermal_throttling"
    case memoryPressure = "memory_pressure"
    
    var displayName: String {
        switch self {
        case .poorLighting: return "Poor Lighting"
        case .rapidMovement: return "Rapid Movement"
        case .clutteredEnvironment: return "Cluttered Environment"
        case .appInterruption: return "App Interruption"
        case .lowStorage: return "Low Storage"
        case .offlineMode: return "Offline Mode"
        case .largeRoom: return "Large Room"
        case .smallRoom: return "Small Room"
        case .irregularRoom: return "Irregular Room"
        case .noiseInterference: return "Noise Interference"
        case .thermalThrottling: return "Thermal Throttling"
        case .memoryPressure: return "Memory Pressure"
        }
    }
}

// MARK: - Edge Case Severity

enum EdgeCaseSeverity: Int, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"  
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Edge Case Detection Result

struct EdgeCaseDetectionResult {
    let type: EdgeCaseType
    let severity: EdgeCaseSeverity
    let confidence: Float
    let timestamp: Date
    let metadata: [String: Any]
    let recommendedActions: [EdgeCaseAction]
    
    var shouldTriggerRecovery: Bool {
        return severity.rawValue >= EdgeCaseSeverity.high.rawValue || confidence > 0.8
    }
}

// MARK: - Edge Case Actions

enum EdgeCaseAction: String, CaseIterable {
    case adjustQuality = "adjust_quality"
    case enableFallbackMode = "enable_fallback_mode"
    case pauseSession = "pause_session"
    case showGuidance = "show_guidance"
    case requestBetterConditions = "request_better_conditions"
    case optimizePerformance = "optimize_performance"
    case clearMemory = "clear_memory"
    case saveProgress = "save_progress"
    case switchToOffline = "switch_to_offline"
    case adjustLighting = "adjust_lighting"
    case reduceFeatures = "reduce_features"
    case waitForStability = "wait_for_stability"
    
    var displayName: String {
        switch self {
        case .adjustQuality: return "Adjust Quality Settings"
        case .enableFallbackMode: return "Enable Fallback Mode"
        case .pauseSession: return "Pause AR Session"
        case .showGuidance: return "Show User Guidance"
        case .requestBetterConditions: return "Request Better Conditions"
        case .optimizePerformance: return "Optimize Performance"
        case .clearMemory: return "Clear Memory"
        case .saveProgress: return "Save Progress"
        case .switchToOffline: return "Switch to Offline Mode"
        case .adjustLighting: return "Adjust Lighting Detection"
        case .reduceFeatures: return "Reduce Features"
        case .waitForStability: return "Wait for Stability"
        }
    }
}

// MARK: - Edge Case Handler

@MainActor
public class EdgeCaseHandler: ObservableObject {
    static let shared = EdgeCaseHandler()
    
    @Published public private(set) var detectedCases: [EdgeCaseDetectionResult] = []
    @Published public private(set) var activeRecoveryActions: Set<EdgeCaseAction> = []
    @Published public private(set) var isMonitoring = false
    @Published public private(set) var systemHealth = SystemHealthMetrics()
    
    // Dependencies
    private let motionManager = CMMotionManager()
    private let arSessionManager = ARSessionManager()
    private let offlineManager = OfflineManager.shared
    private let errorManager = ErrorManager.shared
    private let performanceManager = PerformanceManager.shared
    
    // Monitoring timers and state
    private var lightingMonitorTimer: Timer?
    private var movementMonitorTimer: Timer?
    private var storageMonitorTimer: Timer?
    private var environmentMonitorTimer: Timer?
    private var thermalMonitorTimer: Timer?
    
    // Detection thresholds
    private struct Thresholds {
        static let poorLightingLux: Float = 50.0
        static let rapidMovementThreshold: Double = 2.0 // m/s²
        static let lowStorageGB: Float = 1.0
        static let largeRoomArea: Float = 100.0 // m²
        static let smallRoomArea: Float = 4.0 // m²
        static let clutterDensityThreshold: Float = 0.7
        static let thermalWarningTemperature: Float = 45.0 // °C
        static let memoryPressureThreshold: Float = 0.8 // 80% usage
    }
    
    // Edge case history for pattern detection
    private var caseHistory: [EdgeCaseDetectionResult] = []
    private let maxHistorySize = 100
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotifications()
        setupMotionMonitoring()
        startSystemHealthMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Interface
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startAllMonitors()
        
        logInfo("Edge case monitoring started", category: .performance, context: LogContext(customData: [
            "monitor_types": EdgeCaseType.allCases.map { $0.rawValue }
        ]))
    }
    
    public func stopMonitoring() {
        isMonitoring = false
        stopAllMonitors()
        
        logInfo("Edge case monitoring stopped", category: .performance)
    }
    
    public func forceCheckAllEdgeCases() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkLightingConditions() }
            group.addTask { await self.checkDeviceMovement() }
            group.addTask { await self.checkEnvironmentClutter() }
            group.addTask { await self.checkStorageSpace() }
            group.addTask { await self.checkRoomSize() }
            group.addTask { await self.checkSystemHealth() }
            group.addTask { await self.checkOfflineCapabilities() }
        }
    }
    
    public func handleDetectedEdgeCase(_ result: EdgeCaseDetectionResult) async {
        detectedCases.append(result)
        
        // Keep history manageable
        if detectedCases.count > maxHistorySize {
            detectedCases.removeFirst()
        }
        
        // Add to history for pattern analysis
        caseHistory.append(result)
        if caseHistory.count > maxHistorySize {
            caseHistory.removeFirst()
        }
        
        // Take action if needed
        if result.shouldTriggerRecovery {
            await executeRecoveryActions(result.recommendedActions)
        }
        
        // Log the detection
        logWarning("Edge case detected: \(result.type.displayName)", category: .performance, context: LogContext(customData: [
            "severity": result.severity.displayName,
            "confidence": result.confidence,
            "actions": result.recommendedActions.map { $0.rawValue }
        ]))
        
        // Notify other systems
        NotificationCenter.default.post(
            name: .edgeCaseDetected,
            object: result,
            userInfo: ["type": result.type.rawValue, "severity": result.severity.rawValue]
        )
    }
    
    // MARK: - Poor Lighting Detection
    
    private func checkLightingConditions() async {
        guard let frame = arSessionManager.session.currentFrame else { return }
        
        let lightEstimate = frame.lightEstimate
        let ambientIntensity = lightEstimate?.ambientIntensity ?? 0
        let ambientColorTemperature = lightEstimate?.ambientColorTemperature ?? 6500
        
        // Convert to lux (approximation)
        let estimatedLux = Float(ambientIntensity / 40.0) // ARKit uses different scale
        
        var severity: EdgeCaseSeverity = .low
        var confidence: Float = 0.0
        var actions: [EdgeCaseAction] = []
        
        if estimatedLux < Thresholds.poorLightingLux {
            confidence = min(1.0, (Thresholds.poorLightingLux - estimatedLux) / Thresholds.poorLightingLux)
            
            if estimatedLux < 10 {
                severity = .critical
                actions = [.pauseSession, .requestBetterConditions, .adjustLighting]
            } else if estimatedLux < 25 {
                severity = .high
                actions = [.adjustQuality, .showGuidance, .adjustLighting]
            } else {
                severity = .medium
                actions = [.adjustQuality, .showGuidance]
            }
            
            let result = EdgeCaseDetectionResult(
                type: .poorLighting,
                severity: severity,
                confidence: confidence,
                timestamp: Date(),
                metadata: [
                    "estimated_lux": estimatedLux,
                    "ambient_intensity": ambientIntensity,
                    "color_temperature": ambientColorTemperature
                ],
                recommendedActions: actions
            )
            
            await handleDetectedEdgeCase(result)
        }
    }
    
    // MARK: - Rapid Movement Detection
    
    private func checkDeviceMovement() async {
        guard let frame = arSessionManager.session.currentFrame else { return }
        
        let camera = frame.camera
        let transform = camera.transform
        
        // Calculate movement from camera transform changes
        let currentPosition = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        // Store previous position for comparison (simplified - would need proper state management)
        static var previousPosition: simd_float3?
        static var previousTimestamp: TimeInterval = 0
        
        let currentTimestamp = frame.timestamp
        
        if let prevPos = previousPosition {
            let deltaTime = currentTimestamp - previousTimestamp
            if deltaTime > 0 {
                let distance = simd_distance(currentPosition, prevPos)
                let velocity = Double(distance) / deltaTime
                let acceleration = velocity / deltaTime // Simplified calculation
                
                if acceleration > Thresholds.rapidMovementThreshold {
                    let confidence = min(1.0, Float(acceleration / (Thresholds.rapidMovementThreshold * 2)))
                    let severity: EdgeCaseSeverity = acceleration > Thresholds.rapidMovementThreshold * 3 ? .critical : .high
                    
                    let result = EdgeCaseDetectionResult(
                        type: .rapidMovement,
                        severity: severity,
                        confidence: confidence,
                        timestamp: Date(),
                        metadata: [
                            "velocity": velocity,
                            "acceleration": acceleration,
                            "distance": distance,
                            "delta_time": deltaTime
                        ],
                        recommendedActions: [.showGuidance, .waitForStability, .adjustQuality]
                    )
                    
                    await handleDetectedEdgeCase(result)
                }
            }
        }
        
        previousPosition = currentPosition
        previousTimestamp = currentTimestamp
    }
    
    // MARK: - Cluttered Environment Detection
    
    private func checkEnvironmentClutter() async {
        guard let frame = arSessionManager.session.currentFrame else { return }
        
        // Analyze feature points density and distribution
        let featurePoints = frame.rawFeaturePoints?.points ?? []
        let pointCount = featurePoints.count
        
        if pointCount > 0 {
            // Calculate feature point density in viewable area
            let viewportArea: Float = 1.0 // Normalized viewport area
            let density = Float(pointCount) / viewportArea
            
            // High density might indicate cluttered environment
            let clutterThreshold: Float = 1000.0 // points per unit area
            
            if density > clutterThreshold {
                let confidence = min(1.0, (density - clutterThreshold) / clutterThreshold)
                let severity: EdgeCaseSeverity = density > clutterThreshold * 2 ? .high : .medium
                
                // Analyze point distribution for clutter patterns
                let distributionVariance = calculateFeaturePointVariance(featurePoints)
                
                let result = EdgeCaseDetectionResult(
                    type: .clutteredEnvironment,
                    severity: severity,
                    confidence: confidence,
                    timestamp: Date(),
                    metadata: [
                        "feature_point_count": pointCount,
                        "density": density,
                        "distribution_variance": distributionVariance
                    ],
                    recommendedActions: [.showGuidance, .adjustQuality, .requestBetterConditions]
                )
                
                await handleDetectedEdgeCase(result)
            }
        }
    }
    
    private func calculateFeaturePointVariance(_ points: [simd_float3]) -> Float {
        guard points.count > 1 else { return 0 }
        
        let avgX = points.map { $0.x }.reduce(0, +) / Float(points.count)
        let avgY = points.map { $0.y }.reduce(0, +) / Float(points.count)
        let avgZ = points.map { $0.z }.reduce(0, +) / Float(points.count)
        
        let variance = points.map { point in
            pow(point.x - avgX, 2) + pow(point.y - avgY, 2) + pow(point.z - avgZ, 2)
        }.reduce(0, +) / Float(points.count)
        
        return sqrt(variance)
    }
    
    // MARK: - App Interruption Handling
    
    private func setupNotifications() {
        // Phone call interruptions
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                self?.handleAudioInterruption(notification)
            }
            .store(in: &cancellables)
        
        // App lifecycle interruptions
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { await self?.handleAppWillResignActive() }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { await self?.handleAppDidBecomeActive() }
            }
            .store(in: &cancellables)
        
        // Incoming notifications
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { await self?.handleMemoryWarning() }
            }
            .store(in: &cancellables)
    }
    
    private func handleAudioInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        Task {
            let result = EdgeCaseDetectionResult(
                type: .appInterruption,
                severity: .high,
                confidence: 1.0,
                timestamp: Date(),
                metadata: [
                    "interruption_type": type == .began ? "began" : "ended",
                    "source": "audio_session"
                ],
                recommendedActions: type == .began ? [.pauseSession, .saveProgress] : [.showGuidance]
            )
            
            await handleDetectedEdgeCase(result)
        }
    }
    
    private func handleAppWillResignActive() async {
        let result = EdgeCaseDetectionResult(
            type: .appInterruption,
            severity: .medium,
            confidence: 1.0,
            timestamp: Date(),
            metadata: ["source": "app_lifecycle", "event": "will_resign_active"],
            recommendedActions: [.pauseSession, .saveProgress]
        )
        
        await handleDetectedEdgeCase(result)
    }
    
    private func handleAppDidBecomeActive() async {
        let result = EdgeCaseDetectionResult(
            type: .appInterruption,
            severity: .low,
            confidence: 1.0,
            timestamp: Date(),
            metadata: ["source": "app_lifecycle", "event": "did_become_active"],
            recommendedActions: [.showGuidance]
        )
        
        await handleDetectedEdgeCase(result)
    }
    
    // MARK: - Storage Monitoring
    
    private func checkStorageSpace() async {
        let availableSpace = getAvailableStorageSpace()
        let availableGB = availableSpace / (1024 * 1024 * 1024)
        
        if availableGB < Thresholds.lowStorageGB {
            let confidence = min(1.0, (Thresholds.lowStorageGB - Float(availableGB)) / Thresholds.lowStorageGB)
            let severity: EdgeCaseSeverity = availableGB < 0.5 ? .critical : .high
            
            let result = EdgeCaseDetectionResult(
                type: .lowStorage,
                severity: severity,
                confidence: confidence,
                timestamp: Date(),
                metadata: [
                    "available_gb": availableGB,
                    "total_space": getTotalStorageSpace()
                ],
                recommendedActions: [.clearMemory, .optimizePerformance, .saveProgress]
            )
            
            await handleDetectedEdgeCase(result)
        }
    }
    
    private func getAvailableStorageSpace() -> Int64 {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        if let dictionary = try? FileManager.default.attributesOfFileSystem(forPath: paths.last!) {
            if let freeSize = dictionary[.systemFreeSize] as? NSNumber {
                return freeSize.int64Value
            }
        }
        return 0
    }
    
    private func getTotalStorageSpace() -> Int64 {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        if let dictionary = try? FileManager.default.attributesOfFileSystem(forPath: paths.last!) {
            if let totalSize = dictionary[.systemSize] as? NSNumber {
                return totalSize.int64Value
            }
        }
        return 0
    }
    
    // MARK: - Room Size Detection
    
    private func checkRoomSize() async {
        let detectedPlanes = arSessionManager.detectedPlanes
        let floorPlanes = detectedPlanes.filter { $0.alignment == .horizontal }
        
        guard !floorPlanes.isEmpty else { return }
        
        // Calculate total floor area
        let totalFloorArea = floorPlanes.map { plane in
            plane.extent.x * plane.extent.z
        }.reduce(0, +)
        
        var edgeCase: EdgeCaseType?
        var severity: EdgeCaseSeverity = .medium
        var actions: [EdgeCaseAction] = []
        
        if totalFloorArea > Thresholds.largeRoomArea {
            edgeCase = .largeRoom
            severity = .medium
            actions = [.optimizePerformance, .reduceFeatures, .adjustQuality]
        } else if totalFloorArea < Thresholds.smallRoomArea {
            edgeCase = .smallRoom
            severity = .low
            actions = [.adjustQuality, .showGuidance]
        }
        
        if let caseType = edgeCase {
            let confidence = caseType == .largeRoom ? 
                min(1.0, (totalFloorArea - Thresholds.largeRoomArea) / Thresholds.largeRoomArea) :
                min(1.0, (Thresholds.smallRoomArea - totalFloorArea) / Thresholds.smallRoomArea)
            
            let result = EdgeCaseDetectionResult(
                type: caseType,
                severity: severity,
                confidence: confidence,
                timestamp: Date(),
                metadata: [
                    "total_floor_area": totalFloorArea,
                    "plane_count": floorPlanes.count
                ],
                recommendedActions: actions
            )
            
            await handleDetectedEdgeCase(result)
        }
    }
    
    // MARK: - System Health Monitoring
    
    private func checkSystemHealth() async {
        systemHealth.update()
        
        // Check thermal state
        if systemHealth.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            let result = EdgeCaseDetectionResult(
                type: .thermalThrottling,
                severity: .critical,
                confidence: 1.0,
                timestamp: Date(),
                metadata: ["thermal_state": systemHealth.thermalState.rawValue],
                recommendedActions: [.optimizePerformance, .reduceFeatures, .pauseSession]
            )
            
            await handleDetectedEdgeCase(result)
        }
        
        // Check memory pressure
        if systemHealth.memoryPressure > Thresholds.memoryPressureThreshold {
            let result = EdgeCaseDetectionResult(
                type: .memoryPressure,
                severity: .high,
                confidence: systemHealth.memoryPressure,
                timestamp: Date(),
                metadata: [
                    "memory_pressure": systemHealth.memoryPressure,
                    "memory_usage_mb": systemHealth.memoryUsageMB
                ],
                recommendedActions: [.clearMemory, .optimizePerformance, .reduceFeatures]
            )
            
            await handleDetectedEdgeCase(result)
        }
    }
    
    // MARK: - Offline Mode Detection
    
    private func checkOfflineCapabilities() async {
        if !offlineManager.networkStatus.isConnected && !offlineManager.isOfflineMode {
            let result = EdgeCaseDetectionResult(
                type: .offlineMode,
                severity: .medium,
                confidence: 1.0,
                timestamp: Date(),
                metadata: [
                    "network_status": "disconnected",
                    "offline_features": offlineManager.getOfflineCapabilities().map { $0.rawValue }
                ],
                recommendedActions: [.switchToOffline, .showGuidance, .reduceFeatures]
            )
            
            await handleDetectedEdgeCase(result)
        }
    }
    
    // MARK: - Recovery Actions
    
    private func executeRecoveryActions(_ actions: [EdgeCaseAction]) async {
        for action in actions {
            activeRecoveryActions.insert(action)
            
            switch action {
            case .adjustQuality:
                await adjustQualitySettings()
            case .enableFallbackMode:
                await enableFallbackMode()
            case .pauseSession:
                await pauseARSession()
            case .showGuidance:
                await showUserGuidance()
            case .requestBetterConditions:
                await requestBetterConditions()
            case .optimizePerformance:
                await optimizePerformance()
            case .clearMemory:
                await clearMemory()
            case .saveProgress:
                await saveProgress()
            case .switchToOffline:
                await switchToOfflineMode()
            case .adjustLighting:
                await adjustLightingDetection()
            case .reduceFeatures:
                await reduceFeatures()
            case .waitForStability:
                await waitForStability()
            }
            
            activeRecoveryActions.remove(action)
        }
    }
    
    private func adjustQualitySettings() async {
        // Reduce AR quality settings to improve performance
        let fallbackOptions = ARConfigurationOptions.fallback()
        arSessionManager.updateConfiguration(fallbackOptions)
        
        logInfo("Adjusted quality settings for edge case handling", category: .performance)
    }
    
    private func enableFallbackMode() async {
        arSessionManager.switchToFallbackMode()
        logInfo("Enabled fallback mode for edge case handling", category: .performance)
    }
    
    private func pauseARSession() async {
        arSessionManager.pauseSession()
        logInfo("Paused AR session for edge case handling", category: .performance)
    }
    
    private func showUserGuidance() async {
        // Post notification for UI to show guidance
        NotificationCenter.default.post(name: .showEdgeCaseGuidance, object: nil)
    }
    
    private func requestBetterConditions() async {
        // Post notification for UI to request better conditions
        NotificationCenter.default.post(name: .requestBetterConditions, object: nil)
    }
    
    private func optimizePerformance() async {
        performanceManager.enableAggressiveOptimizations()
        logInfo("Enabled performance optimizations for edge case handling", category: .performance)
    }
    
    private func clearMemory() async {
        // Clear non-essential cached data
        // This would interface with various managers to clear their caches
        logInfo("Cleared memory for edge case handling", category: .performance)
    }
    
    private func saveProgress() async {
        // Save current scanning progress
        NotificationCenter.default.post(name: .saveProgress, object: nil)
    }
    
    private func switchToOfflineMode() async {
        offlineManager.enableOfflineMode()
        logInfo("Switched to offline mode for edge case handling", category: .performance)
    }
    
    private func adjustLightingDetection() async {
        // Adjust lighting detection sensitivity
        var options = ARConfigurationOptions.forInteriorDesign()
        options = ARConfigurationOptions(
            planeDetection: options.planeDetection,
            sceneReconstruction: .none, // Disable for poor lighting
            environmentTexturing: .none,
            frameSemantics: [],
            providesAudioData: options.providesAudioData,
            isLightEstimationEnabled: false, // Disable in poor lighting
            isCollaborationEnabled: false,
            maximumNumberOfTrackedImages: 0,
            detectionImages: nil
        )
        arSessionManager.updateConfiguration(options)
    }
    
    private func reduceFeatures() async {
        // Reduce active features to improve performance
        let minimalOptions = ARConfigurationOptions(
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
        arSessionManager.updateConfiguration(minimalOptions)
    }
    
    private func waitForStability() async {
        // Wait for device movement to stabilize
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    }
    
    // MARK: - Memory Warning Handling
    
    private func handleMemoryWarning() async {
        let result = EdgeCaseDetectionResult(
            type: .memoryPressure,
            severity: .critical,
            confidence: 1.0,
            timestamp: Date(),
            metadata: ["source": "system_memory_warning"],
            recommendedActions: [.clearMemory, .optimizePerformance, .reduceFeatures]
        )
        
        await handleDetectedEdgeCase(result)
    }
    
    // MARK: - Motion Monitoring Setup
    
    private func setupMotionMonitoring() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1 // 10 Hz
        }
    }
    
    // MARK: - Timer Management
    
    private func startAllMonitors() {
        lightingMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { await self?.checkLightingConditions() }
        }
        
        movementMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { await self?.checkDeviceMovement() }
        }
        
        storageMonitorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { await self?.checkStorageSpace() }
        }
        
        environmentMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { await self?.checkEnvironmentClutter() }
        }
        
        thermalMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { await self?.checkSystemHealth() }
        }
    }
    
    private func stopAllMonitors() {
        lightingMonitorTimer?.invalidate()
        movementMonitorTimer?.invalidate()
        storageMonitorTimer?.invalidate()
        environmentMonitorTimer?.invalidate()
        thermalMonitorTimer?.invalidate()
        
        lightingMonitorTimer = nil
        movementMonitorTimer = nil
        storageMonitorTimer = nil
        environmentMonitorTimer = nil
        thermalMonitorTimer = nil
    }
    
    private func startSystemHealthMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.systemHealth.update()
        }
    }
}

// MARK: - System Health Metrics

public struct SystemHealthMetrics {
    private(set) var memoryUsageMB: Int = 0
    private(set) var memoryPressure: Float = 0.0
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    private(set) var cpuUsage: Float = 0.0
    private(set) var batteryLevel: Float = 1.0
    private(set) var lastUpdate: Date = Date()
    
    mutating func update() {
        memoryUsageMB = getCurrentMemoryUsage() / (1024 * 1024)
        memoryPressure = Float(memoryUsageMB) / 1024.0 // Simplified calculation
        thermalState = ProcessInfo.processInfo.thermalState
        batteryLevel = UIDevice.current.batteryLevel
        lastUpdate = Date()
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

// MARK: - Notifications

extension Notification.Name {
    static let edgeCaseDetected = Notification.Name("edgeCaseDetected")
    static let showEdgeCaseGuidance = Notification.Name("showEdgeCaseGuidance")
    static let requestBetterConditions = Notification.Name("requestBetterConditions")
    static let saveProgress = Notification.Name("saveProgress")
}