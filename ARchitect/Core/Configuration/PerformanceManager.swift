import Foundation
import Combine
import UIKit
import MetalKit

// MARK: - Performance Metrics
struct PerformanceMetrics {
    let timestamp: Date
    let memoryUsageMB: Double
    let cpuUsagePercent: Double
    let frameRate: Double
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float
    let networkLatencyMs: Double?
    let renderingTimeMs: Double
    let arTrackingQuality: ARTrackingQuality
    
    enum ARTrackingQuality {
        case excellent
        case good
        case poor
        case unavailable
    }
}

// MARK: - Performance Thresholds
struct PerformanceThresholds {
    let memoryWarningMB: Double
    let memoryCriticalMB: Double
    let cpuWarningPercent: Double
    let cpuCriticalPercent: Double
    let frameRateWarning: Double
    let frameRateCritical: Double
    let batteryLowLevel: Float
    let batteryCriticalLevel: Float
    let networkTimeoutMs: Double
    let renderingTimeoutMs: Double
    let maxConcurrentOperations: Int
    let maxCacheSize: Int
    
    static func forEnvironment(_ environment: AppEnvironment) -> PerformanceThresholds {
        switch environment {
        case .development:
            return PerformanceThresholds(
                memoryWarningMB: 800,
                memoryCriticalMB: 1200,
                cpuWarningPercent: 80,
                cpuCriticalPercent: 95,
                frameRateWarning: 45,
                frameRateCritical: 30,
                batteryLowLevel: 0.2,
                batteryCriticalLevel: 0.1,
                networkTimeoutMs: 10000,
                renderingTimeoutMs: 33,
                maxConcurrentOperations: 10,
                maxCacheSize: 200 * 1024 * 1024
            )
        case .staging:
            return PerformanceThresholds(
                memoryWarningMB: 600,
                memoryCriticalMB: 800,
                cpuWarningPercent: 70,
                cpuCriticalPercent: 85,
                frameRateWarning: 50,
                frameRateCritical: 35,
                batteryLowLevel: 0.25,
                batteryCriticalLevel: 0.15,
                networkTimeoutMs: 8000,
                renderingTimeoutMs: 25,
                maxConcurrentOperations: 6,
                maxCacheSize: 100 * 1024 * 1024
            )
        case .production:
            return PerformanceThresholds(
                memoryWarningMB: 400,
                memoryCriticalMB: 600,
                cpuWarningPercent: 60,
                cpuCriticalPercent: 75,
                frameRateWarning: 55,
                frameRateCritical: 40,
                batteryLowLevel: 0.3,
                batteryCriticalLevel: 0.2,
                networkTimeoutMs: 5000,
                renderingTimeoutMs: 20,
                maxConcurrentOperations: 4,
                maxCacheSize: 50 * 1024 * 1024
            )
        }
    }
}

// MARK: - Performance Manager
class PerformanceManager: ObservableObject {
    static let shared = PerformanceManager()
    
    @Published private(set) var currentMetrics = PerformanceMetrics(
        timestamp: Date(),
        memoryUsageMB: 0,
        cpuUsagePercent: 0,
        frameRate: 60,
        thermalState: .nominal,
        batteryLevel: 1.0,
        networkLatencyMs: nil,
        renderingTimeMs: 16.67,
        arTrackingQuality: .unavailable
    )
    
    @Published private(set) var performanceState: PerformanceState = .optimal
    @Published private(set) var isThrottled = false
    @Published private(set) var activeOptimizations: [PerformanceOptimization] = []
    
    private let thresholds: PerformanceThresholds
    private let errorManager = ErrorManager.shared
    private let featureFlags = FeatureFlagManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private var metricsTimer: Timer?
    private var performanceHistory: [PerformanceMetrics] = []
    private let maxHistorySize = 100
    private let metricsUpdateInterval: TimeInterval = 1.0
    
    enum PerformanceState {
        case optimal
        case degraded
        case critical
    }
    
    enum PerformanceOptimization {
        case reduceFrameRate
        case disableComplexRendering
        case clearCaches
        case pauseBackgroundTasks
        case disableAnimations
        case reduceTextureQuality
        case limitConcurrentOperations
    }
    
    private init() {
        self.thresholds = PerformanceThresholds.forEnvironment(AppEnvironment.current)
        
        setupMonitoring()
        startMetricsCollection()
    }
    
    deinit {
        metricsTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func getCurrentMetrics() -> PerformanceMetrics {
        return currentMetrics
    }
    
    func getPerformanceHistory(last minutes: Int = 5) -> [PerformanceMetrics] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(minutes * 60))
        return performanceHistory.filter { $0.timestamp >= cutoff }
    }
    
    func forceOptimization(_ optimization: PerformanceOptimization) {
        if !activeOptimizations.contains(optimization) {
            activeOptimizations.append(optimization)
            applyOptimization(optimization)
        }
    }
    
    func removeOptimization(_ optimization: PerformanceOptimization) {
        activeOptimizations.removeAll { $0 == optimization }
        removeOptimizationEffect(optimization)
    }
    
    func resetOptimizations() {
        for optimization in activeOptimizations {
            removeOptimizationEffect(optimization)
        }
        activeOptimizations.removeAll()
        isThrottled = false
    }
    
    func checkMemoryPressure() -> MemoryPressureLevel {
        let memoryMB = currentMetrics.memoryUsageMB
        
        if memoryMB >= thresholds.memoryCriticalMB {
            return .critical
        } else if memoryMB >= thresholds.memoryWarningMB {
            return .warning
        } else {
            return .normal
        }
    }
    
    func triggerMemoryCleanup() {
        // Clear caches
        URLCache.shared.removeAllCachedResponses()
        
        // Clear image cache if available
        clearImageCaches()
        
        // Force garbage collection
        autoreleasepool {
            // Trigger memory cleanup operations
        }
        
        // Apply memory optimization
        forceOptimization(.clearCaches)
        
        // Update metrics immediately
        updateMetrics()
    }
    
    enum MemoryPressureLevel {
        case normal
        case warning
        case critical
    }
    
    // MARK: - Private Methods
    
    private func setupMonitoring() {
        // Monitor thermal state changes
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleThermalStateChange()
            }
            .store(in: &cancellables)
        
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
        // Monitor battery state changes
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateBatteryMetrics()
            }
            .store(in: &cancellables)
    }
    
    private func startMetricsCollection() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: metricsUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    private func updateMetrics() {
        let newMetrics = PerformanceMetrics(
            timestamp: Date(),
            memoryUsageMB: getCurrentMemoryUsage(),
            cpuUsagePercent: getCurrentCPUUsage(),
            frameRate: getCurrentFrameRate(),
            thermalState: ProcessInfo.processInfo.thermalState,
            batteryLevel: UIDevice.current.batteryLevel,
            networkLatencyMs: getCurrentNetworkLatency(),
            renderingTimeMs: getCurrentRenderingTime(),
            arTrackingQuality: getCurrentARTrackingQuality()
        )
        
        DispatchQueue.main.async {
            self.currentMetrics = newMetrics
            self.addToHistory(newMetrics)
            self.evaluatePerformanceState(newMetrics)
        }
    }
    
    private func addToHistory(_ metrics: PerformanceMetrics) {
        performanceHistory.append(metrics)
        
        if performanceHistory.count > maxHistorySize {
            performanceHistory.removeFirst()
        }
    }
    
    private func evaluatePerformanceState(_ metrics: PerformanceMetrics) {
        let previousState = performanceState
        var newState: PerformanceState = .optimal
        var requiredOptimizations: [PerformanceOptimization] = []
        
        // Check memory thresholds
        if metrics.memoryUsageMB >= thresholds.memoryCriticalMB {
            newState = .critical
            requiredOptimizations.append(.clearCaches)
            requiredOptimizations.append(.pauseBackgroundTasks)
        } else if metrics.memoryUsageMB >= thresholds.memoryWarningMB {
            newState = max(newState, .degraded)
            requiredOptimizations.append(.clearCaches)
        }
        
        // Check CPU thresholds
        if metrics.cpuUsagePercent >= thresholds.cpuCriticalPercent {
            newState = .critical
            requiredOptimizations.append(.limitConcurrentOperations)
            requiredOptimizations.append(.disableAnimations)
        } else if metrics.cpuUsagePercent >= thresholds.cpuWarningPercent {
            newState = max(newState, .degraded)
            requiredOptimizations.append(.limitConcurrentOperations)
        }
        
        // Check frame rate thresholds
        if metrics.frameRate <= thresholds.frameRateCritical {
            newState = .critical
            requiredOptimizations.append(.reduceFrameRate)
            requiredOptimizations.append(.disableComplexRendering)
        } else if metrics.frameRate <= thresholds.frameRateWarning {
            newState = max(newState, .degraded)
            requiredOptimizations.append(.reduceTextureQuality)
        }
        
        // Check thermal state
        if metrics.thermalState == .critical || metrics.thermalState == .serious {
            newState = .critical
            requiredOptimizations.append(.reduceFrameRate)
            requiredOptimizations.append(.disableComplexRendering)
            requiredOptimizations.append(.pauseBackgroundTasks)
        } else if metrics.thermalState == .fair {
            newState = max(newState, .degraded)
            requiredOptimizations.append(.reduceTextureQuality)
        }
        
        // Check battery level
        if metrics.batteryLevel <= thresholds.batteryCriticalLevel && metrics.batteryLevel > 0 {
            newState = .critical
            requiredOptimizations.append(.pauseBackgroundTasks)
            requiredOptimizations.append(.disableAnimations)
        } else if metrics.batteryLevel <= thresholds.batteryLowLevel && metrics.batteryLevel > 0 {
            newState = max(newState, .degraded)
        }
        
        performanceState = newState
        
        // Apply optimizations if needed
        if newState != .optimal {
            applyPerformanceOptimizations(requiredOptimizations)
        } else if previousState != .optimal && newState == .optimal {
            // Performance improved, remove some optimizations
            removeUnnecessaryOptimizations()
        }
        
        // Report performance issues
        if newState == .critical && previousState != .critical {
            reportPerformanceIssue(metrics)
        }
    }
    
    private func applyPerformanceOptimizations(_ optimizations: [PerformanceOptimization]) {
        for optimization in optimizations {
            if !activeOptimizations.contains(optimization) {
                activeOptimizations.append(optimization)
                applyOptimization(optimization)
            }
        }
        
        isThrottled = !activeOptimizations.isEmpty
    }
    
    private func applyOptimization(_ optimization: PerformanceOptimization) {
        switch optimization {
        case .reduceFrameRate:
            // Notify AR system to reduce frame rate
            NotificationCenter.default.post(name: .reduceFrameRate, object: nil)
            
        case .disableComplexRendering:
            // Disable advanced rendering features
            NotificationCenter.default.post(name: .disableComplexRendering, object: nil)
            
        case .clearCaches:
            triggerMemoryCleanup()
            
        case .pauseBackgroundTasks:
            // Pause non-essential background operations
            NotificationCenter.default.post(name: .pauseBackgroundTasks, object: nil)
            
        case .disableAnimations:
            // Disable UI animations
            UIView.setAnimationsEnabled(false)
            
        case .reduceTextureQuality:
            // Notify rendering system to reduce texture quality
            NotificationCenter.default.post(name: .reduceTextureQuality, object: nil)
            
        case .limitConcurrentOperations:
            // Reduce concurrent operation limits
            NotificationCenter.default.post(name: .limitConcurrentOperations, object: nil)
        }
    }
    
    private func removeOptimizationEffect(_ optimization: PerformanceOptimization) {
        switch optimization {
        case .reduceFrameRate:
            NotificationCenter.default.post(name: .restoreFrameRate, object: nil)
            
        case .disableComplexRendering:
            NotificationCenter.default.post(name: .enableComplexRendering, object: nil)
            
        case .clearCaches:
            // Cache clearing is not reversible
            break
            
        case .pauseBackgroundTasks:
            NotificationCenter.default.post(name: .resumeBackgroundTasks, object: nil)
            
        case .disableAnimations:
            UIView.setAnimationsEnabled(true)
            
        case .reduceTextureQuality:
            NotificationCenter.default.post(name: .restoreTextureQuality, object: nil)
            
        case .limitConcurrentOperations:
            NotificationCenter.default.post(name: .restoreConcurrentOperations, object: nil)
        }
    }
    
    private func removeUnnecessaryOptimizations() {
        // Remove optimizations that are no longer needed
        let optimizationsToRemove = activeOptimizations.filter { optimization in
            switch optimization {
            case .disableAnimations, .pauseBackgroundTasks:
                return performanceState == .optimal
            case .reduceTextureQuality:
                return currentMetrics.frameRate >= thresholds.frameRateWarning
            default:
                return false
            }
        }
        
        for optimization in optimizationsToRemove {
            removeOptimization(optimization)
        }
    }
    
    private func handleThermalStateChange() {
        updateMetrics()
        
        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState == .critical || thermalState == .serious {
            let error = SystemError.thermalThrottling
            errorManager.reportError(error, context: [
                "thermal_state": thermalState.rawValue,
                "current_metrics": formatMetricsForContext(currentMetrics)
            ])
        }
    }
    
    private func handleMemoryWarning() {
        triggerMemoryCleanup()
        
        let error = SystemError.memoryWarning
        errorManager.reportError(error, context: [
            "memory_usage_mb": currentMetrics.memoryUsageMB,
            "memory_threshold_mb": thresholds.memoryWarningMB
        ])
    }
    
    private func updateBatteryMetrics() {
        // Battery metrics are updated in the main metrics update cycle
        updateMetrics()
    }
    
    private func reportPerformanceIssue(_ metrics: PerformanceMetrics) {
        let error = SystemError.performanceDegradation
        errorManager.reportError(error, context: [
            "performance_metrics": formatMetricsForContext(metrics),
            "active_optimizations": activeOptimizations.map { "\($0)" },
            "performance_state": "\(performanceState)"
        ])
    }
    
    private func formatMetricsForContext(_ metrics: PerformanceMetrics) -> [String: Any] {
        return [
            "memory_mb": metrics.memoryUsageMB,
            "cpu_percent": metrics.cpuUsagePercent,
            "frame_rate": metrics.frameRate,
            "thermal_state": metrics.thermalState.rawValue,
            "battery_level": metrics.batteryLevel,
            "rendering_time_ms": metrics.renderingTimeMs
        ]
    }
    
    // MARK: - System Metrics Collection
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        return Double(info.resident_size) / 1024 / 1024 // Convert to MB
    }
    
    private func getCurrentCPUUsage() -> Double {
        var info = task_info_t()
        var count = mach_msg_type_number_t(TASK_INFO_MAX)
        
        let result = task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), &info, &count)
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        // This is a simplified CPU usage calculation
        // In a real implementation, you'd want to track CPU usage over time
        return Double.random(in: 0...100) // Placeholder
    }
    
    private func getCurrentFrameRate() -> Double {
        // This would typically be provided by the rendering system
        // For now, return a simulated value
        return 60.0 - (currentMetrics.memoryUsageMB / 10) // Simplified simulation
    }
    
    private func getCurrentNetworkLatency() -> Double? {
        // This would be measured by network requests
        return nil
    }
    
    private func getCurrentRenderingTime() -> Double {
        // This would be provided by the rendering system
        return 16.67 // 60 FPS = 16.67ms per frame
    }
    
    private func getCurrentARTrackingQuality() -> PerformanceMetrics.ARTrackingQuality {
        // This would be provided by ARSessionManager
        return .good
    }
    
    private func clearImageCaches() {
        // Clear any image caches your app might have
        // This is app-specific implementation
    }
}

// MARK: - Performance Notifications
extension Notification.Name {
    static let reduceFrameRate = Notification.Name("reduceFrameRate")
    static let restoreFrameRate = Notification.Name("restoreFrameRate")
    static let disableComplexRendering = Notification.Name("disableComplexRendering")
    static let enableComplexRendering = Notification.Name("enableComplexRendering")
    static let pauseBackgroundTasks = Notification.Name("pauseBackgroundTasks")
    static let resumeBackgroundTasks = Notification.Name("resumeBackgroundTasks")
    static let reduceTextureQuality = Notification.Name("reduceTextureQuality")
    static let restoreTextureQuality = Notification.Name("restoreTextureQuality")
    static let limitConcurrentOperations = Notification.Name("limitConcurrentOperations")
    static let restoreConcurrentOperations = Notification.Name("restoreConcurrentOperations")
}

// MARK: - Performance Optimization Extensions
extension PerformanceManager.PerformanceOptimization: Equatable {
    static func == (lhs: PerformanceManager.PerformanceOptimization, rhs: PerformanceManager.PerformanceOptimization) -> Bool {
        switch (lhs, rhs) {
        case (.reduceFrameRate, .reduceFrameRate),
             (.disableComplexRendering, .disableComplexRendering),
             (.clearCaches, .clearCaches),
             (.pauseBackgroundTasks, .pauseBackgroundTasks),
             (.disableAnimations, .disableAnimations),
             (.reduceTextureQuality, .reduceTextureQuality),
             (.limitConcurrentOperations, .limitConcurrentOperations):
            return true
        default:
            return false
        }
    }
}

extension PerformanceManager.PerformanceState: Comparable {
    static func < (lhs: PerformanceManager.PerformanceState, rhs: PerformanceManager.PerformanceState) -> Bool {
        let lhsValue = lhs.rawValue
        let rhsValue = rhs.rawValue
        return lhsValue < rhsValue
    }
    
    private var rawValue: Int {
        switch self {
        case .optimal: return 0
        case .degraded: return 1
        case .critical: return 2
        }
    }
    
    static func max(_ lhs: PerformanceManager.PerformanceState, _ rhs: PerformanceManager.PerformanceState) -> PerformanceManager.PerformanceState {
        return lhs > rhs ? lhs : rhs
    }
}